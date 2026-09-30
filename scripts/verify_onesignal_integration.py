#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]

checks = {
    "pubspec.yaml": ["onesignal_flutter:"],
    "lib/services/notification_service.dart": [
        "package:onesignal_flutter/onesignal_flutter.dart",
        "OneSignal.initialize",
        "OneSignal.login",
        "OneSignal.logout",
        "OneSignal.Notifications.requestPermission",
        "addClickListener",
        "ONESIGNAL_APP_ID",
    ],
    "lib/services/onesignal_push_service.dart": [
        "onesignal-send",
        "paymentReceived",
        "debtCreated",
        "debtLimitWarning",
        "syncError",
    ],
    "supabase/functions/onesignal-send/index.ts": [
        "ONESIGNAL_APP_ID",
        "ONESIGNAL_REST_API_KEY",
        "include_aliases",
        "external_id",
        "can_send_push_notifications",
        "cross_tenant_forbidden",
        'https://api.onesignal.com/notifications',
    ],
    "android/app/src/main/AndroidManifest.xml": [
        "android.permission.POST_NOTIFICATIONS",
        "android.permission.INTERNET",
    ],
    "ios/Runner/Info.plist": [
        "UIBackgroundModes",
        "remote-notification",
    ],
    "ios/Runner/Runner.entitlements": [
        "aps-environment",
        "$(APS_ENVIRONMENT)",
    ],
    "ios/Flutter/Debug.xcconfig": [
        "CODE_SIGN_ENTITLEMENTS=Runner/Runner.entitlements",
        "APS_ENVIRONMENT=development",
    ],
    "ios/Flutter/Release.xcconfig": [
        "CODE_SIGN_ENTITLEMENTS=Runner/Runner.entitlements",
        "APS_ENVIRONMENT=production",
    ],
    "codemagic.yaml": [
        "ONESIGNAL_DISABLE_LOCATION",
        "--dart-define=ONESIGNAL_APP_ID=",
        "com.karoxghafoor.zhirox.user",
    ],
}

errors: list[str] = []
for relative, required in checks.items():
    path = ROOT / relative
    if not path.exists():
        errors.append(f"missing file: {relative}")
        continue
    text = path.read_text(encoding="utf-8")
    for needle in required:
        if needle not in text:
            errors.append(f"{relative}: missing contract {needle!r}")

if errors:
    print("OneSignal integration contract FAILED", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    sys.exit(1)

print("OneSignal integration contract OK")
