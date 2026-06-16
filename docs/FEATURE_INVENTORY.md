ZHIROX AI Debt — Feature Inventory & Engineering Guard

ئەم فایلە نەخشەی پاراستنی پڕۆژەی Zhirox AI Debt ـە.
مەبەست ئەوەیە هیچ تایبەتمەندییەک دووبارە، ناپێویست، یان بە شێوەیەک زیاد نەکرێت کە frontend، backend، PocketBase، Netlify build، یان داتابەیس بشکێنێت.

⸻

1. یاسای سەرەکیی پڕۆژە

Branch Policy

* main = کۆدی فەرمی، سالم و کارا.
* Dev = شوێنی هەموو گۆڕانکاری، تاقیکردنەوە و feature ـی نوێ.
* هیچ feature ـێک نابێت ڕاستەوخۆ لە main زیاد بکرێت.
* هەر feature پاش تاقیکردنەوە و سەرکەوتن دەکرێت Pull Request و Merge بۆ main.

Database Safety Policy

تا ئەو کاتەی بڕیاری تایبەتی نەدرێت:

* Collection نوێ زیاد ناکرێت.
* Field نوێ زیاد ناکرێت.
* API Rules ناگۆڕدرێن.
* PocketBase schema دەستکاری ناکرێت.
* تایبەتمەندی نوێکان سەرەتا read-only / frontend-calculated دەبن.
* ئەگەر feature ـێک داتابەیس دەنووسێت، دەبێت تەنها field/collection ـی هەبوو بەکاربهێنێت.

No Duplicate Feature Rule

پێش زیادکردنی هەر feature ـێک دەبێت بپشکنرێت:

* ئایا پێشتر لە screen ـێکدا هەیە؟
* ئایا لە PBService function ـی هاوشێوە هەیە؟
* ئایا لە pdf_service.dart هەمان کار هەیە؟
* ئایا لە notification_service.dart هەمان کار هەیە؟
* ئایا feature ـەکە تەنها upgrade ـە یان دووبارە نووسینەوە؟

ئەگەر هەیە، نابێت دووبارە بنووسرێت؛ دەبێت بە شێوەی smart / AI upgrade بەرز بکرێتەوە.

⸻

2. دۆخی سۆرس کۆد

Architecture ـی ئێستا

پڕۆژەی Flutter بە شێوەی خوارەوە ڕێکخراوە:

lib/
  main.dart
  providers/
  services/
  screens/
  utils/

شوێنە سەرەکییەکان

lib/services/pb_service.dart
lib/services/pdf_service.dart
lib/services/notification_service.dart
lib/services/connectivity_service.dart
lib/providers/auth_provider.dart
lib/providers/debt_provider.dart
lib/providers/theme_provider.dart
lib/screens/admin/
lib/screens/auth/
lib/screens/customer/
lib/screens/employee/
lib/screens/shared/

شوێنی هەستیار

ئەم فایلانە زۆر هەستیارن و نابێت بێ پلان دەستکاری بکرێن:

lib/services/pb_service.dart
lib/services/pdf_service.dart
lib/providers/auth_provider.dart
lib/screens/shared/add_debt_screen.dart
lib/screens/shared/debt_detail_screen.dart
lib/screens/shared/debt_list_screen.dart
lib/screens/admin/admin_dashboard.dart
lib/screens/shared/user_profile_screen.dart

شوێنی باش بۆ feature ـی نوێ

تایبەتمەندی نوێکان دەبێت لە فایل/فۆڵدەری جیا زیاد بکرێن:

lib/core/intelligence/
lib/features/ai_advisor/
lib/features/ai_quality/
lib/features/customer_intelligence/
lib/features/manager_command/

⸻

3. تایبەتمەندییەکانی ئێستا کە هەن

ئەم تایبەتمەندییانە پێشتر لە سیستەمەکەدا هەن. نابێت دووبارە بنووسرێن.

Auth / Login

- Login بە ژمارەی مۆبایل
- Role system: admin / employee / customer
- Customer approval check
- Employee active check
- Admin subscription check
- Login lockout after failed attempts
- Logout
- Secure storage/cache

User / Customer / Employee

- زیادکردنی کڕیار
- زیادکردنی کارمەند
- admin_id بۆ customer
- created_by
- approved
- active
- debt_limit
- employee permissions
- pending customer requests
- admin subscription renewal

Debt Engine

- زیادکردنی قەرز
- دەستکاری قەرز
- سڕینەوەی قەرز
- amount
- remaining
- status: pending / partial / paid
- due_date
- custom_date
- currency: IQD / USD
- dollar_rate
- amount_usd
- items
- receipt_image
- debt_limit warning

Payment Engine

- زیادکردنی payment
- quick payment buttons
- partial payment
- full payment
- bulk/customer payment
- update remaining
- update status

Reports / PDF

- basic report
- invoice
- admin report
- customer statement
- PDF generation
- printing support

Notifications

- PocketBase notifications
- local notifications
- unread count
- mark as read
- delete notification
- Telegram token/chat id fields

Connectivity

- network status
- connectivity banner
- auto reload when online

⸻

4. تایبەتمەندییەکانی هەبوو کە تەنها دەبێت Upgrade بکرێن

ئەم شتانە هەن، بەڵام دەکرێن زیرەکتر بکرێن:

- Dashboard stats → AI Command Center
- Customer profile → Customer Risk DNA
- Debt limit warning → Suggested Credit Limit + Debt Lock Advisor
- Payment validation → AI Payment Safety Guard
- PDF statement → AI Statement Explainer
- Notifications → AI Priority Alerts
- Customer list → Collection Priority Queue
- Employee permissions → AI Employee Coach

⸻

5. کێشەکانی هەستیار کە پێش feature ـی نوێ دەبێت چاک بکرێن

5.1 Backend URL

دەبێت دڵنیابین baseUrl ئەمەیە:

https://pocketbase-production-18bc.up.railway.app

کێشەی URL ـی کۆن نابێت بگەڕێتەوە.

5.2 Auth Token

نابێت login token بێهۆ پاک بکرێتەوە.
ئەگەر authStore.clear() دوای login هەبێت، API Rules دەتوانێت کێشە درووست بکات.

5.3 debts.admin_id

field هەیە، بەڵام دەبێت لە کاتی create debt پڕ بکرێتەوە.

5.4 payments.admin_id

field هەیە، بەڵام دەبێت لە کاتی create payment پڕ بکرێتەوە.

5.5 notifications.admin_id

field هەیە، بەڵام دەبێت لە notification ـە نوێکان پڕ بکرێتەوە ئەگەر پێویست بوو.

5.6 Service-level Payment Safety

payment validation نابێت تەنها لە UI بێت.
PBService.createPayment خۆی دەبێت چک بکات:

- amount > 0
- amount <= remaining
- debt exists
- debt is not already paid

5.7 Silent Catch

کۆدەکانی catch (_) {} نابێت لە کارە داراییەکان بێدەنگ هەڵە بشارنەوە.
هەڵەی debt/payment دەبێت نیشان بدرێت یان debugPrint بکرێت.

⸻

6. تایبەتمەندییە نوێ و شاهانەکان کە بەڕاستی نیین

ئەم تایبەتمەندییانە بەڕاستی نوێن و سیستەمەکە دەگۆڕن بۆ Money Protection & Credit Intelligence OS.

1. Zhirox AI Intelligence Engine

شوێن:

lib/core/intelligence/zhirox_ai_engine.dart

کار:

- risk calculation
- debt health score
- next best action
- suggested credit limit
- debt lock recommendation
- fraud/mistake detection
- data quality inspection

Schema نوێ ناوێت.

⸻

2. AI Data Quality Checker

شوێن:

lib/features/ai_quality/

دەدۆزێتەوە:

- debts.admin_id = N/A
- payments.admin_id = N/A
- notifications.admin_id = N/A
- paid debt بە remaining > 0
- pending debt بە remaining = 0
- partial debt بە remaining = 0
- قەرزی بێ customer
- payment بێ debt
- customer بێ phone
- debt بە description = N/A
- due_date بەتاڵ یان N/A

Read-only دەبێت. هیچ شتێک خۆکار ناگۆڕێت.

⸻

3. Customer Risk DNA

بۆ هەر customer دۆخ درووست دەکات:

- متمانەپێکراو
- باش
- ئاگاداری
- مەترسیدار
- قەرزی نوێ مەدرێت

لەسەر داتای هەبوو کار دەکات:

debts.remaining
debts.status
payments.amount
users.debt_limit
created / updated

⸻

4. AI Debt Health Score

Score بە frontend حساب دەکرێت:

0 - 100

دۆخ:

- باش
- مامناوەند
- مەترسیدار

ذخیرە ناکرێت.

⸻

5. Next Best Action

بۆ هەر customer پێشنیار دەدات:

- هیچ کارێک پێویست نییە
- پەیامی نەرم بنێرە
- پەیامی فەرمی بنێرە
- قەرزی نوێ مەدە
- سەرەتا بەشێک پارە وەربگرە
- بڕۆ بۆ بەدواداچوون

⸻

6. Collection Priority Queue

کڕیاران ڕیز دەکات بۆ بەدواداچوونی پارە:

1. قەرزی زۆر + هیچ payment نییە
2. قەرزی زۆر + partial
3. pending debts
4. نزیک بە debt_limit
5. کڕیارانی پاک

⸻

7. Suggested Credit Limit

پێشنیار دەدات:

- سنوور زیاد بکە
- سنوور کەم بکە
- سنوور نەگۆڕە
- قەرزی نوێ مەدە

خۆکار update ناکات.

⸻

8. Smart Debt Lock Advisor

تەنها ڕاوێژ دەدات:

پێشنیار: قەرزی نوێ بۆ ئەم کڕیارە مەدرێت

Field نوێ زیاد ناکرێت.

⸻

9. AI Duplicate Debt Warning

پێش زیادکردنی قەرز دەپشکنێت:

- هەمان customer
- هەمان amount
- کاتی نزیک
- description هاوشێوە

⸻

10. AI Fraud / Mistake Detector

دەدۆزێتەوە:

- payment زیاتر لە remaining
- قەرزی گەورە بەبێ تێبینی
- زۆر قەرز بۆ هەمان customer لە کاتی کەم
- remaining/status ناگونجاو
- paid بە remaining ماوە

⸻

11. AI WhatsApp Draft Assistant

پەیامی ژیر ئامادە دەکات بە 3 تۆن:

- نەرم
- فەرمی
- بەهێز

خۆکار نانێرێت. تەنها draft/share/open WhatsApp دەکات.

⸻

12. AI Statement Explainer

لەسەر statement ـی کڕیار summary دەدات:

- کۆی قەرز
- کۆی payment
- ماوە
- قەرزە paid ـەکان
- قەرزە partial ـەکان
- قەرزە pending ـەکان
- ڕاوێژی داهاتوو

⸻

13. AI Daily Briefing

لە dashboard کورتەی ئەمڕۆ پیشان دەدات:

- چەند قەرز زیادکرا
- چەند payment تۆمارکرا
- چەند قەرز paid بوو
- کۆی ماوەی قەرز
- گرنگترین customer بۆ بەدواداچوون

⸻

14. AI Employee Coach

کارمەند پێش save ڕێنمایی دەکرێت:

- customer هەڵبژێردراوە؟
- amount درووستە؟
- debt limit تێپەڕاوە؟
- duplicate debt هەیە؟
- remaining چەند دەبێت؟

⸻

15. AI Manager Command Center

لە dashboard یان بەشی جیا:

- Daily Briefing
- Collection Priority Queue
- Top Risk Customers
- What should I do now?
- Data Quality Warnings
- Suggested Actions

⸻

7. ئەو feature ـانەی نابێت ئێستا زیاد بکرێن

چونکە schema/backend نوێ دەوێت یان مەترسیدارن:

- Audit log collection
- Installment system
- Promise to pay system
- Real WhatsApp API sending
- Scheduled reminders
- Stored AI score
- Branch management advanced
- Ledger collection نوێ
- Dispute system

ئەمەیان دواتر و بە پلانێکی جیا دەکرێن.

⸻

8. ڕیزبەندی جێبەجێکردن

قۆناغی 1 — Foundation Fixes

1. دڵنیابوون لە baseUrl
2. چاککردنی login token issue
3. پڕکردنەوەی debts.admin_id
4. پڕکردنەوەی payments.admin_id
5. زیادکردنی service-level payment safety

قۆناغی 2 — AI Engine

6. zhirox_ai_engine.dart
7. data_quality_issue.dart
8. customer_risk_profile.dart
9. debt_health_score.dart
10. next_best_action.dart

قۆناغی 3 — First AI Feature

11. AI Data Quality Checker
12. Data Quality Screen
13. Data Quality Card on dashboard

قۆناغی 4 — Customer Intelligence

14. Customer Risk DNA
15. Debt Health Score Card
16. Next Best Action Card
17. Suggested Credit Limit Card
18. Smart Debt Lock Advisor Card

قۆناغی 5 — Manager Intelligence

19. Collection Priority Queue
20. AI Daily Briefing
21. AI Manager Command Center
22. What should I do now button

قۆناغی 6 — Employee & WhatsApp Intelligence

23. AI Employee Coach
24. AI Duplicate Debt Warning
25. AI Fraud / Mistake Detector
26. AI WhatsApp Draft Assistant
27. AI Statement Explainer

⸻

9. Commit Rules

هەر feature یان fix بە commit ـی جیا:

Add feature inventory
Fix PocketBase base URL
Preserve auth token after login
Fix admin_id for debts
Fix admin_id for payments
Add service-level payment safety
Add Zhirox AI engine
Add AI data quality checker
Add customer risk DNA
Add manager command center

⸻

10. Test Checklist

دوای هەر commit:

- Flutter build/web سەرکەوتووە؟
- Login کار دەکات؟
- Customer list دەردەکەوێت؟
- Customer create کار دەکات؟
- Debt create کار دەکات؟
- Payment create کار دەکات؟
- remaining/status ڕاست دەبێت؟
- Dashboard crash ناکات؟
- PocketBase logs 400/403/500 نیشان نادات؟
- Netlify deploy سەرکەوتووە؟

⸻

11. Engineering Rule

هەر feature ـی AI باید:

- frontend-only بێت تا دەکرێت
- read-only بێت لە قۆناغی یەکەم
- داتابەیس schema نەگۆڕێت
- PBService تەنها بۆ fix ـی پێویست دەستکاری بکرێت
- screen ـی گەورە تێک نەدات
- بە widget/controller/engine ـی جیا زیاد بکرێت

⸻

12. بڕیاری فەرمی

پڕۆژەکە نابێت لە سەرەتا بنووسرێتەوە.
کۆدی هەبوو بەکاردێت، بەڵام layer ـی زیرەک لەسەری زیاد دەکرێت.

ناوی قۆناغی داهاتوو:

Zhirox AI Debt — Smart Frontend Intelligence Upgrade

مەبەست:

لە ئەپی قەرزەوە → بۆ Money Protection & Credit Intelligence OS
