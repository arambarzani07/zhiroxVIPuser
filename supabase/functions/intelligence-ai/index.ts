import { createClient } from "npm:@supabase/supabase-js@2.116.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

function envJsonKey(name: string): string | null {
  const raw = Deno.env.get(name);
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw);
    return parsed.default ?? Object.values(parsed)[0] ?? null;
  } catch (_) {
    return raw;
  }
}

function num(value: unknown): number {
  const n = Number(value ?? 0);
  return Number.isFinite(n) ? n : 0;
}

function isoDay(value: Date): string {
  return value.toISOString().slice(0, 10);
}

function dayDiff(later: Date, earlier: Date): number {
  return Math.max(0, Math.floor((later.getTime() - earlier.getTime()) / 86_400_000));
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function fetchAll(
  admin: any,
  table: string,
  columns: string,
  configure: (query: any) => any,
): Promise<Record<string, unknown>[]> {
  const rows: Record<string, unknown>[] = [];
  const pageSize = 1000;
  for (let from = 0; ; from += pageSize) {
    let query = admin.from(table).select(columns);
    query = configure(query);
    const { data, error } = await query.range(from, from + pageSize - 1);
    if (error) throw error;
    const page = (data ?? []) as Record<string, unknown>[];
    rows.push(...page);
    if (page.length < pageSize) break;
  }
  return rows;
}

async function fetchDebtsForCustomers(
  admin: any,
  customerIds: string[],
): Promise<Record<string, unknown>[]> {
  const rows: Record<string, unknown>[] = [];
  const chunkSize = 80;
  const pageSize = 1000;
  for (let i = 0; i < customerIds.length; i += chunkSize) {
    const chunk = customerIds.slice(i, i + chunkSize);
    for (let from = 0; ; from += pageSize) {
      const { data, error } = await admin
        .from("debts")
        .select("id,customer_id,amount,remaining,due_date,status,currency,created_at")
        .in("customer_id", chunk)
        .eq("is_deleted", false)
        .range(from, from + pageSize - 1);
      if (error) throw error;
      const page = (data ?? []) as Record<string, unknown>[];
      rows.push(...page);
      if (page.length < pageSize) break;
    }
  }
  return rows;
}

async function fetchPaymentsForCustomers(
  admin: any,
  customerIds: string[],
): Promise<Record<string, unknown>[]> {
  const rows: Record<string, unknown>[] = [];
  const chunkSize = 80;
  const pageSize = 1000;
  for (let i = 0; i < customerIds.length; i += chunkSize) {
    const chunk = customerIds.slice(i, i + chunkSize);
    for (let from = 0; ; from += pageSize) {
      const { data, error } = await admin
        .from("payments")
        .select("id,debt_id,amount,created_at,debts!inner(customer_id,currency)")
        .in("debts.customer_id", chunk)
        .range(from, from + pageSize - 1);
      if (error) throw error;
      const page = (data ?? []) as Record<string, unknown>[];
      rows.push(...page);
      if (page.length < pageSize) break;
    }
  }
  return rows;
}

type RiskRow = {
  customer_id: string;
  name: string;
  risk_score: number;
  remaining_iqd: number;
  overdue_iqd: number;
  max_overdue_days: number;
  open_debts: number;
};

function buildSnapshot(
  profile: Record<string, unknown>,
  customers: Record<string, unknown>[],
  debts: Record<string, unknown>[],
  payments: Record<string, unknown>[],
) {
  const now = new Date();
  const today = isoDay(now);
  const in7 = new Date(now.getTime() + 7 * 86_400_000);
  const in30 = new Date(now.getTime() + 30 * 86_400_000);
  const ago30 = new Date(now.getTime() - 30 * 86_400_000);
  const ago60 = new Date(now.getTime() - 60 * 86_400_000);

  let openCount = 0;
  let remainingIqd = 0;
  let remainingUsd = 0;
  let overdueCount = 0;
  let overdueIqd = 0;
  let due7Count = 0;
  let due7Iqd = 0;
  let due30Count = 0;
  let due30Iqd = 0;

  const riskByCustomer = new Map<string, {
    remaining: number;
    overdue: number;
    maxOverdueDays: number;
    openCount: number;
  }>();

  for (const debt of debts) {
    const remaining = Math.max(0, num(debt.remaining));
    if (remaining <= 0) continue;
    const currency = String(debt.currency ?? "IQD").toUpperCase();
    const customerId = String(debt.customer_id ?? "");
    const dueRaw = String(debt.due_date ?? "");
    const due = dueRaw ? new Date(`${dueRaw}T00:00:00Z`) : null;
    openCount += 1;

    if (currency === "USD") {
      remainingUsd += remaining;
      continue;
    }
    if (currency !== "IQD") continue;

    remainingIqd += remaining;
    const risk = riskByCustomer.get(customerId) ?? {
      remaining: 0,
      overdue: 0,
      maxOverdueDays: 0,
      openCount: 0,
    };
    risk.remaining += remaining;
    risk.openCount += 1;

    if (due && !Number.isNaN(due.getTime())) {
      const dueDay = isoDay(due);
      if (dueDay < today) {
        overdueCount += 1;
        overdueIqd += remaining;
        risk.overdue += remaining;
        risk.maxOverdueDays = Math.max(risk.maxOverdueDays, dayDiff(now, due));
      } else if (due <= in7) {
        due7Count += 1;
        due7Iqd += remaining;
      } else if (due <= in30) {
        due30Count += 1;
        due30Iqd += remaining;
      }
    }
    riskByCustomer.set(customerId, risk);
  }

  let collected30 = 0;
  let collectedPrev30 = 0;
  for (const payment of payments) {
    const debtRelation = payment.debts;
    const debtRow = Array.isArray(debtRelation) ? debtRelation[0] : debtRelation;
    const currency = String(
      debtRow && typeof debtRow === "object"
        ? (debtRow as Record<string, unknown>).currency ?? "IQD"
        : "IQD",
    ).toUpperCase();
    if (currency !== "IQD") continue;

    const at = new Date(String(payment.created_at ?? ""));
    if (Number.isNaN(at.getTime())) continue;
    const amount = Math.max(0, num(payment.amount));
    if (at >= ago30) {
      collected30 += amount;
    } else if (at >= ago60 && at < ago30) {
      collectedPrev30 += amount;
    }
  }

  const customerName = new Map(
    customers.map((row) => [String(row.id ?? ""), String(row.name ?? "کڕیار")]),
  );

  const topRisks: RiskRow[] = [];
  const avgOutstanding = riskByCustomer.size > 0
    ? remainingIqd / riskByCustomer.size
    : 0;

  for (const [customerId, risk] of riskByCustomer.entries()) {
    if (!customerId) continue;
    const overdueRatio = risk.remaining > 0 ? risk.overdue / risk.remaining : 0;
    const amountFactor = avgOutstanding > 0
      ? Math.min(1, risk.remaining / (avgOutstanding * 3))
      : 0;
    const score = Math.round(Math.min(
      100,
      overdueRatio * 45 +
        Math.min(30, risk.maxOverdueDays / 3) +
        amountFactor * 20 +
        Math.min(5, risk.openCount),
    ));
    topRisks.push({
      customer_id: customerId,
      name: customerName.get(customerId) ?? "کڕیار",
      risk_score: score,
      remaining_iqd: Math.round(risk.remaining),
      overdue_iqd: Math.round(risk.overdue),
      max_overdue_days: risk.maxOverdueDays,
      open_debts: risk.openCount,
    });
  }
  topRisks.sort((a, b) =>
    b.risk_score - a.risk_score ||
    b.overdue_iqd - a.overdue_iqd ||
    b.remaining_iqd - a.remaining_iqd
  );

  const overdueRatio = remainingIqd > 0 ? overdueIqd / remainingIqd : 0;
  const highRiskCount = topRisks.filter((r) => r.risk_score >= 70).length;
  const highRiskRatio = customers.length > 0 ? highRiskCount / customers.length : 0;
  const healthScore = Math.max(
    0,
    Math.min(100, Math.round(100 - overdueRatio * 65 - highRiskRatio * 35)),
  );

  const collectionChangePercent = collectedPrev30 > 0
    ? Math.round(((collected30 - collectedPrev30) / collectedPrev30) * 1000) / 10
    : (collected30 > 0 ? 100 : 0);

  return {
    generated_at: now.toISOString(),
    market_name: String(profile.market_name ?? ""),
    health_score: healthScore,
    totals: {
      customers: customers.length,
      active_customers: customers.filter((c) => c.active === true).length,
      open_debts: openCount,
      total_remaining_iqd: Math.round(remainingIqd),
      total_remaining_usd: Math.round(remainingUsd * 100) / 100,
      overdue_count: overdueCount,
      overdue_iqd: Math.round(overdueIqd),
      due_7_count: due7Count,
      due_7_iqd: Math.round(due7Iqd),
      due_30_count: due30Count,
      due_30_iqd: Math.round(due30Iqd),
      collected_30_iqd: Math.round(collected30),
      collected_previous_30_iqd: Math.round(collectedPrev30),
      collection_change_percent: collectionChangePercent,
      high_risk_customers: highRiskCount,
    },
    top_risks: topRisks.slice(0, 12),
  };
}

function extractOutputText(payload: any): string {
  if (typeof payload?.output_text === "string" && payload.output_text.trim()) {
    return payload.output_text.trim();
  }
  for (const item of payload?.output ?? []) {
    if (item?.type !== "message") continue;
    for (const content of item?.content ?? []) {
      if (content?.type === "output_text" && typeof content.text === "string") {
        return content.text.trim();
      }
    }
  }
  return "";
}

async function runOpenAI(
  apiKey: string,
  model: string,
  adminId: string,
  snapshot: any,
  question: string,
) {
  const aliases = (snapshot.top_risks as RiskRow[]).slice(0, 8).map((risk, index) => ({
    alias: `C${index + 1}`,
    risk_score: risk.risk_score,
    remaining_iqd: risk.remaining_iqd,
    overdue_iqd: risk.overdue_iqd,
    max_overdue_days: risk.max_overdue_days,
    open_debts: risk.open_debts,
  }));

  const userPayload = {
    market: {
      name: snapshot.market_name,
      health_score: snapshot.health_score,
      totals: snapshot.totals,
    },
    top_risk_customers: aliases,
    question: question || "پوختەی دۆخ، مەترسییەکان و ٣ هەنگاوی پێشنیارکراو بۆ بەڕێوەبەر بنووسە.",
  };

  const body = {
    model,
    store: false,
    reasoning: { effort: "low" },
    max_output_tokens: 1800,
    safety_identifier: await sha256Hex(`zhirox:${adminId}`),
    prompt_cache_key: "zhirox-intelligence-v1",
    instructions:
      "You are ZHIROX AI for a debt-management market. Answer only in Kurdish Sorani. Use only supplied figures, never invent facts, and make recommendations advisory rather than automatic decisions.",
    input: JSON.stringify(userPayload),
    text: {
      verbosity: "low",
      format: {
        type: "json_schema",
        name: "zhirox_intelligence",
        strict: true,
        schema: {
          type: "object",
          additionalProperties: false,
          properties: {
            executive_summary: { type: "string" },
            health_assessment: { type: "string" },
            alerts: {
              type: "array",
              items: {
                type: "object",
                additionalProperties: false,
                properties: {
                  severity: { type: "string", enum: ["high", "medium", "low"] },
                  title: { type: "string" },
                  detail: { type: "string" },
                },
                required: ["severity", "title", "detail"],
              },
            },
            recommendations: {
              type: "array",
              items: {
                type: "object",
                additionalProperties: false,
                properties: {
                  priority: { type: "string", enum: ["high", "medium", "low"] },
                  title: { type: "string" },
                  why: { type: "string" },
                  action: { type: "string" },
                },
                required: ["priority", "title", "why", "action"],
              },
            },
            customer_insights: {
              type: "array",
              items: {
                type: "object",
                additionalProperties: false,
                properties: {
                  customer_alias: { type: "string" },
                  assessment: { type: "string" },
                  next_action: { type: "string" },
                },
                required: ["customer_alias", "assessment", "next_action"],
              },
            },
            confidence: { type: "number", minimum: 0, maximum: 1 },
          },
          required: [
            "executive_summary",
            "health_assessment",
            "alerts",
            "recommendations",
            "customer_insights",
            "confidence",
          ],
        },
      },
    },
  };

  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    console.error("OpenAI request failed", response.status, payload?.error?.code ?? "unknown");
    throw new Error(`openai_${response.status}`);
  }

  const outputText = extractOutputText(payload);
  if (!outputText) throw new Error("openai_empty_output");

  const parsed = JSON.parse(outputText);
  const aliasMap = new Map(
    (snapshot.top_risks as RiskRow[]).slice(0, 8).map((risk, index) => [
      `C${index + 1}`,
      risk,
    ]),
  );

  const customerInsights = Array.isArray(parsed.customer_insights)
    ? parsed.customer_insights.map((item: any) => {
        const risk = aliasMap.get(String(item.customer_alias ?? ""));
        return {
          customer_id: risk?.customer_id ?? null,
          customer_name: risk?.name ?? String(item.customer_alias ?? ""),
          risk_score: risk?.risk_score ?? null,
          assessment: String(item.assessment ?? ""),
          next_action: String(item.next_action ?? ""),
        };
      })
    : [];

  return {
    model: String(payload.model ?? model),
    generated_at: new Date().toISOString(),
    executive_summary: String(parsed.executive_summary ?? ""),
    health_assessment: String(parsed.health_assessment ?? ""),
    alerts: Array.isArray(parsed.alerts) ? parsed.alerts.slice(0, 6) : [],
    recommendations: Array.isArray(parsed.recommendations)
      ? parsed.recommendations.slice(0, 6)
      : [],
    customer_insights: customerInsights.slice(0, 8),
    confidence: Math.max(0, Math.min(1, num(parsed.confidence))),
    usage: payload.usage
      ? {
          input_tokens: num(payload.usage.input_tokens),
          output_tokens: num(payload.usage.output_tokens),
          total_tokens: num(payload.usage.total_tokens),
        }
      : null,
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const secret = envJsonKey("SUPABASE_SECRET_KEYS") ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !secret) return json({ error: "server_not_configured" }, 500);

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
      .select("id,role,active,approved,subscription_end,market_name,is_system_owner")
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

    const body = await req.json().catch(() => ({}));
    const action = String(body.action ?? "snapshot");
    const question = String(body.question ?? "").trim().slice(0, 1000);
    if (!["snapshot", "analyze"].includes(action)) {
      return json({ error: "unsupported_action" }, 400);
    }

    const adminId = String(profile.id);
    const customers = await fetchAll(
      admin,
      "profiles",
      "id,name,active",
      (q) => q.eq("admin_id", adminId).eq("role", "customer"),
    );
    const customerIds = customers.map((row) => String(row.id ?? "")).filter(Boolean);

    const [debts, payments] = await Promise.all([
      fetchDebtsForCustomers(admin, customerIds),
      fetchPaymentsForCustomers(admin, customerIds),
    ]);

    const snapshot = buildSnapshot(profile, customers, debts, payments);
    const apiKey = Deno.env.get("OPENAI_API_KEY")?.trim() ?? "";
    const model = Deno.env.get("OPENAI_INTELLIGENCE_MODEL")?.trim() ||
      "gpt-5.6-luna";

    if (action === "snapshot") {
      return json({
        ok: true,
        ai_enabled: apiKey.length > 0,
        model: apiKey.length > 0 ? model : null,
        snapshot,
      });
    }

    if (!apiKey) {
      return json({
        ok: true,
        ai_enabled: false,
        error: "ai_not_configured",
        snapshot,
      });
    }

    try {
      const ai = await runOpenAI(apiKey, model, adminId, snapshot, question);
      return json({ ok: true, ai_enabled: true, snapshot, ai });
    } catch (error) {
      console.error(error);
      return json({
        ok: true,
        ai_enabled: true,
        error: error instanceof Error ? error.message : "ai_failed",
        snapshot,
      });
    }
  } catch (error) {
    console.error(error);
    return json({ error: error instanceof Error ? error.message : "internal_error" }, 500);
  }
});
