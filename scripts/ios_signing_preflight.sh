#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  P12_PASSWORD='your-password' ./scripts/ios_signing_preflight.sh \
    /path/to/apple-distribution.p12 \
    /path/to/owner.mobileprovision \
    /path/to/user.mobileprovision \
    [EXPECTED_TEAM_ID]

Validates locally on macOS:
  - Apple Distribution identity in the P12
  - Owner profile bundle ID: com.karoxghafoor.zhirox.owner
  - User profile bundle ID:  com.karoxghafoor.zhirox.user
  - Team ID consistency
  - Ad Hoc device list is present
  - Profile is not expired
  - get-task-allow is false

The script never prints certificate/profile bytes or the P12 password.
EOF
}

if [[ $# -lt 3 || $# -gt 4 ]]; then
  usage
  exit 2
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: This validator must run on macOS because it uses Apple's security tool." >&2
  exit 1
fi

for tool in security python3; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "ERROR: Missing required tool: $tool" >&2
    exit 1
  }
done

P12_PATH="$1"
OWNER_PROFILE="$2"
USER_PROFILE="$3"
EXPECTED_TEAM_ID="${4:-}"
P12_PASSWORD="${P12_PASSWORD:-}"

[[ -f "$P12_PATH" ]] || { echo "ERROR: P12 not found: $P12_PATH" >&2; exit 1; }
[[ -f "$OWNER_PROFILE" ]] || { echo "ERROR: Owner profile not found: $OWNER_PROFILE" >&2; exit 1; }
[[ -f "$USER_PROFILE" ]] || { echo "ERROR: User profile not found: $USER_PROFILE" >&2; exit 1; }
[[ -n "$P12_PASSWORD" ]] || { echo "ERROR: Set P12_PASSWORD in the environment." >&2; exit 1; }

TMP_DIR="$(mktemp -d)"
KEYCHAIN_PATH="$TMP_DIR/zhirox-preflight.keychain-db"
KEYCHAIN_PASSWORD="$(uuidgen)$(uuidgen)"
cleanup() {
  security delete-keychain "$KEYCHAIN_PATH" >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null
security set-keychain-settings -lut 600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$P12_PATH" \
  -P "$P12_PASSWORD" \
  -A \
  -t cert \
  -f pkcs12 \
  -k "$KEYCHAIN_PATH" >/dev/null

IDENTITY_COUNT="$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep -c 'Apple Distribution' || true)"
if [[ "$IDENTITY_COUNT" -lt 1 ]]; then
  echo "ERROR: The P12 does not contain a valid Apple Distribution signing identity." >&2
  exit 1
fi

decode_profile() {
  local profile_path="$1"
  local output_path="$2"
  security cms -D -i "$profile_path" > "$output_path"
}

OWNER_PLIST="$TMP_DIR/owner.plist"
USER_PLIST="$TMP_DIR/user.plist"
decode_profile "$OWNER_PROFILE" "$OWNER_PLIST"
decode_profile "$USER_PROFILE" "$USER_PLIST"

PROFILE_RESULT="$TMP_DIR/result.json"
python3 - "$OWNER_PLIST" "$USER_PLIST" "$EXPECTED_TEAM_ID" > "$PROFILE_RESULT" <<'PY'
import json
import plistlib
import sys
import time
from pathlib import Path

owner_path, user_path, expected_team = sys.argv[1:4]

EXPECTED = {
    "owner": "com.karoxghafoor.zhirox.owner",
    "user": "com.karoxghafoor.zhirox.user",
}


def load_and_validate(label: str, path: str):
    with Path(path).open("rb") as fh:
        profile = plistlib.load(fh)

    teams = profile.get("TeamIdentifier") or []
    if not teams:
        raise SystemExit(f"ERROR: {label} profile has no TeamIdentifier")
    team = str(teams[0])

    ent = profile.get("Entitlements") or {}
    app_id = str(ent.get("application-identifier") or "")
    wanted = f"{team}.{EXPECTED[label]}"
    if app_id != wanted:
        raise SystemExit(
            f"ERROR: {label} profile bundle mismatch. Expected {wanted}, got {app_id or '<empty>'}"
        )

    devices = profile.get("ProvisionedDevices") or []
    if not devices:
        raise SystemExit(f"ERROR: {label} profile is not Ad Hoc: ProvisionedDevices is empty")

    if ent.get("get-task-allow") is True:
        raise SystemExit(f"ERROR: {label} profile has get-task-allow=true; expected Ad Hoc distribution")

    expiry = profile.get("ExpirationDate")
    if expiry is None or expiry.timestamp() <= time.time():
        raise SystemExit(f"ERROR: {label} profile is expired")

    name = str(profile.get("Name") or "")
    uuid = str(profile.get("UUID") or "")
    if not name or not uuid:
        raise SystemExit(f"ERROR: {label} profile is missing Name or UUID")

    return {
        "label": label,
        "team": team,
        "bundle_id": EXPECTED[label],
        "name": name,
        "uuid": uuid,
        "expiry": expiry.isoformat(),
        "device_count": len(devices),
    }

owner = load_and_validate("owner", owner_path)
user = load_and_validate("user", user_path)

if owner["team"] != user["team"]:
    raise SystemExit(
        f"ERROR: Owner/User profiles use different Team IDs: {owner['team']} vs {user['team']}"
    )

if expected_team and owner["team"] != expected_team:
    raise SystemExit(
        f"ERROR: Expected Team ID {expected_team}, but profiles use {owner['team']}"
    )

json.dump({"team_id": owner["team"], "profiles": [owner, user]}, sys.stdout)
PY

python3 - "$PROFILE_RESULT" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    result = json.load(fh)

print("iOS signing preflight: PASS")
print(f"Team ID: {result['team_id']}")
for profile in result["profiles"]:
    print(
        f"{profile['label'].capitalize()}: "
        f"{profile['bundle_id']} | "
        f"profile={profile['name']} | "
        f"devices={profile['device_count']} | "
        f"expires={profile['expiry']}"
    )
print("Apple Distribution identity: PASS")
print("Ready to encode these files as GitHub Actions secrets.")
PY
