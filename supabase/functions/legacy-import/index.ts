import { createClient } from "npm:@supabase/supabase-js@2.116.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function envJsonKey(name: string): string | null {
  const raw = Deno.env.get(name);
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw);
    const value = parsed.default ?? Object.values(parsed)[0];
    return typeof value === "string" ? value : null;
  } catch (_) {
    return raw;
  }
}

function randomPassword() {
  const bytes = crypto.getRandomValues(new Uint8Array(24));
  return `${Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join("")}Aa1!`;
}

function safeAmount(value: unknown): number {
  const n = Number(value ?? 0);
  if (!Number.isFinite(n) || n < 0) throw new Error("invalid_amount");
  return Math.round(n * 100) / 100;
}

type ImportEntityKind = "customer" | "debt" | "payment";

async function findPreviousTarget(
  admin: any,
  adminId: string,
  entityKind: ImportEntityKind,
  sourceId: string,
): Promise<{ targetId: string | null; conflict: boolean }> {
  const { data, error } = await admin
    .from("legacy_import_links")
    .select("target_id")
    .eq("admin_id", adminId)
    .eq("entity_kind", entityKind)
    .eq("source_id", sourceId)
    .limit(20);
  if (error) throw error;

  const targetIds: string[] = [
    ...new Set<string>(
      (data ?? []).map((row: { target_id: string }) => row.target_id),
    ),
  ];
  return {
    targetId: targetIds.length === 1 ? (targetIds[0] ?? null) : null,
    conflict: targetIds.length > 1,
  };
}

async function addFingerprintLink(
  admin: any,
  adminId: string,
  fingerprint: string,
  entityKind: ImportEntityKind,
  sourceId: string,
  targetId: string,
) {
  const { error } = await admin.from("legacy_import_links").upsert({
    admin_id: adminId,
    source_fingerprint: fingerprint,
    entity_kind: entityKind,
    source_id: sourceId,
    target_id: targetId,
  }, {
    onConflict: "admin_id,source_fingerprint,entity_kind,source_id",
    ignoreDuplicates: true,
  });
  if (error) throw error;
}

function sameInstant(left: unknown, right: unknown): boolean {
  const leftMs = Date.parse(String(left ?? ""));
  const rightMs = Date.parse(String(right ?? ""));
  return Number.isFinite(leftMs) && Number.isFinite(rightMs) && leftMs === rightMs;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const secret = envJsonKey("SUPABASE_SECRET_KEYS") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!secret) return json({ error: "server_not_configured" }, 500);

  const admin = createClient(url, secret, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
    if (!token) return json({ error: "unauthorized" }, 401);

    const { data: authData, error: authError } = await admin.auth.getUser(token);
    if (authError || !authData.user) return json({ error: "unauthorized" }, 401);

    const { data: profile, error: profileError } = await admin
      .from("profiles")
      .select("id, role, active, approved, subscription_end, market_name, can_import_data, is_system_owner")
      .eq("id", authData.user.id)
      .maybeSingle();
    if (profileError || !profile) return json({ error: "profile_not_found" }, 403);
    if (profile.role !== "admin" || profile.is_system_owner === true) {
      return json({ error: "admin_required" }, 403);
    }
    if (profile.active !== true || profile.approved !== true) {
      return json({ error: "account_inactive" }, 403);
    }
    if (profile.subscription_end) {
      const end = Date.parse(String(profile.subscription_end));
      if (Number.isFinite(end) && end < Date.now()) {
        return json({ error: "subscription_expired" }, 403);
      }
    }
    if (profile.can_import_data !== true) {
      return json({ error: "import_permission_required" }, 403);
    }

    const body = await req.json();
    const action = String(body.action ?? "preflight");
    const adminId = profile.id as string;

    if (action === "preflight") {
      return json({
        ok: true,
        admin_id: adminId,
        market_name: profile.market_name ?? "",
        can_import_data: true,
      });
    }

    const fingerprint = String(body.source_fingerprint ?? "").trim();
    if (!fingerprint || fingerprint.length < 16) {
      return json({ error: "invalid_fingerprint" }, 400);
    }

    if (action === "start") {
      const expectedCustomers = Math.max(0, Number(body.expected_customers ?? 0) | 0);
      const expectedDebts = Math.max(0, Number(body.expected_debts ?? 0) | 0);
      const expectedPayments = Math.max(0, Number(body.expected_payments ?? 0) | 0);
      const expectedBalance = safeAmount(body.expected_balance_iqd ?? 0);
      const sourceMarket = String(body.source_market_name ?? "").trim();
      if (sourceMarket && profile.market_name && sourceMarket !== profile.market_name) {
        return json({ error: "market_mismatch" }, 409);
      }

      const { data: existing } = await admin
        .from("legacy_import_jobs")
        .select("*")
        .eq("admin_id", adminId)
        .eq("source_fingerprint", fingerprint)
        .maybeSingle();
      if (existing) return json({ ok: true, job: existing, resumed: true });

      const { data: job, error } = await admin
        .from("legacy_import_jobs")
        .insert({
          admin_id: adminId,
          source_fingerprint: fingerprint,
          source_name: String(body.source_name ?? ""),
          source_market_name: sourceMarket,
          status: "running",
          expected_customers: expectedCustomers,
          expected_debts: expectedDebts,
          expected_payments: expectedPayments,
          expected_balance_iqd: expectedBalance,
        })
        .select()
        .single();
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true, job, resumed: false });
    }

    const { data: job, error: jobError } = await admin
      .from("legacy_import_jobs")
      .select("*")
      .eq("admin_id", adminId)
      .eq("source_fingerprint", fingerprint)
      .maybeSingle();
    if (jobError || !job) return json({ error: "import_job_not_found" }, 404);
    if (job.status === "completed" && action !== "status") {
      return json({ ok: true, job, already_completed: true });
    }

    if (action === "status") return json({ ok: true, job });

    if (action === "customers") {
      const rows = Array.isArray(body.rows) ? body.rows : [];
      if (rows.length === 0 || rows.length > 100) return json({ error: "invalid_batch" }, 400);
      let imported = 0;
      let reused = 0;

      for (const raw of rows) {
        const sourceId = String(raw.source_id ?? raw.legacy_customer_id ?? "").trim();
        const name = String(raw.name ?? "").trim();
        if (!sourceId || !name) return json({ error: "invalid_customer_row", source_id: sourceId }, 400);

        const { data: link } = await admin
          .from("legacy_import_links")
          .select("target_id")
          .eq("admin_id", adminId)
          .eq("source_fingerprint", fingerprint)
          .eq("entity_kind", "customer")
          .eq("source_id", sourceId)
          .maybeSingle();
        if (link) continue;

        const previous = await findPreviousTarget(admin, adminId, "customer", sourceId);
        if (previous.conflict) {
          return json({ error: "source_id_conflict", entity_kind: "customer", source_id: sourceId }, 409);
        }
        if (previous.targetId) {
          const { data: previousCustomer } = await admin.from("profiles")
            .select("id, role, admin_id")
            .eq("id", previous.targetId)
            .maybeSingle();
          if (!previousCustomer || previousCustomer.role !== "customer" || previousCustomer.admin_id !== adminId) {
            return json({ error: "source_id_conflict", entity_kind: "customer", source_id: sourceId }, 409);
          }
          await addFingerprintLink(admin, adminId, fingerprint, "customer", sourceId, previous.targetId);
          imported++;
          reused++;
          continue;
        }

        let phone = String(raw.phone ?? raw.source_phone ?? "").trim();
        if (!phone) phone = `legacy_${adminId.slice(0, 8)}_${sourceId}`;

        const { data: existingProfile } = await admin
          .from("profiles")
          .select("id, role, admin_id")
          .eq("phone", phone)
          .maybeSingle();

        let customerId: string;
        if (existingProfile) {
          if (existingProfile.role !== "customer" || existingProfile.admin_id !== adminId) {
            return json({ error: "phone_collision", source_id: sourceId, phone }, 409);
          }
          customerId = existingProfile.id;
        } else {
          const email = `${phone}@zhirox.local`;
          const { data: createdAuth, error: createAuthError } = await admin.auth.admin.createUser({
            email,
            password: randomPassword(),
            email_confirm: true,
            user_metadata: {
              imported: true,
              legacy_source_id: sourceId,
              admin_id: adminId,
            },
          });
          if (createAuthError || !createdAuth.user) {
            return json({ error: createAuthError?.message ?? "auth_create_failed", source_id: sourceId }, 400);
          }
          customerId = createdAuth.user.id;
          const { error: insertProfileError } = await admin.from("profiles").insert({
            id: customerId,
            name,
            father_name: String(raw.father_name ?? ""),
            grandfather_name: String(raw.grandfather_name ?? ""),
            phone,
            role: "customer",
            market_name: "",
            admin_id: adminId,
            created_by: adminId,
            approved: true,
            active: true,
            debt_limit: safeAmount(raw.debt_limit ?? 0),
            debt_duration: Math.max(1, Number(raw.debt_duration ?? 30) | 0),
            is_system_owner: false,
          });
          if (insertProfileError) {
            await admin.auth.admin.deleteUser(customerId);
            return json({ error: insertProfileError.message, source_id: sourceId }, 400);
          }
        }

        const { error: linkError } = await admin.from("legacy_import_links").insert({
          admin_id: adminId,
          source_fingerprint: fingerprint,
          entity_kind: "customer",
          source_id: sourceId,
          target_id: customerId,
        });
        if (linkError) return json({ error: linkError.message }, 400);
        imported++;
      }

      if (imported > 0) {
        const { error: progressError } = await admin.rpc(
          "increment_legacy_import_progress",
          {
            p_job_id: job.id,
            p_customers: imported,
            p_debts: 0,
            p_payments: 0,
          },
        );
        if (progressError) {
          console.warn("legacy_import_progress_update_failed", progressError.message);
        }
        const { data: links } = await admin
          .from("legacy_import_links")
          .select("source_id", { count: "exact", head: true })
          .eq("admin_id", adminId)
          .eq("source_fingerprint", fingerprint)
          .eq("entity_kind", "customer");
        void links;
      }
      const { count } = await admin
        .from("legacy_import_links")
        .select("source_id", { count: "exact", head: true })
        .eq("admin_id", adminId)
        .eq("source_fingerprint", fingerprint)
        .eq("entity_kind", "customer");
      await admin.from("legacy_import_jobs").update({ imported_customers: count ?? 0, updated_at: new Date().toISOString() }).eq("id", job.id);
      return json({ ok: true, imported, reused, total_imported: count ?? 0 });
    }

    if (action === "debts") {
      const rows = Array.isArray(body.rows) ? body.rows : [];
      if (rows.length === 0 || rows.length > 150) return json({ error: "invalid_batch" }, 400);
      let imported = 0;
      let reused = 0;
      for (const raw of rows) {
        const sourceId = String(raw.source_id ?? raw.legacy_transaction_id ?? "").trim();
        const customerSourceId = String(raw.customer_source_id ?? raw.legacy_customer_id ?? "").trim();
        if (!sourceId || !customerSourceId) return json({ error: "invalid_debt_row" }, 400);

        const { data: existingLink } = await admin.from("legacy_import_links")
          .select("target_id")
          .eq("admin_id", adminId).eq("source_fingerprint", fingerprint)
          .eq("entity_kind", "debt").eq("source_id", sourceId).maybeSingle();
        if (existingLink) continue;

        const { data: customerLink } = await admin.from("legacy_import_links")
          .select("target_id")
          .eq("admin_id", adminId).eq("source_fingerprint", fingerprint)
          .eq("entity_kind", "customer").eq("source_id", customerSourceId).maybeSingle();
        if (!customerLink) return json({ error: "customer_mapping_missing", source_id: sourceId }, 409);

        const amount = safeAmount(raw.amount);
        if (amount <= 0) return json({ error: "invalid_amount", source_id: sourceId }, 400);
        const occurredAt = String(raw.occurred_at ?? raw.custom_date ?? raw.created_at ?? new Date().toISOString());
        const description = String(raw.description ?? raw.note ?? "");
        const currency = String(raw.currency ?? "IQD");

        const previous = await findPreviousTarget(admin, adminId, "debt", sourceId);
        if (previous.conflict) {
          return json({ error: "source_id_conflict", entity_kind: "debt", source_id: sourceId }, 409);
        }
        if (previous.targetId) {
          const { data: previousDebt } = await admin.from("debts")
            .select("id, customer_id, amount, description, currency, custom_date, created_at, created_by")
            .eq("id", previous.targetId)
            .maybeSingle();
          const previousOccurredAt = previousDebt?.custom_date ?? previousDebt?.created_at;
          const matches = previousDebt
            && previousDebt.created_by === adminId
            && previousDebt.customer_id === customerLink.target_id
            && safeAmount(previousDebt.amount) === amount
            && String(previousDebt.description ?? "") === description
            && String(previousDebt.currency ?? "IQD") === currency
            && sameInstant(previousOccurredAt, occurredAt);
          if (!matches) {
            return json({ error: "source_id_conflict", entity_kind: "debt", source_id: sourceId }, 409);
          }
          await addFingerprintLink(admin, adminId, fingerprint, "debt", sourceId, previous.targetId);
          imported++;
          reused++;
          continue;
        }

        const debtId = crypto.randomUUID();
        const { error: debtError } = await admin.from("debts").insert({
          id: debtId,
          customer_id: customerLink.target_id,
          description,
          amount,
          remaining: amount,
          due_date: null,
          status: "pending",
          created_by: adminId,
          currency,
          dollar_rate: 0,
          amount_usd: currency === "USD" ? amount : 0,
          items: [],
          custom_date: occurredAt,
          receipt_image_path: "",
          created_at: occurredAt,
          updated_at: occurredAt,
          reference_snapshot: {
            source: "legacy_import",
            source_id: sourceId,
            source_fingerprint: fingerprint,
          },
          subtotal: amount,
          discount_percent: 0,
          discount_amount: 0,
        });
        if (debtError) return json({ error: debtError.message, source_id: sourceId }, 400);
        const { error: linkError } = await admin.from("legacy_import_links").insert({
          admin_id: adminId,
          source_fingerprint: fingerprint,
          entity_kind: "debt",
          source_id: sourceId,
          target_id: debtId,
        });
        if (linkError) return json({ error: linkError.message }, 400);
        imported++;
      }
      const { count } = await admin.from("legacy_import_links")
        .select("source_id", { count: "exact", head: true })
        .eq("admin_id", adminId).eq("source_fingerprint", fingerprint).eq("entity_kind", "debt");
      await admin.from("legacy_import_jobs").update({ imported_debts: count ?? 0, updated_at: new Date().toISOString() }).eq("id", job.id);
      return json({ ok: true, imported, reused, total_imported: count ?? 0 });
    }

    if (action === "payments") {
      const rows = Array.isArray(body.rows) ? body.rows : [];
      if (rows.length === 0 || rows.length > 150) return json({ error: "invalid_batch" }, 400);
      let imported = 0;
      let reused = 0;

      for (const raw of rows) {
        const sourceId = String(
          raw.source_id ??
            `${raw.legacy_transaction_id ?? ""}:${raw.allocation_part ?? "1"}`,
        ).trim();
        const debtSourceId = String(
          raw.debt_source_id ??
            raw.legacy_debt_transaction_id ??
            raw.debt_legacy_transaction_id ??
            "",
        ).trim();
        const paymentScope = String(
          raw.payment_scope ?? (debtSourceId ? "debt" : "general"),
        ).trim().toLowerCase();
        const customerSourceId = String(
          raw.customer_source_id ?? raw.legacy_customer_id ?? "",
        ).trim();

        if (!sourceId || (paymentScope !== "debt" && paymentScope !== "general")) {
          return json({ error: "invalid_payment_row", source_id: sourceId }, 400);
        }
        if (paymentScope === "debt" && !debtSourceId) {
          return json({ error: "invalid_payment_row", source_id: sourceId }, 400);
        }
        if (paymentScope === "general" && !customerSourceId) {
          return json({ error: "invalid_general_payment_row", source_id: sourceId }, 400);
        }

        const { data: existingLink } = await admin.from("legacy_import_links")
          .select("target_id")
          .eq("admin_id", adminId).eq("source_fingerprint", fingerprint)
          .eq("entity_kind", "payment").eq("source_id", sourceId).maybeSingle();
        if (existingLink) continue;

        const amount = safeAmount(raw.amount);
        if (amount <= 0) {
          return json({ error: "invalid_amount", source_id: sourceId }, 400);
        }
        const occurredAt = String(
          raw.occurred_at ?? raw.created_at ?? new Date().toISOString(),
        );
        const note = String(raw.note ?? "");

        const previous = await findPreviousTarget(admin, adminId, "payment", sourceId);
        if (previous.conflict) {
          return json({
            error: "source_id_conflict",
            entity_kind: "payment",
            source_id: sourceId,
          }, 409);
        }

        if (paymentScope === "general") {
          const { data: customerLink } = await admin.from("legacy_import_links")
            .select("target_id")
            .eq("admin_id", adminId).eq("source_fingerprint", fingerprint)
            .eq("entity_kind", "customer").eq("source_id", customerSourceId)
            .maybeSingle();
          if (!customerLink) {
            return json({
              error: "customer_mapping_missing",
              source_id: sourceId,
              customer_source_id: customerSourceId,
            }, 409);
          }

          if (previous.targetId) {
            const { data: previousGeneral } = await admin
              .from("customer_general_payments")
              .select("id, admin_id, customer_id, amount, note, created_at, created_by")
              .eq("id", previous.targetId)
              .maybeSingle();
            const matches = previousGeneral
              && previousGeneral.admin_id === adminId
              && previousGeneral.customer_id === customerLink.target_id
              && previousGeneral.created_by === adminId
              && safeAmount(previousGeneral.amount) === amount
              && String(previousGeneral.note ?? "") === note
              && sameInstant(previousGeneral.created_at, occurredAt);
            if (!matches) {
              return json({
                error: "source_id_conflict",
                entity_kind: "payment",
                payment_scope: "general",
                source_id: sourceId,
              }, 409);
            }
            await addFingerprintLink(
              admin,
              adminId,
              fingerprint,
              "payment",
              sourceId,
              previous.targetId,
            );
            imported++;
            reused++;
            continue;
          }

          const { data: generalPaymentId, error: generalPaymentError } =
            await admin.rpc("legacy_import_apply_general_payment", {
              p_admin_id: adminId,
              p_customer_id: customerLink.target_id,
              p_source_fingerprint: fingerprint,
              p_source_id: sourceId,
              p_amount: amount,
              p_note: note,
              p_created_at: occurredAt,
            });
          if (generalPaymentError || !generalPaymentId) {
            return json({
              error: generalPaymentError?.message ?? "general_payment_import_failed",
              source_id: sourceId,
            }, 400);
          }

          const { error: linkError } = await admin.from("legacy_import_links").insert({
            admin_id: adminId,
            source_fingerprint: fingerprint,
            entity_kind: "payment",
            source_id: sourceId,
            target_id: generalPaymentId,
          });
          if (linkError) return json({ error: linkError.message }, 400);
          imported++;
          continue;
        }

        const { data: debtLink } = await admin.from("legacy_import_links")
          .select("target_id")
          .eq("admin_id", adminId).eq("source_fingerprint", fingerprint)
          .eq("entity_kind", "debt").eq("source_id", debtSourceId).maybeSingle();
        if (!debtLink) {
          return json({
            error: "debt_mapping_missing",
            source_id: sourceId,
            debt_source_id: debtSourceId,
          }, 409);
        }

        if (previous.targetId) {
          const { data: previousPayment } = await admin.from("payments")
            .select("id, debt_id, amount, note, created_at, created_by")
            .eq("id", previous.targetId)
            .maybeSingle();
          const matches = previousPayment
            && previousPayment.created_by === adminId
            && previousPayment.debt_id === debtLink.target_id
            && safeAmount(previousPayment.amount) === amount
            && String(previousPayment.note ?? "") === note
            && sameInstant(previousPayment.created_at, occurredAt);
          if (!matches) {
            return json({
              error: "source_id_conflict",
              entity_kind: "payment",
              payment_scope: "debt",
              source_id: sourceId,
            }, 409);
          }
          await addFingerprintLink(
            admin,
            adminId,
            fingerprint,
            "payment",
            sourceId,
            previous.targetId,
          );
          imported++;
          reused++;
          continue;
        }

        const paymentId = crypto.randomUUID();
        const { error: paymentError } = await admin.rpc("legacy_import_apply_payment", {
          p_admin_id: adminId,
          p_debt_id: debtLink.target_id,
          p_payment_id: paymentId,
          p_amount: amount,
          p_note: note,
          p_created_at: occurredAt,
        });
        if (paymentError) {
          return json({ error: paymentError.message, source_id: sourceId }, 400);
        }

        const { error: linkError } = await admin.from("legacy_import_links").insert({
          admin_id: adminId,
          source_fingerprint: fingerprint,
          entity_kind: "payment",
          source_id: sourceId,
          target_id: paymentId,
        });
        if (linkError) return json({ error: linkError.message }, 400);
        imported++;
      }

      const { count } = await admin.from("legacy_import_links")
        .select("source_id", { count: "exact", head: true })
        .eq("admin_id", adminId)
        .eq("source_fingerprint", fingerprint)
        .eq("entity_kind", "payment");
      await admin.from("legacy_import_jobs").update({
        imported_payments: count ?? 0,
        updated_at: new Date().toISOString(),
      }).eq("id", job.id);
      return json({ ok: true, imported, reused, total_imported: count ?? 0 });
    }

    if (action === "finalize") {
      const { data: debtLinks, error: debtLinksError } = await admin
        .from("legacy_import_links")
        .select("target_id")
        .eq("admin_id", adminId)
        .eq("source_fingerprint", fingerprint)
        .eq("entity_kind", "debt");
      if (debtLinksError) return json({ error: debtLinksError.message }, 400);

      const debtIds = (debtLinks ?? []).map((row: { target_id: string }) => row.target_id);
      let grossBalanceIqd = 0;
      for (let i = 0; i < debtIds.length; i += 500) {
        const { data: debts, error } = await admin.from("debts")
          .select("remaining, currency")
          .in("id", debtIds.slice(i, i + 500))
          .eq("is_deleted", false);
        if (error) return json({ error: error.message }, 400);
        for (const debt of debts ?? []) {
          if (String(debt.currency ?? "IQD").toUpperCase() === "IQD") {
            grossBalanceIqd += Number(debt.remaining ?? 0);
          }
        }
      }

      const { data: paymentLinks, error: paymentLinksError } = await admin
        .from("legacy_import_links")
        .select("target_id")
        .eq("admin_id", adminId)
        .eq("source_fingerprint", fingerprint)
        .eq("entity_kind", "payment");
      if (paymentLinksError) return json({ error: paymentLinksError.message }, 400);

      const paymentTargetIds = (paymentLinks ?? [])
        .map((row: { target_id: string }) => row.target_id);
      let generalPaidIqd = 0;
      for (let i = 0; i < paymentTargetIds.length; i += 500) {
        const ids = paymentTargetIds.slice(i, i + 500);
        if (ids.length === 0) continue;
        const { data: generalPayments, error } = await admin
          .from("customer_general_payments")
          .select("amount")
          .eq("admin_id", adminId)
          .in("id", ids);
        if (error) return json({ error: error.message }, 400);
        for (const payment of generalPayments ?? []) {
          generalPaidIqd += Number(payment.amount ?? 0);
        }
      }

      const grossRounded = Math.round(grossBalanceIqd * 100) / 100;
      const generalRounded = Math.round(generalPaidIqd * 100) / 100;
      const balance = Math.round(
        Math.max(grossRounded - generalRounded, 0) * 100,
      ) / 100;
      const expected = Number(job.expected_balance_iqd ?? 0);
      const countsOk =
        Number(job.imported_customers) === Number(job.expected_customers)
        && Number(job.imported_debts) === Number(job.expected_debts)
        && Number(job.imported_payments) === Number(job.expected_payments);
      const balanceOk = Math.abs(balance - expected) < 0.01;

      if (!countsOk || !balanceOk) {
        await admin.from("legacy_import_jobs").update({
          status: "failed",
          verified_balance_iqd: balance,
          last_error: !countsOk ? "count_mismatch" : "balance_mismatch",
          updated_at: new Date().toISOString(),
        }).eq("id", job.id);
        return json({
          error: !countsOk ? "count_mismatch" : "balance_mismatch",
          verified_balance_iqd: balance,
          gross_balance_iqd: grossRounded,
          general_paid_iqd: generalRounded,
          job,
        }, 409);
      }

      const { data: completed, error } = await admin.from("legacy_import_jobs")
        .update({
          status: "completed",
          verified_balance_iqd: balance,
          last_error: null,
          updated_at: new Date().toISOString(),
          completed_at: new Date().toISOString(),
        })
        .eq("id", job.id)
        .select()
        .single();
      if (error) return json({ error: error.message }, 400);
      return json({
        ok: true,
        job: completed,
        verified_balance_iqd: balance,
        gross_balance_iqd: grossRounded,
        general_paid_iqd: generalRounded,
      });
    }

    return json({ error: "unsupported_action" }, 400);
  } catch (error) {
    console.error(error);
    return json({ error: error instanceof Error ? error.message : "internal_error" }, 500);
  }
});
