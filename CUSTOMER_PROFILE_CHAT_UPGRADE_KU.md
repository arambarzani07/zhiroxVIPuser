# ZHIROX Customer Profile Chat Upgrade

ئەم وەشانە تایبەتمەندی **Customer Profile بە شێوەی چات** زیاد دەکات.

## چی گۆڕاوە؟

- لە `UserProfileScreen` ـدا timeline/card ـی نوێ زیادکرا.
- قەرز پێدانەکان لای ڕاست وەک bubble/card دەردەکەون.
- پارەدانەوەکان لای چەپ وەک bubble/card دەردەکەون.
- Debt Health strip زیادکرا بۆ نیشاندانی دۆخی کڕیار.
- داتا لە `debts` و `payments` دەخوێندرێتەوە؛ collection نوێ پێویست نییە.
- Offline cache بۆ payments ـیش زیادکرا.

## فایلە گۆڕاوەکان

- `lib/screens/shared/user_profile_screen.dart`
- `lib/services/pb_service.dart`

## پێویستی داتابەیس

هەمان schema ـی ئێستا بەسە:

- `users`
- `debts`
- `payments`
- `notifications`

هیچ collection ـی نوێ زیاد نەکراوە.

## گرنگ

بۆ ئەوەی پارەدانەوەکان لە پڕۆفایلی کڕیاردا دەربکەون، `payments.debt` دەبێت relation بێت بۆ `debts` و `debts.customer` relation بێت بۆ `users`.

## تاقیکردنەوە

1. بە admin login بکە.
2. کڕیارێک درووست بکە.
3. قەرزێک زیاد بکە.
4. پارەدانەوە بۆ هەمان قەرز زیاد بکە.
5. بڕۆ پڕۆفایلی کڕیار.
6. قەرز دەبێت لای ڕاست و پارەدانەوە لای چەپ دەربکەون.
