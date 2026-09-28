import 'dart:typed_data';

/// Crops the camera's raw pixels to the visible date guide before OCR.
/// The guide occupies 84% of the preview width and 20% of its height.
class ExpiryFrameCrop {
  ExpiryFrameCrop._();

  static const left = 0.08;
  static const right = 0.92;
  static const top = 0.40;
  static const bottom = 0.60;

  static CroppedExpiryFrame? crop({
    required Uint8List bytes,
    required int width,
    required int height,
    required int bytesPerRow,
    required bool bgra,
    required bool quarterTurn,
  }) {
    if (width < 8 || height < 8) return null;
    // A landscape sensor rotated to portrait swaps the screen axes. Both
    // screen intervals are symmetric, so the rotation direction is immaterial.
    final xMin = quarterTurn ? top : left;
    final xMax = quarterTurn ? bottom : right;
    final yMin = quarterTurn ? left : top;
    final yMax = quarterTurn ? right : bottom;
    final x0 = (width * xMin).floor() & ~1;
    final x1 = ((width * xMax).ceil() & ~1).clamp(0, width & ~1);
    final y0 = (height * yMin).floor() & ~1;
    final y1 = ((height * yMax).ceil() & ~1).clamp(0, height & ~1);
    final cropWidth = x1 - x0;
    final cropHeight = y1 - y0;
    if (cropWidth < 2 || cropHeight < 2) return null;

    if (bgra) {
      if (bytesPerRow < width * 4 || bytes.length < bytesPerRow * height) {
        return null;
      }
      final stride = cropWidth * 4;
      final cropped = Uint8List(stride * cropHeight);
      for (var y = 0; y < cropHeight; y++) {
        cropped.setRange(
          y * stride,
          (y + 1) * stride,
          bytes,
          (y0 + y) * bytesPerRow + x0 * 4,
        );
      }
      return CroppedExpiryFrame(cropped, cropWidth, cropHeight, stride);
    }

    // NV21 has full-resolution Y followed by interleaved VU at half height.
    // All crop coordinates are even to preserve the chroma pairing.
    if (bytesPerRow < width ||
        bytes.length < bytesPerRow * height + bytesPerRow * (height ~/ 2)) {
      return null;
    }
    final ySize = cropWidth * cropHeight;
    final cropped = Uint8List(ySize + ySize ~/ 2);
    for (var y = 0; y < cropHeight; y++) {
      cropped.setRange(
        y * cropWidth,
        (y + 1) * cropWidth,
        bytes,
        (y0 + y) * bytesPerRow + x0,
      );
    }
    final uvStart = bytesPerRow * height;
    for (var y = 0; y < cropHeight ~/ 2; y++) {
      cropped.setRange(
        ySize + y * cropWidth,
        ySize + (y + 1) * cropWidth,
        bytes,
        uvStart + ((y0 ~/ 2) + y) * bytesPerRow + x0,
      );
    }
    return CroppedExpiryFrame(cropped, cropWidth, cropHeight, cropWidth);
  }
}

class CroppedExpiryFrame {
  const CroppedExpiryFrame(
    this.bytes,
    this.width,
    this.height,
    this.bytesPerRow,
  );

  final Uint8List bytes;
  final int width;
  final int height;
  final int bytesPerRow;
}
