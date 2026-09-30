# OneSignal بۆ ZHIROX VIP User

## دۆخی جێبەجێکردن

- `onesignal_flutter` زیادکراوە.
- OneSignal تەنها کاتێک چالاک دەبێت کە `ONESIGNAL_APP_ID` لە build environment دانرابێت.
- user ـی login کراو بە `Supabase Auth user.id` وەک OneSignal External ID دەبەسترێتەوە.
- لە logout ـدا identity ـی OneSignal پاک دەبێتەوە.
- notification permission لە iOS/Android داوا دەکرێت.
- کلیکی remote notification و `additionalData` وەک stream بەردەستە بۆ deep-link ـی پڕۆفایلی کڕیار/مامەڵە.
- local notifications ـی پێشوو هەر بەردەوامن و نەسڕاونەتەوە.

## Codemagic

لە Codemagic Environment Variables ئەمە زیاد بکە:

`ONESIGNAL_APP_ID=<OneSignal App ID>`

Build command ـەکان ئێستا خۆکار ئەم variable ـە بە `--dart-define` دەدەن بە Flutter.

## OneSignal Dashboard

1. OneSignal App دروست بکە بۆ ZHIROX.
2. Android/Firebase Cloud Messaging credential پەیوەست بکە.
3. iOS/APNs credential پەیوەست بکە.
4. App ID ـەکە بخەرە Codemagic وەک `ONESIGNAL_APP_ID`.

## Security

OneSignal REST API Key نابێت لە Flutter app، GitHub، یان `dart-define` ـی client دابنرێت. بۆ ناردنی notification لە backend، REST API Key تەنها لە Supabase/Vercel server secret هەڵبگیرێت.

## Payload convention بۆ قۆناغی deep-link

پێشنیار:

```json
{
  "target": "customer",
  "customer_id": "<customer-id>"
}
```

یان بۆ مامەڵە:

```json
{
  "target": "transaction",
  "customer_id": "<customer-id>",
  "transaction_id": "<transaction-id>"
}
```

قۆناغی داهاتوو: ئەم payload ـانە بە Navigator ـی ZHIROX ببەسترێنەوە تا بە کلیک ڕاستەوخۆ پڕۆفایلی کڕیار/Financial Chat بکرێتەوە.
