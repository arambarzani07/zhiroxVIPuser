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

## Implemented in this first pass

- Added business-safe UI message guard in `AppHelpers.showSnackBar`.
- Aligned global strings with market language and three visible roles.
- Added a dedicated employee work desk.
- Added clean role/permission getters in `AuthProvider`.

## Remaining Phase 1 follow-up

- Finish safe rebuild of the manager dashboard if the large dashboard file blocks automated editing.
- Confirm customer dashboard wording uses only customer-facing language.
- Run Flutter analyze/build from a local or CI environment.
