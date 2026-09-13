import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:zhirox/services/pb_service.dart';

class LegacyImportBundle {
  const LegacyImportBundle({
    required this.fileName,
    required this.fingerprint,
    required this.marketName,
    required this.customers,
    required this.debts,
    required this.payments,
    required this.expectedBalanceIqd,
  });

  final String fileName;
  final String fingerprint;
  final String marketName;
  final List<Map<String, dynamic>> customers;
  final List<Map<String, dynamic>> debts;
  final List<Map<String, dynamic>> payments;
  final double expectedBalanceIqd;
}

class LegacyImportService {
  static Future<Map<String, dynamic>> preflight() => _invoke('preflight');

  static Future<LegacyImportBundle?> pickBundle() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    var bytes = file.bytes ?? Uint8List(0);

    // On iOS/iCloud/Safari downloads, file_picker can return a valid picked
    // file while `bytes` is null. XFile reads from the provider-backed
    // temporary URL/path and is the reliable fallback on those sources.
    if (bytes.isEmpty) {
      try {
        bytes = await file.xFile.readAsBytes();
      } catch (_) {
        // Keep the localized error below if the provider cannot be read.
      }
    }

    if (bytes.isEmpty) {
      throw Exception('نەتوانرا ناوەڕۆکی فایلە ZIP ـەکە بخوێندرێتەوە');
    }
    return parseBundle(bytes, file.name);
  }

  static LegacyImportBundle parseBundle(Uint8List bytes, String fileName) {
    if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4b) {
      throw Exception('فایلە هەڵبژێردراوەکە ZIP ـی دروست نییە');
    }

    final fingerprint = sha256.convert(bytes).toString();
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: true);
    } catch (error) {
      throw Exception('ZIP ـەکە زیان‌پێگەیشتووە یان ناتوانرێت بکرێتەوە: $error');
    }

    if (archive.isEmpty) {
      throw Exception('ZIP ـەکە بەتاڵە');
    }

    final files = <String, Uint8List>{};
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final normalized = entry.name.replaceAll('\\', '/');
      final data = entry.readBytes();
      if (data == null) {
        throw Exception('نەتوانرا فایلێکی ناو ZIP بخوێندرێتەوە: $normalized');
      }
      files[normalized] = data;
    }

    Uint8List requireBySuffix(String suffix) {
      for (final entry in files.entries) {
        if (entry.key.endsWith(suffix)) return entry.value;
      }
      throw Exception('فایلێکی پێویست لە ZIP ـەکە نییە: $suffix');
    }

    final customers = _csv(requireBySuffix('data/01_customers_zhirox.csv'));
    final debtsRaw = _csv(requireBySuffix('data/02_debts_zhirox.csv'));
    final paymentsRaw = _csv(requireBySuffix('data/03_payments_zhirox.csv'));

    final debtIdToLegacy = <String, String>{};
    final debts = debtsRaw.map((row) {
      final legacyId = '${row['legacy_transaction_id'] ?? row['source_id'] ?? ''}'.trim();
      final packageDebtId = '${row['debt_id'] ?? ''}'.trim();
      if (legacyId.isEmpty) throw Exception('Debt source ID بەتاڵە');
      if (packageDebtId.isNotEmpty) debtIdToLegacy[packageDebtId] = legacyId;
      return <String, dynamic>{
        'source_id': legacyId,
        'customer_source_id': '${row['legacy_customer_id'] ?? ''}'.trim(),
        'description': '${row['description'] ?? ''}',
        'amount': _number(row['amount']),
        'currency': '${row['currency'] ?? 'IQD'}',
        'occurred_at': '${row['custom_date'] ?? row['created_at'] ?? ''}',
      };
    }).toList(growable: false);

    final normalizedCustomers = customers.map((row) => <String, dynamic>{
      'source_id': '${row['legacy_customer_id'] ?? row['source_id'] ?? ''}'.trim(),
      'name': '${row['name'] ?? ''}'.trim(),
      'phone': '${row['source_phone'] ?? row['phone'] ?? ''}'.trim(),
      'debt_limit': _number(row['debt_limit'] ?? 0),
      'debt_duration': int.tryParse('${row['debt_duration'] ?? 30}') ?? 30,
    }).toList(growable: false);

    final payments = paymentsRaw.map((row) {
      final packageDebtId = '${row['debt_id'] ?? ''}'.trim();
      final debtSource = debtIdToLegacy[packageDebtId] ??
          '${row['debt_source_id'] ?? row['legacy_debt_transaction_id'] ?? ''}'.trim();
      if (debtSource.isEmpty) {
        throw Exception('Payment ـێک debt mapping ـی نییە');
      }
      final tx = '${row['legacy_transaction_id'] ?? row['source_id'] ?? ''}'.trim();
      final part = '${row['allocation_part'] ?? '1'}'.trim();
      return <String, dynamic>{
        'source_id': '$tx:$part',
        'debt_source_id': debtSource,
        'amount': _number(row['amount']),
        'note': '${row['note'] ?? ''}',
        'occurred_at': '${row['created_at'] ?? row['occurred_at'] ?? ''}',
      };
    }).toList(growable: false);

    String marketName = '';
    double expectedBalance = 0;
    for (final entry in files.entries) {
      if (entry.key.endsWith('meta/migration_summary.csv')) {
        final rows = _csv(entry.value);
        if (rows.isNotEmpty) {
          marketName = '${rows.first['target_market'] ?? ''}'.trim();
          expectedBalance = _number(rows.first['expected_final_balance_iqd']);
        }
      }
      if (entry.key.endsWith('meta/validation_report.json')) {
        try {
          final report = jsonDecode(utf8.decode(entry.value));
          if (report is Map) {
            marketName = marketName.isEmpty ? '${report['target_market'] ?? ''}'.trim() : marketName;
            if (expectedBalance == 0) expectedBalance = _number(report['expected_balance_iqd']);
          }
        } catch (_) {}
      }
    }

    if (normalizedCustomers.any((e) => '${e['source_id']}'.isEmpty || '${e['name']}'.isEmpty)) {
      throw Exception('هەندێک کڕیار source ID یان ناویان نییە');
    }
    if (debts.any((e) => '${e['customer_source_id']}'.isEmpty || (e['amount'] as double) <= 0)) {
      throw Exception('هەندێک قەرز mapping یان بڕی دروستیان نییە');
    }
    if (payments.any((e) => (e['amount'] as double) <= 0)) {
      throw Exception('هەندێک پارەدان بڕی دروستیان نییە');
    }

    return LegacyImportBundle(
      fileName: fileName,
      fingerprint: fingerprint,
      marketName: marketName,
      customers: normalizedCustomers,
      debts: debts,
      payments: payments,
      expectedBalanceIqd: expectedBalance,
    );
  }

  static Future<Map<String, dynamic>> start(LegacyImportBundle bundle) => _invoke(
        'start',
        extra: {
          'source_fingerprint': bundle.fingerprint,
          'source_name': bundle.fileName,
          'source_market_name': bundle.marketName,
          'expected_customers': bundle.customers.length,
          'expected_debts': bundle.debts.length,
          'expected_payments': bundle.payments.length,
          'expected_balance_iqd': bundle.expectedBalanceIqd,
        },
      );

  static Future<void> importBundle(
    LegacyImportBundle bundle, {
    required void Function(int done, int total, String phase) onProgress,
  }) async {
    await start(bundle);
    final total = bundle.customers.length + bundle.debts.length + bundle.payments.length;
    var done = 0;

    Future<void> sendBatches(String action, List<Map<String, dynamic>> rows, int size, String phase) async {
      for (var i = 0; i < rows.length; i += size) {
        final end = (i + size < rows.length) ? i + size : rows.length;
        await _invoke(action, extra: {
          'source_fingerprint': bundle.fingerprint,
          'rows': rows.sublist(i, end),
        });
        done += end - i;
        onProgress(done, total, phase);
      }
    }

    await sendBatches('customers', bundle.customers, 80, 'کڕیارەکان');
    await sendBatches('debts', bundle.debts, 100, 'قەرزەکان');
    await sendBatches('payments', bundle.payments, 100, 'پارەدانەوەکان');
    await _invoke('finalize', extra: {'source_fingerprint': bundle.fingerprint});
    onProgress(total, total, 'تەواو');
  }

  static Future<Map<String, dynamic>> _invoke(
    String action, {
    Map<String, dynamic> extra = const {},
  }) async {
    await PBService.ensureInitialized();
    final response = await PBService.client.functions.invoke(
      'legacy-import',
      body: {'action': action, ...extra},
    );
    if (response.data is! Map) throw Exception('وەڵامی backend نادروستە');
    final map = Map<String, dynamic>.from(response.data as Map);
    if (map['error'] != null) throw Exception('${map['error']}');
    return map;
  }

  static List<Map<String, dynamic>> _csv(Uint8List bytes) {
    final text = utf8.decode(bytes, allowMalformed: false).replaceFirst('\ufeff', '');
    final rows = const CsvToListConverter(shouldParseNumbers: false).convert(text);
    if (rows.isEmpty) return const [];
    final headers = rows.first.map((e) => '$e'.trim()).toList();
    return rows.skip(1).where((row) => row.any((e) => '$e'.trim().isNotEmpty)).map((row) {
      final map = <String, dynamic>{};
      for (var i = 0; i < headers.length; i++) {
        map[headers[i]] = i < row.length ? row[i] : '';
      }
      return map;
    }).toList(growable: false);
  }

  static double _number(Object? value) {
    final n = double.tryParse('${value ?? ''}'.replaceAll(',', '').trim()) ?? 0;
    if (!n.isFinite) return 0;
    return n;
  }
}
