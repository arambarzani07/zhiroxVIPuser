# Customer Push Permanent Link Design

Date: 2026-09-17
Branch: `user-source`
Parent spec: `docs/superpowers/specs/2026-09-17-customer-push-domain-hosting-design.md`

## Goal

Change customer QR/Web Push links from expiring one-time tokens into permanent, reusable links that remain valid until a manager explicitly revokes them.

## Approved behavior

- A generated customer QR/link has no time expiry.
- A generated customer QR/link is reusable and is not consumed after the first successful device subscription.
- Creating a new QR/link does not revoke older active links for the same customer.
- Only an explicit manager revoke action invalidates the customer's active QR/link tokens.
- The same revoke action also disables the customer's active push subscriptions, preserving the existing "disconnect all" safety behavior.
- After revoke, all previously issued active links for that customer fail immediately. A manager can then generate a new permanent link.
- Raw tokens remain 64 lowercase hex and are never stored in plaintext in the database; only SHA-256 hashes are persisted.
- Existing server-side rate limiting, tenant checks, customer/manager authorization, VAPID security, outbox semantics, retry behavior, and financial transaction semantics remain unchanged.

## Database semantics

`customer_push_link_tokens` keeps its current columns for backward compatibility, but permanent-link logic changes as follows:

- `expires_at` becomes nullable and is `NULL` for permanent links.
- `used_at` is no longer a validity gate for permanent links and successful subscription must not consume the token.
- `revoked_at` is the authoritative validity switch.
- Existing unrevoked links are migrated to permanent semantics by clearing legacy expiry/consumption state where safe.

A link is valid when:

1. its token hash matches,
2. `revoked_at IS NULL`,
3. the customer and market are active/approved and tenant access remains valid.

There is no `expires_at > now()` or `used_at IS NULL` requirement for permanent links.

## Admin API

`customer-push-admin` `create_link`:

- generates a 64-character random token,
- stores only its SHA-256 hash,
- inserts a permanent active link without revoking previous links,
- returns `https://push.zhirox.com/?token=<token>`,
- returns `expires_at: null` for compatibility.

`status` returns enough information for the Flutter UI to know whether at least one active link exists even when no device has subscribed yet. Add `active_link_count` (integer >= 0) while preserving existing device status fields.

`revoke_all` revokes all active link tokens and disables all active device subscriptions for that customer. The response continues to include the revoked device count and may additionally expose `revoked_link_count` if implemented without breaking existing clients.

## Flutter UX

- QR dialog text changes from "one-time / 15 minutes" to a permanent-link message such as: "ئەم لینکە بەردەوام کار دەکات تا بەڕێوەبەر ڕایدەگرێت."
- The revoke button is available when either an active link exists or an active device exists.
- The revoke confirmation clearly states that all issued links and connected devices for this customer will be disabled.
- Generating another QR does not silently disable previously shared links.

## Security trade-off

A permanent bearer link has greater exposure risk than a short-lived token. The mitigation is explicit manager revocation, server-side rate limiting, random 256-bit token material, hash-only storage, no customer ID in the URL, and no secret backend credentials in the frontend. If a link is suspected to be exposed, the manager must revoke it and issue a new link.

## Verification

The change is complete only when fresh tests prove:

1. a link remains valid after its former expiry window,
2. the same link can subscribe more than one device,
3. creating a second link does not invalidate the first,
4. manager revoke invalidates all active links immediately,
5. manager revoke disables active push subscriptions,
6. status reports active links even before any device subscribes,
7. Flutter QR copy no longer claims one-time or 15-minute expiry,
8. existing debt/payment push, Deno tests, Flutter tests, policy verification, and iOS build stay green.
