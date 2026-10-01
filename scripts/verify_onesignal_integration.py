#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]

checks = {
    "pubspec.yaml": ["onesignal_flutter:"],
    "lib/main.dart": [
        "RemoteNotificationGate",
        "remote_notification_gate.dart",
    ],
    "lib/widgets/remote_notification_gate.dart": [
        "remoteNotificationClicks",
        "UserProfileScreen",
        "openFinancialChat",
        "canViewCustomers",
    ],
    "lib/services/notification_service.dart": [
        "package:onesignal_flutter/onesignal_flutter.dart",
        "OneSignal.initialize",
        "OneSignal.login",
        "OneSignal.logout",
        "OneSignal.Notifications.requestPermission",
        "addClickListener",
        "ONESIGNAL_APP_ID",
        "onesignal-config",
        "_resolveOneSignalAppId",
    ],
    "lib/services/onesignal_push_service.dart": [
        "onesignal-send",
        "paymentReceived",
        "debtCreated",
        "debtLimitWarning",
        "syncError",
    ],
    "supabase/functions/onesignal-config/index.ts": [
        "ONESIGNAL_APP_ID",
        "configured",
        "app_id",
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
    "supabase/functions/_shared/onesignal.ts": [
        "sendOneSignalFinancialEventBestEffort",
        "sendOneSignalOutboxEventBestEffort",
        "idempotency_key",
        "include_aliases",
        "external_id",
        "new_debt",
        "payment_received",
        "due_reminder",
        "installment_reminder",
        "debt_limit_changed",
        "monthly_statement",
        "manual",
    ],
    "supabase/functions/customer-push-events/index.ts": [
        "sendOneSignalFinancialEventBestEffort",
        "sendMobilePush",
        'eventType: "debt_created"',
    ],
    "supabase/functions/record-payment/index.ts": [
        "sendOneSignalFinancialEventBestEffort",
        "sendMobilePush",
        'eventType: "payment_created"',
    ],
    "supabase/functions/customer-push-worker/index.ts": [
        "sendOneSignalOutboxEventBestEffort",
        "sendMobilePush",
        "eventPreferenceAllows",
        "due_reminders",
        "installment_reminders",
        "monthly_statements",
        "manual_messages",
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
    "ios/Podfile": [
        "CODE_SIGN_ENTITLEMENTS",
        "Runner/Runner.entitlements",
        "APS_ENVIRONMENT",
        "development",
        "production",
    ],
    "codemagic.yaml": [
        "ONESIGNAL_DISABLE_LOCATION",
        "--dart-define=ONESIGNAL_APP_ID=",
        "com.karoxghafoor.zhirox.user",
    ],
    ".github/workflows/ios-unsigned-ipa.yml": [
        "CODE_SIGN_ENTITLEMENTS=Runner/Runner.entitlements",
        "APS_ENVIRONMENT=production",
        "Package signer-ready IPA with production push entitlement",
        "<key>aps-environment</key>",
        "<string>production</string>",
        "codesign --force --deep --sign - Payload/Runner.app",
        "--entitlements /tmp/zhirox-signer-entitlements.plist",
        "Print :aps-environment",
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