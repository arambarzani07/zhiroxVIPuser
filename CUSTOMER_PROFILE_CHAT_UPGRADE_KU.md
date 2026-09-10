# ZHIROX Customer Profile — Online Only

ئەم فایلە دۆخی ئێستای Customer Profile ڕوون دەکاتەوە.

## دیزاینی ئێستا

- پڕۆفایلی کڕیار بە سێ بەش ڕێکخراوە: `پوختە`، `مامەڵەکان` و `دەستکاری`.
- قەرز و پارەدانەوەکان لە timeline/list ـێکی compact نیشان دەدرێن؛ chat bubble ـی کۆن بەکارناهێنرێت.
- status color تەنها بۆ واتای دارایی/دۆخ بەکاردێت، نە بۆ هەموو card ـەکە.

## Online-only policy

- داتای `profiles/users`، `debts`، `payments` و `notifications` لە backend ـی live دەخوێندرێتەوە.
- هیچ business-data offline cache ـێک لە Customer Profile بەکارناهێنرێت.
- ئەگەر network/server fetch سەرکەوتوو نەبێت، stale data نابێتە جێگرەوە؛ error/Retry نیشان دەدرێت.
- global online-only gate لە `lib/main.dart` بەکارهێنانی ئەپ لە کاتی نەبوونی network ڕادەگرێت.

## پێویستی داتابەیس

هەمان schema ـی ئێستا بەسە: `profiles/users`، `debts`، `payments` و `notifications`. هیچ collection/table ـی نوێ بۆ ئەم UI ـە پێویست نییە.

## تاقیکردنەوە

1. بە هەژماری ڕێپێدراو بچۆ ژوورەوە.
2. کڕیارێک هەڵبژێرە.
3. قەرز و پارەدانەوە زیاد بکە.
4. لە `مامەڵەکان` دڵنیابە لە نیشاندانی داتای live.
5. network ببڕە و پشتڕاست بکە کە ئەپ business data ـی cacheکراو پیشان نادات.
