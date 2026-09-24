# ZHIROX NEXT — پلانی گۆڕانکاری ١٠٠٪

ئەم پلانە بۆ `user-source` ـە. یاسای سەرەکی: هیچ قۆناغێک بە نیوەیی بەجێ ناهێڵدرێت. هەر قۆناغێک پێویستە analyze + tests + iOS build تێپەڕێنێت پێش دەستپێکردنی قۆناغی داهاتوو.

## یاساکانی پاراستن

- business data online-only دەمێنێت؛ stale business cache دروست ناکرێت.
- tenant isolation و RLS نابێت لاواز بکرێت.
- System Owner لە User app ـدا business data ـی مارکێت نابینێت.
- General customer payment تەنها overall balance کەم دەکات؛ individual debt ناگۆڕێت.
- Debt-specific payment تەنها debt ـی هەڵبژێردراو دەگۆڕێت.
- Customer portal installment UI نابێت بگەڕێتەوە.
- هەر refactor ـێک لە business rule جیا دەکرێتەوە؛ refactor نابێت semantic ـی دارایی بە بێ migration/test بگۆڕێت.

## قۆناغی ١ — Foundation / Design System / Shell

**ئامانج:** یەک بنەمای UI و navigation بۆ redesign ـی داهاتوو.

- spacing/motion/breakpoint tokens
- unified async loading/error/empty states
- unified ZHIROX app shell
- unified Admin + Employee bottom navigation
- connectivity status surface
- lazy tab preservation
- widget tests بۆ shell/state

**Definition of Done**
- flutter analyze = success
- flutter test = success
- iOS unsigned build = success
- هیچ business rule یان schema گۆڕانکاری نەکرابێت

## قۆناغی ٢ — Customer Center

- customer directory state controller
- search/filter/sort/pagination لە UI جیا بکرێتەوە
- quick actions بخرێنە action layer
- duplicate/VIP/pin/inbox indicators یەکدەست بکرێن
- list screen لە God Screen بگۆڕدرێت بۆ feature components
- full regression tests

## قۆناغی ٣ — Customer 360 Profile

- user_profile_screen.dart دابەش بکرێت
- Overview / Financial Timeline / Documents / Details
- profile controller/state
- realtime coordinator
- payment/debt/document actions جیا بکرێنەوە
- current behavior پارێزراو بێت

## قۆناغی ٤ — Debt Composer

- add_debt_screen.dart دابەش بکرێت
- customer selector
- amount/items editor
- currency/rate
- dates
- debt-limit validation
- receipt attachment
- review/confirm
- create/edit semantics بە test

## قۆناغی ٥ — Payments Domain

- General Payment و Debt-specific Payment دوو flow ـی ڕوون
- dead legacy allocator لاببرێت دوای دڵنیابوون لە no-runtime-reference
- canonical payment domain model
- receipt linkage
- full regression suite

## قۆناغی ٦ — Documents Center

- Statement / Receipt / PDF / CSV / Share / Print
- DocumentEngine ـی یەکتا
- native/web terminology هاوتا بکرێت
- receipt settings/history/governance یەکدەست
- immutable official statement phase

## قۆناغی ٧ — Notifications Center

- local notification و customer web push لە UI/domain جیا و ڕوون
- status/history/retry/manual/broadcast
- deep links
- permission-aware actions

## قۆناغی ٨ — Settings & Governance

- operational features لە Settings دەربهێنرێن
- Settings تەنها configuration
- Employees/permissions
- Audit/Backup/Restore
- Subscription/FIB
- Receipt settings
- Integrations/Daftar status

## قۆناغی ٩ — Data Layer Cleanup

- PocketBase-shaped RecordModel dependency کەم بکرێتەوە
- typed domain models
- repositories: auth/customer/finance/document/notification/sync
- PBService breakup
- compatibility layer retire plan
- no behavior drift

## قۆناغی ١٠ — Realtime & Connectivity

- centralized realtime coordination
- request deduplication
- server-reachable vs network-available status
- reconnect semantics
- no stale business data

## قۆناغی ١١ — Daftar Boundary

- UI لە live/mirror/primary source ئاگادار نەبێت
- canonical repository boundary
- sync health surface بۆ admin
- existing failover/reconciliation protections پارێزراو بن

## قۆناغی ١٢ — Full UX/RTL/Performance Pass

- Kurdish terminology catalog
- RTL audit
- dark/light
- compact/comfortable
- accessibility
- pagination/performance
- zero duplicated loading/error/empty states

## قۆناغی ١٣ — Release Hardening

- quick validation vs full release workflow
- regression matrix
- Android/iOS checks
- rollback validation
- release candidate build
