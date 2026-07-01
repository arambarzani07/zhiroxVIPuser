# Zhirox AI Debt — Dev Audit & Roadmap

Branch: `Dev`
Base branch: `main`
Workflow rule: all fixes and changes happen on `Dev`; `main` stays protected/stable.

## کاری قوفڵکراو

ئەم پڕۆژەیە بە هەنگاو هەنگاو دەچێتە پێشەوە. سەرەتا هەموو هەڵە، مەترسی، کەم‌وکورتی و شتی ناتەواو ڕیز دەکرێت. پاشان بە priority ورد ورد چاک دەکرێن.

قۆناغەکان:

1. Audit & inventory
2. Frontend cleanup and stabilization
3. Frontend security and data-flow correction
4. Frontend UX/Kurdish RTL refinement
5. Backend planning and API contract
6. Database/schema rebuild or repair
7. Integration
8. Final testing and release preparation

> تێبینی: قۆناغی تاقیکردنەوەی کۆتایی لە کۆتایی دەهێڵرێت، بەڵام smoke checks و analyzer checks دەتوانن دوای هەر گۆڕانکارییەکی بچووک ئەنجام بدرێن.

---

## A. Audit — کەم‌وکورتی و مەترسییەکان

### A1. Repository / project structure

- Root `web/` نییە، بۆیە Flutter Web deploy بۆ Netlify/Cloudflare بە تەواوی ئامادە نییە.
- README نییە یان بەردەست نییە؛ developer onboarding ناتەواوە.
- `test/widget_test.dart` هێشتا counter app smoke test ـە و هاوشێوەی ئەپەکە نییە.
- Project name/label هێشتا generic ـە لە شوێنەکانی وەک Android label.
- بەشێک لە generated desktop/plugin files دەتوانن هەڵسەنگاندن بخوازن پێش merge.

### A2. Config / environment

- PocketBase URL هێشتا hard-coded ـە لە `lib/utils/constants.dart`.
- `AppConfig` و `--dart-define` نییە بۆ جیاکردنەوەی dev/staging/production.
- هیچ environment strategy ـی فەرمی نییە.
- Backend endpoint health check/diagnostic UI نییە.

### A3. Auth / session

- Login باشتر کراوە، بەڵام PocketBase auth token/model بە تەواوی restore ناکرێت لە app restart.
- Secure storage تەنها `user_id` و `user_data` هەڵدەگرێت.
- Offline cache دەتوانێت user ـی کۆن نمایش بکات ئەگەر token invalid بێت.
- Permission/session verification پێویستی بە standardization هەیە.

### A4. Password/security

- `password_text` هێشتا لە codebase هەیە.
- Password لە profile screen دەخوێندرێتەوە و update دەکرێت.
- Legacy password fallback هێشتا هەیە.
- Admin/employee دەتوانێت password ـی user ببینێت/بگۆڕێت بە شێوەی ناسەلامەت.
- دەبێت هەموو password flow ببێتە PocketBase auth hash/reset flow، نە plaintext.

### A5. Tenant isolation / roles

- `market_id` بە شێوەی production tenant boundary نییە.
- جیاکردنەوە زۆرجار بە `admin_id` کراوە.
- Owner/C-Panel role بە فەرمی جیا نەکراوەتەوە.
- Admin management functions پێویستیان بە role guard ـی توند هەیە.
- Employee permissions هەن، بەڵام backend enforcement دەبێت جێگیر بکرێت.

### A6. Debt/payment financial logic

- Payment لە frontend/service دوو هەنگاوە: create payment → update debt remaining.
- Atomic transaction/backend action نییە.
- Overpayment، duplicate payment، concurrent payment، network interruption بە تەواوی پارێزراو نین.
- Balance بە client-side calculation پشتگیری دەکرێت.
- Debt status/remaining دەبێت بە backend source of truth بێت.

### A7. Delete/audit

- Hard delete هێشتا لە debts/payments/users/admin data هەیە.
- `audit_logs` نییە یان بەکار نەهاتووە.
- Financial delete دەبێت ببێتە void/reverse/cancel، نە delete.
- Approval flow بۆ کردارە هەستیارەکان نییە.
- Delete reason / deleted_by / deleted_at / approval_status نییە.

### A8. Reports and statements

- Reports/dashboard بە client-side query و sum پشت دەبەستن.
- `perPage: 500` بۆ sums و lists بە شێوەی production-safe نییە.
- Customer statement دەبێت لە ledger_entries بێت، نە تەنها debts/payments list.
- PDF/CSV export دەبێت backend-confirmed totals بەکار بهێنێت.

### A9. Notifications

- Notifications لە create debt/payment inline دروست دەکرێن.
- Failure ـی notification زۆرجار silent ignore دەکرێت.
- WhatsApp reminder draft هێشتا بە شێوەی فەرمی/قابل audit نەکراوە.
- Telegram/token-related pattern دەبێت لە UX/security دووبارە هەڵسەنگێندرێت.

### A10. UX/UI frontend

- Kurdish RTL هەیە، بەڵام consistency ـی labels/messages پێویستی بە polishing هەیە.
- Error handling زۆرجار silent catch ـە.
- Loading/error/empty states پێویستیان بە standard reusable widgets هەیە.
- Customer profile chat/timeline هەیە، بەڵام دەبێت لە ledger و backend truth پشتگیری بکرێت.
- Forms پێویستیان بە validation و helper text ـی یەکگرتوو هەیە.

### A11. Code architecture

- `PBService` زۆر گەورەیە و auth/users/debts/payments/reports/notifications تێکەڵ کراون.
- Screens هەندێک جار ڕاستەوخۆ PocketBase/logic بانگ دەکەن.
- Repository/service separation پێویستە.
- Business logic دەبێت لە UI داببڕێت.
- Error model و result pattern نییە.

### A12. Web/mobile platform readiness

- Web support root folder نییە.
- Workmanager/background notifications دەتوانێت لە web build کێشە دروست بکات.
- Conditional platform handling پێویستە.
- Android/iOS labels, permissions, release config پێویستیان بە هەڵسەنگاندن هەیە.

---

## B. Priority order

### P0 — Safety blockers

1. Create root `web/` correctly.
2. Replace hard-coded PB URL with `AppConfig` + `--dart-define`.
3. Fix PocketBase auth token/model persistence and restore.
4. Remove `password_text` reads/writes from UI and new create/update flows.
5. Disable or guard hard-delete financial actions.
6. Stop relying on frontend-only payment balance updates for production path.
7. Replace broken counter widget test.

### P1 — Frontend stabilization

1. Split `PBService` gradually into domain services/repositories.
2. Standardize loading, empty, and error states.
3. Clean forms and validation.
4. Improve Kurdish RTL labels/messages.
5. Prepare routes/role guards for owner/admin/employee/customer.
6. Add frontend API contract layer.

### P2 — Backend/database design

1. Define market-first schema with `market_id`.
2. Add ledger_entries, audit_logs, approval_requests, market_settings.
3. Define backend actions for debt create, payment receive, reverse, void.
4. Define auth and permission rules.
5. Define report/export endpoints.

### P3 — Integration

1. Connect frontend to backend actions.
2. Replace direct risky writes.
3. Verify tenant isolation.
4. Verify role permissions.
5. Verify notifications/reminders.

### P4 — Final testing/release

1. Flutter analyze.
2. Unit/widget smoke tests.
3. Manual role-by-role test.
4. Debt/payment financial scenario test.
5. Web build test.
6. Android build test.
7. Final production checklist.

---

## C. Immediate first frontend tasks on Dev

### Task 1 — Web support

- Run: `flutter create . --platforms web`
- Do not copy `test/web` manually.
- Keep generated root `web/` files.
- Verify `flutter build web` later.

### Task 2 — Config cleanup

- Create `lib/config/app_config.dart`.
- Move backend URL out of constants.
- Use:

```dart
class AppConfig {
  static const String pbBaseUrl = String.fromEnvironment(
    'PB_BASE_URL',
    defaultValue: 'https://pocketbase-production-18bc.up.railway.app',
  );
}
```

### Task 3 — Auth persistence

- Save PocketBase auth token and model after login.
- Restore token/model before loading user on app startup.
- Clear token/model on logout.

### Task 4 — Password cleanup phase 1

- Stop showing `password_text` in profile.
- Stop writing `password_text` for new users.
- Keep legacy fallback only temporarily behind a migration note.

### Task 5 — Test cleanup

- Replace counter widget test with app/login smoke test.

---

## D. Rules for all future commits

- Work only on `Dev`.
- One small logical change per commit.
- No direct changes to `main`.
- No feature expansion before P0 safety blockers.
- No mock production data.
- No plaintext passwords.
- No hard-delete for financial records.
- No client-side final balance as source of truth.
- Every risky financial/security action must become backend-owned later.
