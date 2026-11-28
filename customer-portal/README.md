# Customer portal — deployed snapshot 20261128-9

Archive of the publicly served text assets from https://zhirox.com/ on 2026-11-28, for Vercel production deployment dpl_6EXTuCVQNnNg5GNFyZtZ1grSM3t7. Production is unchanged. This is not yet an independently reproducible source build.

## Recovered files (8/9)
- index.html
- app.js
- manifest-bootstrap.js
- manifest.webmanifest
- portal-banking.css
- styles.css
- sw.js
- vercel.json — exact original bytes recovered by combining the source prefix with the previous deployment's rewrite section. SHA-1: dd3051769b6f2fbddd702e74f060afa1427cbf0c.

## Remaining binary asset
- apple-touch-icon.png — live public PNG verified in an ephemeral Vercel sandbox: 69,318 bytes; SHA-1 178acfe82ca55e8ebfd85e63bbc22b658fa7cbdf. The tool's output and call limits prevented transferring the entire binary into GitHub. The sandbox stopped automatically after its 60-second limit.

To recover in a trusted checkout of this branch, from the customer-portal directory:
```bash
set -e
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
curl --fail --silent --show-error --max-time 30 https://zhirox.com/apple-touch-icon.png -o "$tmp"
printf '%s  %s\n' 178acfe82ca55e8ebfd85e63bbc22b658fa7cbdf "$tmp" | sha1sum -c -
test "$(wc -c < "$tmp")" -eq 69318
cp "$tmp" apple-touch-icon.png
```
Commit the verified PNG only if the check passes. Do not substitute a different image.

The seven HTTP-served text assets may differ from original deployment source bytes. No private credentials, environment files or customer records are intentionally archived. Backend migration reconciliation and PR #55 remain separate. Do not run migrations or deploy this partial archive automatically.
