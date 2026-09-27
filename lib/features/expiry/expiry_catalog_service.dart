import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:xml/xml.dart';
import 'package:zhirox/services/pb_service.dart';

class ExpiryImportPreview {
  const ExpiryImportPreview(this.headers, this.rows, this.filename);
  final List<String> headers;
  final List<List<String>> rows;
  final String filename;

  List<Map<String, String>> products({
    required int codeColumn,
    required int nameColumn,
    int? barcodeColumn,
    int? categoryColumn,
  }) {
    String field(List<String> row, int? index) =>
        index == null || index < 0 || index >= row.length
        ? ''
        : row[index].trim();

    if (codeColumn == nameColumn && rows.isNotEmpty) {
      throw const FormatException(
        'کۆدی کاڵا و ناوی کاڵا دەبێت دوو ستوونی جیا بن.',
      );
    }
    if (rows.length > 10000) {
      throw const FormatException('هەر فایلێک دەبێت ١٠٠٠٠ کاڵا یان کەمتر بێت.');
    }
    final seenCodes = <String>{};
    final seenBarcodes = <String, String>{};
    final result = <Map<String, String>>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final code = field(row, codeColumn);
      final name = field(row, nameColumn);
      final barcode = field(row, barcodeColumn);
      if (code.isEmpty || name.isEmpty) {
        throw FormatException('کۆد یان ناوی کاڵا لە ڕیزی ${i + 2} بەتاڵە.');
      }
      if (!seenCodes.add(code)) {
        throw FormatException('کۆدی کاڵا لە فایلەکەدا دووبارەیە: $code');
      }
      if (barcode.isNotEmpty &&
          seenBarcodes.putIfAbsent(barcode, () => code) != code) {
        throw FormatException(
          'بارکۆدی $barcode بۆ دوو کاڵای جیاواز بەکارهاتووە.',
        );
      }
      result.add({
        'external_code': code,
        'name': name,
        'barcode': barcode,
        'category': field(row, categoryColumn),
      });
    }
    if (result.isEmpty) {
      throw const FormatException('هیچ کاڵایەک لە فایلەکەدا نییە.');
    }
    return result;
  }
}

class ExpiryCatalogService {
  ExpiryCatalogService._();

  // XLSX is a ZIP of XML files. Read values only; never evaluate formulas,
  // macros, relationships to external resources, or any cashier stock field.
  static List<List<String>> _xlsx(Uint8List bytes) {
    final files = <String, List<int>>{};
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    for (final entry in archive) {
      if (!entry.isFile) continue;
      if (entry.name == 'xl/sharedStrings.xml' ||
          entry.name == 'xl/worksheets/sheet1.xml') {
        final content = entry.readBytes();
        if (content != null) files[entry.name] = content;
      }
    }
    final sheetBytes = files['xl/worksheets/sheet1.xml'];
    if (sheetBytes == null) {
      throw const FormatException('خشتەی یەکەمی XLSX نەدۆزرایەوە.');
    }
    final sharedBytes = files['xl/sharedStrings.xml'];
    final shared = sharedBytes == null
        ? <String>[]
        : XmlDocument.parse(utf8.decode(sharedBytes))
              .findAllElements('si')
              .map((e) => e.findAllElements('t').map((t) => t.innerText).join())
              .toList();
    final sheet = XmlDocument.parse(utf8.decode(sheetBytes));
    final lines = <List<String>>[];
    for (final row in sheet.findAllElements('row')) {
      final cells = <int, String>{};
      for (final cell in row.findElements('c')) {
        final ref = cell.getAttribute('r') ?? '';
        final letters = RegExp(r'^[A-Z]+').stringMatch(ref);
        if (letters == null) continue;
        var index = 0;
        for (final char in letters.codeUnits) {
          index = index * 26 + char - 64;
        }
        index -= 1;
        if (index >= 100) {
          throw const FormatException('ستونەکانی XLSX زۆر زۆرن.');
        }
        final type = cell.getAttribute('t');
        final raw = cell.findElements('v').firstOrNull?.innerText ?? '';
        String value;
        if (type == 's') {
          final position = int.tryParse(raw);
          if (position == null || position < 0 || position >= shared.length) {
            throw const FormatException('دەقی XLSX دروست نییە.');
          }
          value = shared[position];
        } else if (type == 'inlineStr') {
          value = cell.findAllElements('t').map((t) => t.innerText).join();
        } else {
          value = raw;
        }
        cells[index] = value.trim();
      }
      if (cells.isEmpty) continue;
      final width = cells.keys.reduce((a, b) => a > b ? a : b) + 1;
      lines.add(List.generate(width, (i) => cells[i] ?? ''));
    }
    return lines;
  }

  static ExpiryImportPreview parseFile(Uint8List bytes, String filename) {
    final List<List<String>> lines;
    if (filename.toLowerCase().endsWith('.xlsx')) {
      lines = _xlsx(bytes);
    } else if (filename.toLowerCase().endsWith('.csv')) {
      final data = utf8
          .decode(bytes)
          .replaceFirst('\ufeff', '')
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n');
      lines = const CsvToListConverter(shouldParseNumbers: false, eol: '\n')
          .convert(data)
          .map((row) => row.map((value) => '$value'.trim()).toList())
          .toList();
    } else {
      throw const FormatException('تەنها CSV و XLSX پشتگیری دەکرێن.');
    }
    if (lines.isEmpty) throw const FormatException('فایلەکە بەتاڵە.');
    final headers = lines.first;
    if (headers.length < 2) {
      throw const FormatException('کەمتر لە دوو ستوون لە فایلەکەدا هەیە.');
    }
    final rows = lines
        .skip(1)
        .where((r) => r.any((e) => e.isNotEmpty))
        .toList();
    return ExpiryImportPreview(headers, rows, filename);
  }

  static Future<ExpiryImportPreview?> pickFile() async {
    final chosen = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx'],
      withData: true,
    );
    if (chosen == null || chosen.files.isEmpty) return null;
    final file = chosen.files.single;
    Uint8List bytes = file.bytes ?? Uint8List(0);
    if (bytes.isEmpty) bytes = await file.xFile.readAsBytes();
    if (bytes.length > 8 * 1024 * 1024) {
      throw const FormatException('قەبارەی فایلەکە دەبێت لە ٨ MB کەمتر بێت.');
    }
    return parseFile(bytes, file.name);
  }

  static Future<List<Map<String, dynamic>>> products(String adminId) async {
    await PBService.ensureInitialized();
    final all = <Map<String, dynamic>>[];
    for (var start = 0; ; start += 500) {
      final result = await PBService.client
          .from('expiry_products')
          .select('id,external_code,barcode,name,category')
          .eq('admin_id', adminId)
          .order('name')
          .order('id')
          .range(start, start + 499);
      final page = List<Map<String, dynamic>>.from(result);
      all.addAll(page);
      if (page.length < 500) break;
    }
    return all;
  }

  static Future<List<Map<String, dynamic>>> arrivals(String adminId) async {
    await PBService.ensureInitialized();
    final all = <Map<String, dynamic>>[];
    for (var start = 0; ; start += 500) {
      final result = await PBService.client
          .from('expiry_arrivals')
          .select(
            'id,product_id,expiry_date,arrived_on,batch_code,notes,resolved_at,created_at',
          )
          .eq('admin_id', adminId)
          .order('expiry_date')
          .order('id')
          .range(start, start + 499);
      final page = List<Map<String, dynamic>>.from(result);
      all.addAll(page);
      if (page.length < 500) break;
    }
    return all;
  }

  static Future<Map<String, dynamic>> importProducts(
    List<Map<String, String>> rows,
  ) async {
    await PBService.ensureInitialized();
    final result = await PBService.client.rpc(
      'import_expiry_products',
      params: {'p_rows': rows},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  static Future<void> addArrival({
    required String adminId,
    required String actorId,
    required String productId,
    required DateTime expires,
    String batchCode = '',
  }) async {
    await PBService.ensureInitialized();
    await PBService.client.from('expiry_arrivals').insert({
      'admin_id': adminId,
      'product_id': productId,
      'created_by': actorId,
      'expiry_date':
          '${expires.year.toString().padLeft(4, '0')}-${expires.month.toString().padLeft(2, '0')}-${expires.day.toString().padLeft(2, '0')}',
      'batch_code': batchCode.trim(),
    });
  }

  static Future<void> resolve(String id) async {
    await PBService.ensureInitialized();
    await PBService.client
        .from('expiry_arrivals')
        .update({'resolved_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id);
  }
}
