# پلانی سەلامەت بۆ گۆڕینی وشەکانی پارە وەرگرتنەوە لە debt_list_screen.dart

ئەم فایلە بۆ ئەوەیە کە گۆڕانکارییەکانی `lib/screens/shared/debt_list_screen.dart` بە شێوەی ورد و بێ‌شکاندنی فایلە گەورەکە جێبەجێ بکرێن.

## دۆخی ئێستا

- `constants.dart` وشە گشتییەکانی پارە وەرگرتنەوەی هەیە.
- `helpers.dart` وشەکانی status ـی `partial` و `paid` یەکدەست کراون.
- `debt_list_screen.dart` جارێ نابێت بە تەواوی نووسرێتەوە.

## گۆڕانکارییە بچووکە پێویستەکان

### 1. ناونیشانی dialog

گۆڕینی دەقی کۆن:

```dart
'پارەدانەوە بۆ ${customer.name}'
```

بۆ دەقی نوێ:

```dart
'${AppStrings.paymentForCustomer} ${customer.name}'
```

### 2. label ـی خانەی بڕ

گۆڕینی label بۆ:

```dart
AppStrings.paymentAmount
```

### 3. note ـی پارە وەرگرتنەوەی کۆمەڵ

گۆڕینی note بۆ:

```dart
AppStrings.bulkPaymentNote
```

### 4. پەیامی سەرکەوتن

گۆڕینی پەیامی سەرکەوتن بۆ دەقی بنەڕەتی:

```dart
AppStrings.paymentSaved
```

یان بە ژمارەی قەرز:

```dart
'${AppStrings.paymentSaved} (${distribution.length} قەرز)'
```

## سنووری کاری هەنگاوی دواتر

- تەنها text/label دەگۆڕدرێت.
- logic ـی داتابەیس، payment distribution، remaining، status، cache، realtime، و sorting دەستکاری ناکرێت.
- `main` دەستکاری ناکرێت.
- build تەنها کاتێک دەکرێت کە بەڕێوەبەر داوای بکات.
