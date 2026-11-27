#!/usr/bin/env bash
# Read-only release gate. Run from a clone that has both staging refs.
# Usage: bash check_vip_client_endpoints.sh USER_REF OWNER_REF
set -euo pipefail
[[ $# -eq 2 ]] || { echo 'Usage: check_vip_client_endpoints.sh USER_REF OWNER_REF' >&2; exit 2; }
old_ref='madoflmbretqghqbqaak'
target_url='https://ryzgbajgjctmliwhvezo.supabase.co'
for ref in "$@"; do
  git rev-parse --verify "$ref^{commit}" >/dev/null
  if git grep -I -l -F "$old_ref" "$ref" -- lib ios customer-push-web; then
    echo "FAIL: retired project reference in $ref" >&2
    exit 1
  else
    code=$?
    [[ $code -eq 1 ]] || exit "$code"
  fi
  if ! git show "$ref:lib/utils/constants.dart" | grep -F "$target_url" >/dev/null; then
    echo "FAIL: target project URL missing in $ref" >&2
    exit 1
  fi
  echo "PASS: $ref client endpoint gate"
done
for path in _headers _redirects app.js manifest-bootstrap.js onesignal-setup.html; do
  if ! git show "$1:customer-push-web/$path" | grep -F "$target_url" >/dev/null; then
    echo "FAIL: missing target URL in customer portal $path" >&2
    exit 1
  fi
done
echo 'PASS: customer portal target URLs'
