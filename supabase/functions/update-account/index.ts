import { createClient } from "npm:@supabase/supabase-js@2.116.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

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

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function isOperational(admin: any, profile: any): Promise<boolean> {
  if (!profile || profile.active !== true || profile.approved !== true) return false;
  if (profile.is_system_owner === true) return true;

  const tenantId = profile.role === "admin" ? profile.id : profile.admin_id;
  if (!tenantId) return false;
  const tenant = profile.role === "admin"
    ? profile
    : (await admin
        .from("profiles")
        .select("id, active, approved, subscription_end")
        .eq("id", tenantId)
        .eq("role", "admin")
        .maybeSingle()).data;
  if (!tenant || tenant.active !== true || tenant.approved !== true) return false;

  const subscriptionEnd = tenant.subscription_end
    ? Date.parse(String(tenant.subscription_end))
    : null;
  return subscriptionEnd === null ||
    (Number.isFinite(subscriptionEnd) && subscriptionEnd >= Date.now());
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const secret = envJsonKey("SUPABASE_SECRET_KEYS") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!secret) return json({ error: "server_not_configured" }, 500);

    const admin = createClient(url, secret, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
    if (!token) return json({ error: "authentication_required" }, 401);

    const { data: authData, error: authError } = await admin.auth.getUser(token);
    if (authError || !authData.user) return json({ error: "authentication_required" }, 401);

    const body = await req.json();
    const targetId = String(body.user_id ?? "").trim();
    const incoming = body.data && typeof body.data === "object" ? body.data : {};
    if (!targetId) return json({ error: "invalid_input" }, 400);

    const [{ data: requester, error: requesterError }, { data: target, error: targetError }] =
      await Promise.all([
        admin.from("profiles").select("*").eq("id", authData.user.id).maybeSingle(),
        admin.from("profiles").select("*").eq("id", targetId).maybeSingle(),
      ]);

    if (requesterError) return json({ error: requesterError.message }, 400);
    if (targetError) return json({ error: targetError.message }, 400);
    if (!requester || !target) return json({ error: "profile_not_found" }, 404);
    if (!(await isOperational(admin, requester))) {
      return json({ error: "forbidden" }, 403);
    }

    const isSelf = requester.id === target.id;
    const sameTenantMember =
      requester.role === "admin" &&
      (target.role === "employee" || target.role === "customer") &&
      target.admin_id === requester.id;
    const employeeCustomerMember =
      requester.role === "employee" &&
      target.role === "customer" &&
      Boolean(requester.admin_id) &&
      target.admin_id === requester.admin_id;
    const employeeEmployeeMember =
      requester.role === "employee" &&
      target.role === "employee" &&
      Boolean(requester.admin_id) &&
      target.admin_id === requester.admin_id;

    if (
      !isSelf &&
      !sameTenantMember &&
      !employeeCustomerMember &&
      !employeeEmployeeMember
    ) {
      return json({ error: "forbidden" }, 403);
    }

    const selfFields = new Set(["name", "father_name", "grandfather_name", "phone"]);
    if (requester.role === "admin") selfFields.add("market_name");

    const tenantAdminFields = new Set([
      "name",
      "father_name",
      "grandfather_name",
      "phone",
      "approved",
      "active",
      "debt_limit",
      "is_pinned",
      "pinned_at",
      "is_vip",
      "debt_duration",
      "can_add_customers",
      "can_set_debt_limit",
      "can_set_due_date",
      "can_edit_debts",
      "can_send_notifications",
      "can_view_customers",
      "can_edit_customers",
      "can_delete_customers",
      "can_view_debts",
      "can_add_debts",
      "can_delete_debts",
      "can_record_payments",
      "can_view_financial_reports",
      "can_export_data",
      "can_import_data",
      "can_refund_payments",
      "can_restore_debts",
      "can_manage_receipts",
      "can_manage_notifications",
      "can_approve_customers",
      "can_manage_employees",
      "can_view_audit_log",
      "can_manage_backup",
      "can_manage_daftar_sync",
      "can_manage_subscription",
      "can_view_dashboard",
      "can_view_recent_activity",
      "can_view_transactions",
      "can_edit_payments",
      "can_delete_payments",
      "can_create_statements",
      "can_manage_customer_links",
      "can_pin_customers",
      "can_manage_vip_customers",
      "can_merge_customer_identities",
      "can_view_market_rates",
      "can_view_intelligence",
      "can_manage_collections",
      "can_view_expiry",
      "can_manage_expiry",
      "can_manage_settings",
      "can_view_customer_phone",
      "can_view_customer_notes",
      "can_edit_customer_notes",
      "can_view_customer_balances",
      "can_view_payment_history",
      "can_create_receipts",
      "can_edit_receipts",
      "can_delete_receipts",
      "can_export_receipts",
      "can_view_report_summary",
      "can_export_reports",
      "can_view_sync_logs",
      "can_retry_failed_sync",
      "can_run_manual_backup",
      "can_restore_backup",
      "can_manage_notification_templates",
      "can_send_bulk_notifications",
      "can_manage_market_rate_refresh",
      "can_manage_security_settings",
      "can_view_customer_documents",
      "can_manage_customer_documents",
      "can_create_customer_qr",
      "can_view_customer_qr",
      "can_archive_customers",
      "can_restore_archived_customers",
      "can_blacklist_customers",
      "can_remove_customer_blacklist",
      "can_approve_new_debts",
      "can_reject_new_debts",
      "can_override_debt_limit",
      "can_change_due_date_after_create",
      "can_close_debts",
      "can_reopen_debts",
      "can_change_debt_currency",
      "can_change_debt_amount_after_approval",
      "can_approve_payments",
      "can_void_payments",
      "can_correct_payment_amount",
      "can_correct_payment_date",
      "can_reallocate_payments",
      "can_restore_voided_payments",
      "can_print_receipts",
      "can_share_receipts",
      "can_reissue_receipts",
      "can_view_receipt_history",
      "can_lock_receipts",
      "can_unlock_receipts",
      "can_suspend_employees",
      "can_reactivate_employees",
      "can_reset_employee_passwords",
      "can_view_employee_login_history",
      "can_force_employee_logout",
      "can_manage_employee_devices",
      "can_pause_sync",
      "can_resume_sync",
      "can_replay_failed_sync",
      "can_view_sync_payloads",
      "can_download_backups",
      "can_export_audit_log",
      "can_view_active_devices",
      "can_remove_trusted_devices",
      "can_approve_new_devices",
      "can_view_failed_logins",
      "can_lock_employee_accounts",
      "can_unlock_employee_accounts",
      "can_force_password_change",
      "can_manage_biometric_login",
      "can_view_deleted_transactions",
      "can_restore_deleted_transactions",
      "can_approve_transaction_edits",
      "can_view_transaction_change_history",
      "can_lock_old_transactions",
      "can_unlock_old_transactions",
      "can_transfer_transactions_between_customers",
      "can_require_transaction_edit_reason",
      "can_view_daily_reports",
      "can_view_weekly_reports",
      "can_view_monthly_reports",
      "can_view_yearly_reports",
      "can_create_custom_reports",
      "can_schedule_reports",
      "can_send_report_notifications",
      "can_view_employee_performance_reports",
      "can_assign_customer_tags",
      "can_manage_customer_tags",
      "can_set_customer_priority",
      "can_set_customer_status",
      "can_create_followups",
      "can_complete_followups",
      "can_view_customer_contact_history",
      "can_add_private_customer_notes",
      "can_view_backend_health",
      "can_view_database_health",
      "can_view_sync_queue",
      "can_clear_cache",
      "can_refresh_configuration",
      "can_view_version_history",
      "can_view_feature_flags",
      "can_manage_feature_flags",
      "can_approve_customer_creation",
      "can_approve_customer_edits",
      "can_approve_customer_deletion",
      "can_approve_debt_edits",
      "can_approve_debt_deletion",
      "can_approve_payment_voids",
      "can_approve_restores",
      "can_approve_debt_limit_changes",
      "can_view_full_phone_numbers",
      "can_view_masked_phone_numbers",
      "can_view_identity_documents",
      "can_download_identity_documents",
      "can_view_private_notes",
      "can_edit_private_notes",
      "can_export_personal_data",
      "can_anonymize_customer_data",
      "can_send_sms",
      "can_send_push_notifications",
      "can_send_telegram_notifications",
      "can_send_whatsapp_templates",
      "can_approve_notifications",
      "can_view_notification_delivery_status",
      "can_retry_failed_notifications",
      "can_lock_bulk_messaging",
      "can_view_api_status",
      "can_manage_api_keys",
      "can_revoke_api_keys",
      "can_view_webhook_logs",
      "can_retry_webhooks",
      "can_disable_integrations",
      "can_enable_integrations",
      "can_view_sync_mappings",
      "can_create_automation_rules",
      "can_edit_automation_rules",
      "can_delete_automation_rules",
      "can_pause_resume_automation",
      "can_view_automation_logs",
      "can_create_alert_rules",
      "can_edit_alert_thresholds",
      "can_mute_alerts",
    ]);

    const employeeCustomerFields = new Set<string>();
    if (employeeCustomerMember) {
      if (requester.can_edit_customers === true) {
        employeeCustomerFields.add("name");
        employeeCustomerFields.add("father_name");
        employeeCustomerFields.add("grandfather_name");
        employeeCustomerFields.add("phone");
      }
      if (requester.can_approve_customers === true) {
        employeeCustomerFields.add("approved");
      }
      if (requester.can_set_debt_limit === true) {
        employeeCustomerFields.add("debt_limit");
      }
      if (requester.can_pin_customers === true) {
        employeeCustomerFields.add("is_pinned");
        employeeCustomerFields.add("pinned_at");
      }
      if (requester.can_manage_vip_customers === true) {
        employeeCustomerFields.add("is_vip");
      }
    }

    const employeeEmployeeFields = new Set<string>();
    if (employeeEmployeeMember && requester.can_manage_employees === true) {
      employeeEmployeeFields.add("name");
      employeeEmployeeFields.add("father_name");
      employeeEmployeeFields.add("grandfather_name");
      employeeEmployeeFields.add("phone");
      employeeEmployeeFields.add("active");
    }

    const allowed = isSelf
      ? selfFields
      : sameTenantMember
        ? tenantAdminFields
        : employeeCustomerMember
          ? employeeCustomerFields
          : employeeEmployeeFields;
    const update: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(incoming)) {
      if (allowed.has(key)) update[key] = value;
    }

    if (Object.hasOwn(update, "debt_limit")) {
      const debtLimit = Number(update.debt_limit);
      if (!Number.isFinite(debtLimit) || debtLimit < 0) {
        return json({ error: "invalid_debt_limit" }, 400);
      }
      update.debt_limit = debtLimit;
    }

    if (Object.hasOwn(update, "is_pinned")) {
      update.is_pinned = update.is_pinned === true;
      update.pinned_at = update.is_pinned ? new Date().toISOString() : null;
    } else {
      delete update.pinned_at;
    }

    if (Object.hasOwn(update, "is_vip")) {
      update.is_vip = update.is_vip === true;
    }

    if (typeof update.phone === "string") {
      const phone = update.phone.trim();
      if (!phone) return json({ error: "invalid_phone" }, 400);
      const { data: duplicate, error: duplicateError } = await admin
        .from("profiles")
        .select("id")
        .eq("phone", phone)
        .neq("id", targetId)
        .maybeSingle();
      if (duplicateError) return json({ error: duplicateError.message }, 400);
      if (duplicate) return json({ error: "phone_exists" }, 409);
      update.phone = phone;
    }

    if (Object.keys(update).length === 0) {
      if (!isSelf && !sameTenantMember) {
        return json({ error: "missing_permission" }, 403);
      }
      return json({ user: target });
    }

    const syncAuthIdentity = Object.hasOwn(update, "phone") || Object.hasOwn(update, "name");
    let previousAuthEmail: string | undefined;
    let previousAuthMetadata: Record<string, unknown> | undefined;

    if (syncAuthIdentity) {
      const { data: targetAuthData, error: targetAuthError } =
        await admin.auth.admin.getUserById(targetId);
      if (targetAuthError || !targetAuthData.user) {
        return json({ error: targetAuthError?.message ?? "auth_user_not_found" }, 400);
      }

      previousAuthEmail = targetAuthData.user.email;
      previousAuthMetadata = { ...(targetAuthData.user.user_metadata ?? {}) };
      const nextPhone = String(update.phone ?? target.phone ?? "").trim();
      const nextName = String(update.name ?? target.name ?? "").trim();
      const authUpdate: Record<string, unknown> = {
        user_metadata: {
          ...previousAuthMetadata,
          name: nextName,
          phone: nextPhone,
          role: target.role,
          admin_id: target.admin_id,
        },
      };
      if (Object.hasOwn(update, "phone")) {
        authUpdate.email = `${nextPhone}@zhirox.local`;
      }

      const { error: userError } = await admin.auth.admin.updateUserById(targetId, authUpdate);
      if (userError) return json({ error: userError.message }, 400);
    }

    update.updated_at = new Date().toISOString();
    const { data: updated, error: updateError } = await admin
      .from("profiles")
      .update(update)
      .eq("id", targetId)
      .select()
      .single();

    if (updateError) {
      if (syncAuthIdentity) {
        try {
          const rollback: Record<string, unknown> = {
            user_metadata: previousAuthMetadata ?? {},
          };
          if (previousAuthEmail) rollback.email = previousAuthEmail;
          await admin.auth.admin.updateUserById(targetId, rollback);
        } catch (_) {
          // Best-effort auth rollback. The profile update remains authoritative.
        }
      }
      return json({ error: updateError.message }, 400);
    }

    return json({ user: updated });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});