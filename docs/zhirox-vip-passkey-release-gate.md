# ZHIROX VIP V10: Passkey release gate (not enabled)

Status: pre-verification policy only. No route, migration, credential enrollment, or production deployment is enabled by this change.

## Existing trust boundary
The current customer-push Edge Function accepts a permanent QR token or device endpoint plus device secret. The database already resolves these to a customer_id + market_id pair via private.resolve_customer_push_identity (see the secure receipt migration). The portal is not presently a Supabase Auth passkey session. Never infer ownership from browser-provided IDs, phone, display name, or balance. Supabase Auth passkeys are currently beta; do not toggle a project-wide authentication feature or create/merge customer Auth users without proving the mapping.

## Required integration
- Use the canonical relying party ID zhirox.com and explicitly allowed HTTPS origins https://zhirox.com and https://push.zhirox.com. Never allow arbitrary subdomains or preview origins in production. Use an isolated test relying party for staging.
- Resolve both market and customer through the existing server authorization; do not accept those IDs from the browser. Enrollment requires an independently verified existing customer identity. A leaked permanent QR token alone must not permit persistent passkey takeover.
- Use a maintained pinned WebAuthn server library, with lockfile and dependency audit. Generate cryptographically random challenges; store the exact challenge, customer/market identity, ceremony, origin, RP ID, issuance and expiry (5 minutes maximum). The policy module is only a precondition check. Atomically consume once in a transaction; challenge reuse fails even under concurrency. Validate signed response, challenge, origin, RP ID, user presence and user verification using the library. Verify the registered credential belongs to the same customer/market; retain public key, credential ID, counter and backup flags; never store biometrics/private keys. Handle synchronized passkey counter semantics using the library.
- Successful authentication may issue a short-lived server session scoped to the same customer and market. Enforce current account/link status on every sensitive API action. A successful local biometric prompt is not a server session.
- Optional passkey sign-in is convenience, not mandatory second factor: existing permanent QR and device-secret routes remain valid until a deliberately approved policy changes them. If an account lock is requested, enforce it for every alternate credential path and provide secure recovery. Do not falsely label a UI-only lock as account security.
- Keep enrollment, recovery, revocation, session expiry and cross-device flows auditable without storing tokens or personal financial data in logs. Rate limit enrollment/authentication per identity and network; prevent account enumeration. RLS and grants must deny public credential/challenge access.
- Do not enable feature flag until tests pass, including actual signed ceremonies on physical iPhone Safari and Home Screen, Android and desktop, invalid signatures, origin/RP mismatch, concurrent replay, cross-market isolation, revoked account, fallback/QR regression, and recovery. No financial data edits, push service activation or production promotion as part of this preparatory change.

## Reference
https://simplewebauthn.dev/docs/packages/server
https://supabase.com/docs/guides/auth/passkeys
