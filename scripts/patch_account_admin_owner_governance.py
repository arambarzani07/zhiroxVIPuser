#!/usr/bin/env python3
from pathlib import Path

path = Path('supabase/functions/account-admin/index.ts')
text = path.read_text(encoding='utf-8')


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'PATCH_FAILED {label}: expected 1 match, found {count}')
    text = text.replace(old, new, 1)

replace_once(
'''  return subscriptionEnd === null ||
    (Number.isFinite(subscriptionEnd) && subscriptionEnd >= Date.now());
}

Deno.serve(async (req) => {''',
'''  return subscriptionEnd === null ||
    (Number.isFinite(subscriptionEnd) && subscriptionEnd >= Date.now());
}

async function authorizeOwnerAction(
  admin: any,
  actorId: string,
  permissionKey: string,
  targetAdminId: string | null = null,
): Promise<boolean> {
  const { data, error } = await admin.rpc(
    "authorize_system_owner_account_admin_service",
    {
      p_actor_id: actorId,
      p_permission_key: permissionKey,
      p_target_admin_id: targetAdminId,
    },
  );
  return !error && data?.authorized === true;
}

Deno.serve(async (req) => {''',
'owner authorization helper',
)

replace_once(
'''      if (!["admin", "employee", "customer"].includes(role)) {
        return json({ error: "invalid_role" }, 400);
      }

      const { data: existing, error: existingError } = await admin''',
'''      if (!["admin", "employee", "customer"].includes(role)) {
        return json({ error: "invalid_role" }, 400);
      }
      if (requesterProfile?.is_system_owner === true && role !== "admin") {
        return json({ error: "owner_tenant_member_management_forbidden" }, 403);
      }

      const { data: existing, error: existingError } = await admin''',
'block Owner tenant-member creation',
)

replace_once(
'''      if (role === "admin") {
        if (!requester || !requesterProfile?.is_system_owner || requesterProfile.active !== true) {
          return json({ error: "system_owner_required" }, 403);
        }

        adminId = null;''',
'''      if (role === "admin") {
        if (!requester || !requesterProfile?.is_system_owner || requesterProfile.active !== true) {
          return json({ error: "system_owner_required" }, 403);
        }
        for (const permissionKey of [
          "owner_create_admin",
          "owner_create_market",
          "owner_create_subscription",
        ]) {
          if (!(await authorizeOwnerAction(admin, requester.id, permissionKey))) {
            return json({ error: "owner_permission_denied", permission_key: permissionKey }, 403);
          }
        }

        adminId = null;''',
'authorize admin creation',
)

replace_once(
'''      if (profileError) {
        await admin.auth.admin.deleteUser(authData.user.id);
        if (
          profileError.code === "23505" &&
          String(profileError.message ?? "").includes("profiles_normalized_phone_unique_idx")
        ) {
          return json({ error: "phone_exists" }, 409);
        }
        return json({ error: profileError.message }, 400);
      }
      return json({ user: inserted }, 201);''',
'''      if (profileError) {
        await admin.auth.admin.deleteUser(authData.user.id);
        if (
          profileError.code === "23505" &&
          String(profileError.message ?? "").includes("profiles_normalized_phone_unique_idx")
        ) {
          return json({ error: "phone_exists" }, 409);
        }
        return json({ error: profileError.message }, 400);
      }
      if (role === "admin" && requester) {
        const { error: auditError } = await admin
          .from("owner_platform_audit")
          .insert({
            actor_id: requester.id,
            target_admin_id: inserted.id,
            action: "admin_account_created",
            metadata: {
              permission_keys: [
                "owner_create_admin",
                "owner_create_market",
                "owner_create_subscription",
              ],
              market_name: marketName,
              subscription_plan: resolvedSubscription?.plan ?? null,
              subscription_days: resolvedSubscription?.days ?? null,
            },
          });
        if (auditError) {
          await admin.auth.admin.deleteUser(authData.user.id);
          return json({ error: "owner_audit_failed" }, 500);
        }
      }
      return json({ user: inserted }, 201);''',
'audit admin creation',
)

replace_once(
'''    if (action === "list_admins") {
      if (requesterProfile.is_system_owner !== true) {
        return json({ error: "system_owner_required" }, 403);
      }
      const page = Math.max(1, Math.round(Number(body.page ?? 1)) || 1);''',
'''    if (action === "list_admins") {
      if (requesterProfile.is_system_owner !== true) {
        return json({ error: "system_owner_required" }, 403);
      }
      if (!(await authorizeOwnerAction(admin, requester.id, "owner_view_all_admins"))) {
        return json({ error: "owner_permission_denied", permission_key: "owner_view_all_admins" }, 403);
      }
      const page = Math.max(1, Math.round(Number(body.page ?? 1)) || 1);''',
'authorize admin list',
)

replace_once(
'''      const { data: target, error: targetError } = await admin
        .from("profiles")
        .select("id,subscription_end")
        .eq("id", adminId)''',
'''      const { data: target, error: targetError } = await admin
        .from("profiles")
        .select("id,subscription_plan,subscription_end")
        .eq("id", adminId)''',
'renew subscription target fields',
)

replace_once(
'''      if (targetError) return json({ error: targetError.message }, 400);
      if (!target) return json({ error: "admin_not_found" }, 404);

      const parsedEnd = target.subscription_end''',
'''      if (targetError) return json({ error: targetError.message }, 400);
      if (!target) return json({ error: "admin_not_found" }, 404);

      const renewalPermissions = [
        "owner_renew_subscription",
        "owner_extend_subscription_days",
      ];
      if (String(target.subscription_plan ?? "") !== resolvedSubscription.plan) {
        renewalPermissions.push("owner_change_subscription_plan");
      }
      for (const permissionKey of renewalPermissions) {
        if (!(await authorizeOwnerAction(admin, requester.id, permissionKey, adminId))) {
          return json({ error: "owner_permission_denied", permission_key: permissionKey }, 403);
        }
      }

      const parsedEnd = target.subscription_end''',
'authorize subscription renewal',
)

replace_once(
'''      const { error: updateError } = await admin
        .from("profiles")
        .update({
          subscription_plan: resolvedSubscription.plan,
          subscription_end: subscriptionEnd,
        })
        .eq("id", adminId);
      if (updateError) return json({ error: updateError.message }, 400);
      return json({ subscription_end: subscriptionEnd });''',
'''      const previousPlan = target.subscription_plan ?? null;
      const previousEnd = target.subscription_end ?? null;
      const { error: updateError } = await admin
        .from("profiles")
        .update({
          subscription_plan: resolvedSubscription.plan,
          subscription_end: subscriptionEnd,
        })
        .eq("id", adminId);
      if (updateError) return json({ error: updateError.message }, 400);

      const { error: auditError } = await admin
        .from("owner_platform_audit")
        .insert({
          actor_id: requester.id,
          target_admin_id: adminId,
          action: "subscription_renewed_via_account_admin",
          metadata: {
            permission_keys: renewalPermissions,
            previous_subscription_plan: previousPlan,
            subscription_plan: resolvedSubscription.plan,
            previous_subscription_end: previousEnd,
            subscription_end: subscriptionEnd,
            extend_days: resolvedSubscription.days,
          },
        });
      if (auditError) {
        await admin
          .from("profiles")
          .update({ subscription_plan: previousPlan, subscription_end: previousEnd })
          .eq("id", adminId);
        return json({ error: "owner_audit_failed" }, 500);
      }
      return json({ subscription_end: subscriptionEnd });''',
'audit and rollback renewal',
)

replace_once(
'''      const isOwner = requesterProfile.is_system_owner === true;
      const isTenantAdmin =
        requesterProfile.role === "admin" &&
        (target.role === "employee" || target.role === "customer") &&
        target.admin_id === requester.id;
      const isEmployeeManager =
        requesterProfile.role === "employee" &&
        requesterProfile.can_manage_employees === true &&
        target.role === "employee" &&
        Boolean(requesterProfile.admin_id) &&
        target.admin_id === requesterProfile.admin_id;
      if (!isOwner && !isTenantAdmin && !isEmployeeManager) {
        return json({ error: "forbidden" }, 403);
      }

      const { error } = await admin.auth.admin.updateUserById(targetId, {''',
'''      const isOwner = requesterProfile.is_system_owner === true;
      if (isOwner) {
        if (target.role === "admin") {
          return json({ error: "admin_recovery_requires_dedicated_endpoint" }, 409);
        }
        return json({ error: "owner_tenant_member_management_forbidden" }, 403);
      }
      const isTenantAdmin =
        requesterProfile.role === "admin" &&
        (target.role === "employee" || target.role === "customer") &&
        target.admin_id === requester.id;
      const isEmployeeManager =
        requesterProfile.role === "employee" &&
        requesterProfile.can_manage_employees === true &&
        target.role === "employee" &&
        Boolean(requesterProfile.admin_id) &&
        target.admin_id === requesterProfile.admin_id;
      if (!isTenantAdmin && !isEmployeeManager) {
        return json({ error: "forbidden" }, 403);
      }

      const { error } = await admin.auth.admin.updateUserById(targetId, {''',
'block Owner reset bypass',
)

replace_once(
'''      const isOwner = requesterProfile.is_system_owner === true;
      const isTenantAdmin =
        requesterProfile.role === "admin" &&
        (target.role === "employee" || target.role === "customer") &&
        target.admin_id === requester.id;
      const isEmployeeManager =
        requesterProfile.role === "employee" &&
        requesterProfile.can_manage_employees === true &&
        target.role === "employee" &&
        Boolean(requesterProfile.admin_id) &&
        target.admin_id === requesterProfile.admin_id;
      const isPendingCustomerApprover =
        requesterProfile.role === "employee" &&
        requesterProfile.can_approve_customers === true &&
        target.role === "customer" &&
        target.approved !== true &&
        Boolean(requesterProfile.admin_id) &&
        target.admin_id === requesterProfile.admin_id;
      if (!isOwner && !isTenantAdmin && !isEmployeeManager && !isPendingCustomerApprover) {
        return json({ error: "forbidden" }, 403);
      }''',
'''      const isOwner = requesterProfile.is_system_owner === true;
      if (isOwner) {
        return json({ error: "owner_tenant_member_management_forbidden" }, 403);
      }
      const isTenantAdmin =
        requesterProfile.role === "admin" &&
        (target.role === "employee" || target.role === "customer") &&
        target.admin_id === requester.id;
      const isEmployeeManager =
        requesterProfile.role === "employee" &&
        requesterProfile.can_manage_employees === true &&
        target.role === "employee" &&
        Boolean(requesterProfile.admin_id) &&
        target.admin_id === requesterProfile.admin_id;
      const isPendingCustomerApprover =
        requesterProfile.role === "employee" &&
        requesterProfile.can_approve_customers === true &&
        target.role === "customer" &&
        target.approved !== true &&
        Boolean(requesterProfile.admin_id) &&
        target.admin_id === requesterProfile.admin_id;
      if (!isTenantAdmin && !isEmployeeManager && !isPendingCustomerApprover) {
        return json({ error: "forbidden" }, 403);
      }''',
'block Owner delete bypass',
)

required = [
    'authorize_system_owner_account_admin_service',
    'owner_create_admin',
    'owner_create_market',
    'owner_create_subscription',
    'owner_view_all_admins',
    'owner_renew_subscription',
    'owner_extend_subscription_days',
    'owner_change_subscription_plan',
    'admin_recovery_requires_dedicated_endpoint',
    'owner_tenant_member_management_forbidden',
    'subscription_renewed_via_account_admin',
    'admin_account_created',
]
for token in required:
    if token not in text:
        raise SystemExit(f'PATCH_FAILED missing token after patch: {token}')

path.write_text(text, encoding='utf-8')
print('ACCOUNT_ADMIN_OWNER_GOVERNANCE_PATCH_OK')
