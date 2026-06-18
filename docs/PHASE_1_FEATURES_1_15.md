# Zhirox AI Debt — Phase 1 / Features 1-15

## Locked direction

Zhirox is a market money-protection system with exactly three visible roles:

1. بەڕێوەبەر
2. کارمەند
3. کڕیار

No developer, backend, database, API, field, collection, record, null, failed, or server wording may appear in the market-facing UI.

## Phase 1 scope

1. داخڵبوون بە پێی ڕۆڵ
2. داشبۆردی بەڕێوەبەر
3. میزکاری کارمەند
4. داشبۆردی کڕیار
5. ناوبەری جیاواز بۆ هەر ڕۆڵ
6. دەسەڵاتی بەڕێوەبەر
7. دەسەڵاتی کارمەند
8. دەسەڵاتی کڕیار
9. ڕێکخستنی permission ـی کارمەند
10. پەیامی ڕێنماییی پاک
11. قەدەغەکردنی پەیامی ناوخۆیی/تەکنیکی
12. پەیامی ئینتەرنێت بە شێوەی پاراستن
13. cache/queue لە پشتەوە، بەبێ دەرخستنی کێشە
14. ڕووکار بە زمانی مارکێت
15. RTL و وشەسازی یەکسان

## Allowed user-facing guidance

- تکایە کڕیارێک هەڵبژێرە
- تکایە بڕی قەرز بنووسە
- تکایە بڕی پارەی وەرگیراو بنووسە
- بڕی پارە دەبێت لە سفر زیاتر بێت
- بڕی پارەی وەرگیراو نابێت زیاتر بێت لە قەرزی ماوە
- ئەم کردارە پێویستی بە ڕێگەپێدانی بەڕێوەبەر هەیە
- پارێزرا ✅ کاتێک ئینتەرنێت گەڕایەوە، خۆکارانە تەواو دەبێت

## Forbidden visible wording

- هەڵە ڕوویدا
- داتابەیس
- سێرڤەر
- API
- backend
- database
- server
- field
- collection
- record
- admin_id
- null
- failed
- exception
- try again

## Implemented in this pass

- Added business-safe UI message guard in `AppHelpers.showSnackBar`.
- Aligned global strings with market language and three visible roles.
- Added clean role/permission getters in `AuthProvider`.
- Added a dedicated employee work desk.
- Added a clean manager dashboard focused on money protection and decisions.
- Retired the old manager dashboard shell by exporting the clean dashboard.
- Added a clean customer dashboard focused on `قەرزی من` and `وەصڵەکان`.
- Routed manager and customer roles from `main.dart` to the new clean dashboards.
- Replaced the app-wide connectivity banner with the approved protected-action wording.

## Remaining Phase 1 follow-up

- Run Flutter analyze/build from a local or CI environment.
- Review all remaining screens for old wording that may still appear when reached from role dashboards.
- Move remaining phase-1 refinements into smaller commits to avoid large-file editing blocks.
