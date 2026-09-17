# Customer Push Permanent Links Implementation Plan

> Use test-driven development. Work only on `user-source`.

**Goal:** Make every customer QR/Web Push link permanent and reusable until an authorized manager explicitly revokes it.

**Spec:** `docs/superpowers/specs/2026-09-17-customer-push-permanent-links-design.md`

## Task 1 — Database/RPC permanent-link semantics

**Create:** `supabase/migrations/20260917194000_permanent_customer_push_links.sql`

1. Add regression SQL assertions or repository policy checks first for permanent semantics.
2. Alter `customer_push_link_tokens.expires_at` to allow NULL.
3. Migrate unrevoked legacy links to `expires_at = NULL` and clear legacy `used_at` so already-issued unrevoked links can continue under the new policy.
4. Replace `manage_customer_push_link` so creating a link does not revoke prior links and stores a NULL expiry.
5. Replace `inspect_customer_push_link_service` so validity depends on token hash + `revoked_at IS NULL` + normal tenant/customer authorization, not expiry or used state.
6. Replace `redeem_customer_push_subscription_service` so successful subscription does not set `used_at` and the same token can link multiple devices.
7. Update `customer_push_status_service` to return `active_link_count` in addition to current device/delivery fields.
8. Replace `revoke_customer_push_subscriptions_service` so it revokes every unrevoked token for the customer, regardless of `used_at`, and disables all active subscriptions.
9. Keep grants/search_path/security-definer hardening equivalent to the existing RPCs.

## Task 2 — Edge admin API

**Modify:**
- `supabase/functions/customer-push-admin/index_test.ts`
- `supabase/functions/customer-push-admin/index.ts`

1. RED: change create-link test to require no expiry and a permanent canonical URL.
2. RED: add status test requiring `active_link_count` passthrough.
3. Change `AdminDeps.manageLink` to accept a nullable expiry or remove the generated expiry from application logic while preserving RPC compatibility.
4. `create_link` returns `expires_at: null` and never calculates 15 minutes/90 days.
5. Run `deno test --allow-env supabase/functions/customer-push-admin` and require GREEN.

## Task 3 — Public link reuse behavior

**Modify tests for:** `supabase/functions/customer-push` and migration verifier.

1. Add regression coverage proving the same token remains valid across repeated `validate` calls.
2. Add integration/RPC coverage proving the same token can be redeemed for two different device endpoints.
3. Add coverage proving manager revoke makes the token unavailable immediately.
4. Keep rate limiting, CORS, token format checks, generic errors, and `push.zhirox.com` redirects unchanged.

## Task 4 — Flutter model and manager UX

**Modify:**
- `lib/services/customer_push_service.dart`
- `lib/widgets/customer_push_card.dart`
- `test/customer_push_service_test.dart`
- `test/customer_push_card_test.dart`

1. RED: update `CustomerPushLink` tests so `expires_at: null` is valid and `expiresAt` is nullable.
2. RED: update status tests to require non-negative `active_link_count` and expose `hasActiveLink`/equivalent state.
3. Change QR dialog copy to: `ئەم لینکە بەردەوام کار دەکات تا بەڕێوەبەر ڕایدەگرێت.`
4. Show the revoke control when `active_link_count > 0` OR `device_count > 0`.
5. Change revoke confirmation to state that all active QR links and devices will be disabled.
6. Keep QR URL validation and 64-hex token validation unchanged.
7. Run focused Flutter tests and require GREEN.

## Task 5 — Policy verification and full CI

1. Update `scripts/verify_customer_push.py` to reject production code/UI text that enforces 15-minute, 90-day, `used_at`-consumption, or automatic link replacement behavior.
2. Run all customer push Deno tests.
3. Run focused Flutter customer-push tests.
4. Run `flutter analyze` and full `flutter test`.
5. Ensure existing iOS unsigned IPA workflow stays green.

## Task 6 — Production rollout

1. Apply the new migration to Supabase production.
2. Deploy the updated `customer-push-admin` Edge Function; deploy `customer-push` only if its code/tests changed.
3. Verify an existing unrevoked link still validates after migration.
4. Create a new link, subscribe device A, then reuse the exact same link to subscribe device B.
5. Generate a second link and verify the first still works.
6. Revoke from the manager UI/API and verify both links fail and both subscriptions become inactive.
7. Re-run live debt/payment push smoke tests.

## Acceptance criteria

- No automatic expiry.
- No one-time consumption.
- No automatic revocation when a new QR is generated.
- Explicit manager revoke is the only normal link-invalidating action.
- All issued active links for the customer are invalidated by manager revoke.
- Hash-only token storage and tenant security remain intact.
