import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/features/expiry/expiry_frame_crop.dart';

void main() {
  test('portrait BGRA crop contains only pixels inside the date guide', () {
    const width = 100;
    const height = 100;
    final source = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        source[(y * width + x) * 4] = y >= 40 && y < 60 ? 77 : 15;
      }
    }
    final cropped = ExpiryFrameCrop.crop(
      bytes: source,
      width: width,
      height: height,
      bytesPerRow: width * 4,
      bgra: true,
      quarterTurn: false,
    )!;
    expect(cropped.width, 84);
    expect(cropped.height, 20);
    expect(cropped.bytes[0], 77);
    expect(cropped.bytes[cropped.bytes.length - 4], 77);
  });

  test('quarter-turn BGRA crop uses screen-height on sensor x axis', () {
    const width = 200;
    const height = 100;
    final source = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        source[(y * width + x) * 4] = x >= 80 && x < 120 ? 51 : 10;
      }
    }
    final cropped = ExpiryFrameCrop.crop(
      bytes: source,
      width: width,
      height: height,
      bytesPerRow: width * 4,
      bgra: true,
      quarterTurn: true,
    )!;
    expect(cropped.width, 40);
    expect(cropped.height, 84);
    expect(cropped.bytes[0], 51);
  });

  test('NV21 crop keeps Y and VU pairs in their original order', () {
    const width = 100;
    const height = 100;
    final source = Uint8List(width * height * 3 ~/ 2);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        source[y * width + x] = y >= 40 && y < 60 ? 101 : 12;
      }
    }
    for (var i = width * height; i < source.length; i++) {
      source[i] = 128;
    }
    final cropped = ExpiryFrameCrop.crop(
      bytes: source,
      width: width,
      height: height,
      bytesPerRow: width,
      bgra: false,
      quarterTurn: false,
    )!;
    expect(cropped.bytes.length, cropped.width * cropped.height * 3 ~/ 2);
    expect(cropped.bytes.first, 101);
    expect(cropped.bytes[cropped.width * cropped.height], 128);
  });
}
