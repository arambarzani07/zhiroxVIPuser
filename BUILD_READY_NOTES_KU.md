# ZHIROX — Build Ready Notes

ئەم ZIP ـە بۆ build کردنی Android و iOS پاککراوەتەوە.

## ئەوەی چاککراوە

- URL ـی PocketBase نوێ لە `lib/utils/constants.dart` هەیە:
  `https://pocketbase-production-e0ff.up.railway.app`
- URL ـی کۆن `https://zhirox.duckdns.org` نەماوە.
- `ios/Podfile` زیادکرا بۆ iOS/CocoaPods.
- فایلی هەڵەی `android/local.properties` کە path ـی Windows ـی تێدا بوو لابرا؛ Flutter خۆی لە build نوێ درووستی دەکات.
- فایلی هەڵەی iOS `Generated.xcconfig` و `flutter_export_environment.sh` کە path ـی Windows ـی تێدا بوو لابران؛ `flutter pub get` دووبارە درووستیان دەکات.
- Android permissions بۆ camera/photos زیادکران.
- iOS permissions بۆ camera/photos/background زیادکران.
- Android release signing بە key.properties اختیاری کرا؛ ئەگەر keystore نەبێت، APK ـی تاقیکردنەوە بە debug signing درووست دەبێت.
- `codemagic.yaml` زیادکرا بۆ build ـی cloud.

## Android APK

```bash
flutter clean
flutter pub get
flutter build apk --release
```

خروجی:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## iOS build check بێ signing

```bash
flutter clean
flutter pub get
cd ios && pod install && cd ..
flutter build ios --release --no-codesign
```

## IPA

بۆ IPA ـی کارا پێویستە Apple Developer signing ڕێک بخرێت. لە Codemagic workflow ـی `ios-signed-ipa` هەیە، بەڵام پێویستە Apple certificate/provisioning profile یان App Store Connect signing ڕێک بکەیت.

## گرنگ

ئەگەر لە GitHub باریدەکەیت، پڕۆژەکە extract بکە و فایلەکانی Flutter لە repo بن، نەک تەنها ZIP.
