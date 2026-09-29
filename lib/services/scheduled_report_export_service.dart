import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:zhirox/utils/kurdish_reshaper.dart';

class ScheduledReportExportService {
  ScheduledReportExportService._();

  static String reportKindLabel(String kind) {
    return switch (kind) {
      'daily_summary' => 'پوختەی ڕۆژانە',
      'collections' => 'کۆکردنەوەی قەرز',
      'cash_flow' => 'Cash Flow Forecast',
      'employee_performance' => 'کارایی کارمەند',
      'data_quality' => 'Data Quality',
      _ => kind,
    };
  }

  static Map<String, String> _flatten(
    Map<String, dynamic> source, {
    String prefix = '',
  }) {
    final out = <String, String>{};
    for (final entry in source.entries) {
      final key = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';
      final value = entry.value;
      if (value is Map) {
        out.addAll(
          _flatten(
            Map<String, dynamic>.from(value),
            prefix: key,
          ),
        );
      } else if (value is List) {
        out[key] = jsonEncode(value);
      } else {
        out[key] = value?.toString() ?? '';
      }
    }
    return out;
  }

  static String _csvCell(dynamic value) {
    final text = value?.toString() ?? '';
    final escaped = text.replaceAll('"', '""');
    if (escaped.contains(',') ||
        escaped.contains('"') ||
        escaped.contains('\n') ||
        escaped.contains('\r')) {
      return '"$escaped"';
    }
    return escaped;
  }

  static String _rowsToCsv(List<List<dynamic>> rows) {
    return rows
        .map((row) => row.map(_csvCell).join(','))
        .join('\r\n');
  }

  static String _safeStamp(String value) {
    final parsed = DateTime.tryParse(value);
    final date = (parsed ?? DateTime.now()).toLocal();
    return '${date.year.toString().padLeft(4, '0')}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}_'
        '${date.hour.toString().padLeft(2, '0')}'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  static String _fileBase(Map<String, dynamic> run) {
    final kind = run['report_kind']?.toString() ?? 'report';
    final stamp = _safeStamp(run['generated_at']?.toString() ?? '');
    return 'zhirox_${kind}_$stamp';
  }

  static Future<void> shareCsv(Map<String, dynamic> run) async {
    final payloadRaw = run['payload'];
    final payload = payloadRaw is Map
        ? Map<String, dynamic>.from(payloadRaw)
        : <String, dynamic>{};
    final flat = _flatten(payload);
    final rows = <List<dynamic>>[
      <dynamic>['report_kind', run['report_kind']?.toString() ?? ''],
      <dynamic>['generated_at', run['generated_at']?.toString() ?? ''],
      <dynamic>[],
      <dynamic>['field', 'value'],
      ...flat.entries.map((entry) => <dynamic>[entry.key, entry.value]),
    ];
    final csv = _rowsToCsv(rows);
    final bytes = Uint8List.fromList(utf8.encode('\uFEFF$csv'));
    final filename = '${_fileBase(run)}.csv';

    await Share.shareXFiles(
      <XFile>[
        XFile.fromData(
          bytes,
          mimeType: 'text/csv',
        ),
      ],
      fileNameOverrides: <String>[filename],
      subject: reportKindLabel(run['report_kind']?.toString() ?? ''),
    );
  }

  static Future<void> sharePdf(Map<String, dynamic> run) async {
    final payloadRaw = run['payload'];
    final payload = payloadRaw is Map
        ? Map<String, dynamic>.from(payloadRaw)
        : <String, dynamic>{};
    final flat = _flatten(payload);
    final fontData = await rootBundle.load('assets/fonts/NotoKufiArabic.ttf');
    final boldData =
        await rootBundle.load('assets/fonts/NotoKufiArabic-Bold.ttf');
    final font = pw.Font.ttf(fontData);
    final bold = pw.Font.ttf(boldData);
    final kind = run['report_kind']?.toString() ?? 'report';
    final generatedAt = run['generated_at']?.toString() ?? '';
    final document = pw.Document();

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: bold),
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => <pw.Widget>[
          pw.Text(
            KurdishReshaper.convert(reportKindLabel(kind)),
            style: pw.TextStyle(
              font: bold,
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            KurdishReshaper.convert('ZHIROX • ڕاپۆرتی خۆکار'),
            style: const pw.TextStyle(
              fontSize: 11,
              color: PdfColors.grey700,
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            generatedAt,
            textDirection: pw.TextDirection.ltr,
            style: const pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey600,
            ),
          ),
          pw.SizedBox(height: 18),
          pw.TableHelper.fromTextArray(
            headers: <String>[
              KurdishReshaper.convert('خانە'),
              KurdishReshaper.convert('نرخ'),
            ],
            data: flat.entries
                .map(
                  (entry) => <String>[
                    KurdishReshaper.convert(entry.key),
                    KurdishReshaper.convert(entry.value),
                  ],
                )
                .toList(growable: false),
            headerStyle: pw.TextStyle(
              font: bold,
              fontWeight: pw.FontWeight.bold,
              fontSize: 10,
            ),
            cellStyle: pw.TextStyle(font: font, fontSize: 9),
            cellAlignment: pw.Alignment.centerRight,
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.grey200),
          ),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await document.save(),
      filename: '${_fileBase(run)}.pdf',
    );
  }
}
