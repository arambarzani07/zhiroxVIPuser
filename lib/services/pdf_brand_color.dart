import 'package:pdf/pdf.dart';

/// Converts the market receipt color to a PDF color with the shared fallback.
PdfColor receiptBrandColor(String hex) {
  final clean = hex.replaceAll('#', '');
  final value = int.tryParse(clean, radix: 16) ?? 0x0F766E;
  return PdfColor(
    ((value >> 16) & 0xff) / 255,
    ((value >> 8) & 0xff) / 255,
    (value & 0xff) / 255,
  );
}
