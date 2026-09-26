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

class _LegacyDebtAllocation {
  _LegacyDebtAllocation({
    required this.sourceId,
    required this.customerSourceId,
    required this.currency,
    required this.occurredAt,
    required this.remaining,
  });

  final String sourceId;
  final String customerSourceId;
  final String currency;
  final String occurredAt;
  double remaining;
}

class LegacyImportService {
  static Future<Map<String, dynamic>> preflight() => _invoke('preflight');

  static Future<LegacyImportBundle?> pickBundle() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'zip', 'json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.single;
    var bytes = file.bytes ?? Uint8List(0);

    // iOS/iCloud/Safari providers can return a valid selected file while the
    // in-memory bytes are null. XFile is the reliable provider-backed fallback.
    if (bytes.isEmpty) {
      try {
        bytes = await file.xFile.readAsBytes();
      } catch (_) {}
    }

    if (bytes.isEmpty) {
      throw Exception('نەتوانرا ناوەڕۆکی فایلەکە بخوێندرێتەوە');
    }

    final lowerName = file.name.toLowerCase();
    if (lowerName.endsWith('.csv')) {
      return parseCsvBundle(bytes, file.name);
    }
    if (lowerName.endsWith('.zip')) {
      return parseZipBundle(bytes, file.name);
    }
    if (lowerName.endsWith('.json')) {
      return parseJsonBundle(bytes, file.name);
    }

    // Defensive sniffing in case a provider strips the extension.
    if (_looksLikeZip(bytes)) return parseZipBundle(bytes, file.name);
    if (_looksLikeJson(bytes)) return parseJsonBundle(bytes, file.name);
    return parseCsvBundle(bytes, file.name);
  }

  static LegacyImportBundle parseZipBundle(Uint8List bytes, String fileName) {
    if (!_looksLikeZip(bytes)) {
      throw Exception('فایلە هەڵبژێردراوەکە ZIP ـی دروست نییە');
    }

    final fingerprint = sha256.convert(bytes).toString();
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: true);
    } catch (error) {
      throw Exception('ZIP ـەکە زیان‌پێگەیشتووە یان ناتوانرێت بکرێتەوە: $error');
    }
    if (archive.isEmpty) throw Exception('ZIP ـەکە بەتاڵە');

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

    final customersRaw = _csv(requireBySuffix('data/01_customers_zhirox.csv'));
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

    final customers = customersRaw.map((row) => <String, dynamic>{
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
      if (debtSource.isEmpty) throw Exception('Payment ـێک debt mapping ـی نییە');
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

    return _buildBundle(
      fileName: fileName,
      fingerprint: fingerprint,
      marketName: marketName,
      expectedBalanceIqd: expectedBalance,
      customers: customers,
      debts: debts,
      payments: payments,
    );
  }

  // Backward-compatible name used by existing tests/callers.
  static LegacyImportBundle parseBundle(Uint8List bytes, String fileName) =>
      parseZipBundle(bytes, fileName);

  /// Zhirox CSV Import v1: one UTF-8 CSV containing META, CUSTOMER, DEBT and
  /// PAYMENT rows. Backend semantics stay identical to ZIP imports.
  static LegacyImportBundle parseCsvBundle(Uint8List bytes, String fileName) {
    final fingerprint = sha256.convert(bytes).toString();
    final rows = _csv(bytes);
    if (rows.isEmpty) throw Exception('CSV ـەکە بەتاڵە');
    if (!rows.first.containsKey('record_type')) {
      throw Exception('CSV ـەکە ستوونی record_type ـی نییە');
    }

    final customers = <Map<String, dynamic>>[];
    final debts = <Map<String, dynamic>>[];
    final payments = <Map<String, dynamic>>[];
    var marketName = '';
    var expectedBalance = 0.0;

    for (final row in rows) {
      final type = '${row['record_type'] ?? ''}'.trim().toUpperCase();
      final rowMarket = '${row['market_name'] ?? ''}'.trim();
      if (marketName.isEmpty && rowMarket.isNotEmpty) marketName = rowMarket;
      if (expectedBalance == 0 && '${row['expected_balance_iqd'] ?? ''}'.trim().isNotEmpty) {
        expectedBalance = _number(row['expected_balance_iqd']);
      }

      switch (type) {
        case 'META':
          break;
        case 'CUSTOMER':
          customers.add({
            'source_id': '${row['source_id'] ?? row['legacy_customer_id'] ?? ''}'.trim(),
            'name': '${row['name'] ?? ''}'.trim(),
            'phone': '${row['phone'] ?? row['source_phone'] ?? ''}'.trim(),
            'debt_limit': _number(row['debt_limit'] ?? 0),
            'debt_duration': int.tryParse('${row['debt_duration'] ?? 30}') ?? 30,
          });
          break;
        case 'DEBT':
          debts.add({
            'source_id': '${row['source_id'] ?? row['legacy_transaction_id'] ?? ''}'.trim(),
            'customer_source_id':
                '${row['customer_source_id'] ?? row['legacy_customer_id'] ?? ''}'.trim(),
            'description': '${row['description'] ?? row['note'] ?? ''}',
            'amount': _number(row['amount']),
            'currency': '${row['currency'] ?? 'IQD'}'.trim().isEmpty
                ? 'IQD'
                : '${row['currency']}'.trim(),
            'occurred_at':
                '${row['occurred_at'] ?? row['custom_date'] ?? row['created_at'] ?? ''}'.trim(),
          });
          break;
        case 'PAYMENT':
          final legacyTx = '${row['legacy_transaction_id'] ?? ''}'.trim();
          final part = '${row['allocation_part'] ?? '1'}'.trim();
          var sourceId = '${row['source_id'] ?? ''}'.trim();
          if (sourceId.isEmpty && legacyTx.isNotEmpty) sourceId = '$legacyTx:$part';
          payments.add({
            'source_id': sourceId,
            'debt_source_id':
                '${row['debt_source_id'] ?? row['legacy_debt_transaction_id'] ?? ''}'.trim(),
            'amount': _number(row['amount']),
            'note': '${row['note'] ?? ''}',
            'occurred_at': '${row['occurred_at'] ?? row['created_at'] ?? ''}'.trim(),
          });
          break;
        case '':
          break;
        default:
          throw Exception('record_type ـی نەناسراو: $type');
      }
    }

    return _buildBundle(
      fileName: fileName,
      fingerprint: fingerprint,
      marketName: marketName,
      expectedBalanceIqd: expectedBalance,
      customers: customers,
      debts: debts,
      payments: payments,
    );
  }


  static LegacyImportBundle parseJsonBundle(
    Uint8List bytes,
    String fileName,
  ) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(
        utf8.decode(bytes, allowMalformed: false).replaceFirst('\ufeff', ''),
      );
    } catch (_) {
      throw Exception('invalid_json');
    }
    if (decoded is! Map) throw Exception('invalid_json_root');
    final root = _stringKeyedMap(decoded);
    final format = (root['format'] ?? '').toString().trim();
    if (format == 'zhirox_local_recovery_v1') {
      return parseLocalRecoveryJsonBundle(bytes, fileName);
    }
    if (format == 'daftar-qarz-authorized-api-export-v1') {
      return parseAuthorizedApiJsonBundle(bytes, fileName);
    }
    throw Exception('unsupported_json_format');
  }

  static LegacyImportBundle parseLocalRecoveryJsonBundle(
    Uint8List bytes,
    String fileName,
  ) {
    final fingerprint = sha256.convert(bytes).toString();
    final dynamic decoded;
    try {
      decoded = jsonDecode(
        utf8.decode(bytes, allowMalformed: false).replaceFirst('\ufeff', ''),
      );
    } catch (_) {
      throw Exception('invalid_recovery_json');
    }
    if (decoded is! Map) throw Exception('invalid_recovery_root');
    final root = _stringKeyedMap(decoded);
    if ((root['format'] ?? '').toString() != 'zhirox_local_recovery_v1') {
      throw Exception('invalid_recovery_format');
    }
    final cacheRaw = root['cache'];
    if (cacheRaw is! Map) throw Exception('recovery_cache_missing');
    final cache = _stringKeyedMap(cacheRaw);

    final customerRecords = <String, Map<String, dynamic>>{};
    final debtRecords = <String, Map<String, dynamic>>{};
    final paymentRecords = <String, Map<String, dynamic>>{};
    final paymentCustomerHints = <String, String>{};
    var adminDebtCacheAtLegacyLimit = false;

    Map<String, dynamic>? asMap(Object? value) =>
        value is Map ? _stringKeyedMap(value) : null;

    List<Map<String, dynamic>> asRows(Object? value) {
      if (value is List) {
        return value
            .whereType<Map>()
            .map((row) => _stringKeyedMap(row))
            .toList(growable: false);
      }
      final single = asMap(value);
      return single == null ? const [] : [single];
    }

    String recordId(Map<String, dynamic> row) =>
        (row['id'] ?? row['source_id'] ?? '').toString().trim();

    void addCustomer(
      Map<String, dynamic> row, {
      bool trustedCustomerKey = false,
    }) {
      final id = recordId(row);
      final role = (row['role'] ?? '').toString().trim().toLowerCase();
      if (id.isEmpty) return;
      if (role != 'customer' && !(trustedCustomerKey && role.isEmpty)) return;
      final name = (row['name'] ?? '').toString().trim();
      if (name.isEmpty) return;
      customerRecords[id] = row;
    }

    void addExpandedCustomer(Map<String, dynamic> row) {
      final expand = asMap(row['expand']);
      if (expand == null) return;
      final customer = asMap(expand['customer']);
      if (customer != null) {
        addCustomer(customer, trustedCustomerKey: true);
      }
    }

    for (final entry in cache.entries) {
      final key = entry.key;
      final rows = asRows(entry.value);
      if (key.startsWith('cached_users_customer_')) {
        for (final row in rows) {
          addCustomer(row, trustedCustomerKey: true);
        }
        continue;
      }
      if (key.startsWith('cached_profile_user_')) {
        for (final row in rows) {
          addCustomer(row, trustedCustomerKey: true);
        }
        continue;
      }
      if (key.startsWith('cached_debts_admin_')) {
        if (rows.length >= 100) adminDebtCacheAtLegacyLimit = true;
        for (final row in rows) {
          final id = recordId(row);
          if (id.isEmpty) continue;
          debtRecords[id] = row;
          addExpandedCustomer(row);
        }
        continue;
      }
      if (key.startsWith('cached_profile_debts_')) {
        for (final row in rows) {
          final id = recordId(row);
          if (id.isEmpty) continue;
          debtRecords[id] = row;
          addExpandedCustomer(row);
        }
        continue;
      }
      if (key.startsWith('cached_profile_payments_')) {
        final hintedCustomerId =
            key.substring('cached_profile_payments_'.length).trim();
        for (final row in rows) {
          final id = recordId(row);
          if (id.isEmpty) continue;
          paymentRecords[id] = row;
          if (hintedCustomerId.isNotEmpty) {
            paymentCustomerHints[id] = hintedCustomerId;
          }
          final expand = asMap(row['expand']);
          final debt = expand == null ? null : asMap(expand['debt']);
          if (debt != null) {
            final debtId = recordId(debt);
            if (debtId.isNotEmpty) {
              debtRecords.putIfAbsent(debtId, () => debt);
            }
            addExpandedCustomer(debt);
          }
        }
      }
    }

    final identity = asMap(root['identity']);
    final userData = identity == null ? null : asMap(identity['user_data']);
    var marketName = '';
    if (userData != null) {
      marketName = (userData['market_name'] ?? '').toString().trim();
    }

    if (customerRecords.isEmpty) {
      throw Exception('recovery_customers_missing');
    }
    if (debtRecords.isEmpty) {
      throw Exception('recovery_debts_missing');
    }
    if (adminDebtCacheAtLegacyLimit) {
      throw Exception('recovery_debt_cache_may_be_truncated');
    }

    final customers = <Map<String, dynamic>>[];
    for (final entry in customerRecords.entries) {
      final row = entry.value;
      customers.add({
        'source_id': entry.key,
        'name': (row['name'] ?? '').toString().trim(),
        'phone': (row['phone'] ?? '').toString().trim(),
        'father_name': (row['father_name'] ?? '').toString().trim(),
        'grandfather_name':
            (row['grandfather_name'] ?? '').toString().trim(),
        'debt_limit': _number(row['debt_limit'] ?? 0),
        'debt_duration':
            int.tryParse((row['debt_duration'] ?? 30).toString()) ?? 30,
      });
    }

    String validOccurredAt(Map<String, dynamic> row, String sourceId) {
      final value = (row['custom_date'] ??
              row['created_at'] ??
              row['created'] ??
              '')
          .toString()
          .trim();
      if (value.isEmpty || DateTime.tryParse(value) == null) {
        throw Exception('invalid_recovery_date:$sourceId');
      }
      return value;
    }

    final debts = <Map<String, dynamic>>[];
    final debtAmount = <String, double>{};
    final debtRemaining = <String, double>{};
    final debtCurrency = <String, String>{};

    for (final entry in debtRecords.entries) {
      final row = entry.value;
      final sourceId = entry.key;
      final customerSourceId =
          (row['customer_id'] ?? row['customer'] ?? '').toString().trim();
      if (customerSourceId.isEmpty ||
          !customerRecords.containsKey(customerSourceId)) {
        throw Exception('recovery_customer_missing_for_debt:$sourceId');
      }
      final amount = _money(row['amount']);
      if (amount <= 0) {
        throw Exception('invalid_recovery_debt_amount:$sourceId');
      }
      final remaining =
          row.containsKey('remaining') ? _money(row['remaining']) : amount;
      if (remaining < -0.009 || remaining > amount + 0.009) {
        throw Exception('invalid_recovery_remaining:$sourceId');
      }
      final rawCurrency =
          (row['currency'] ?? 'IQD').toString().trim().toUpperCase();
      final currency = rawCurrency.isEmpty ? 'IQD' : rawCurrency;
      debtAmount[sourceId] = amount;
      debtRemaining[sourceId] = remaining;
      debtCurrency[sourceId] = currency;
      debts.add({
        'source_id': sourceId,
        'customer_source_id': customerSourceId,
        'description': (row['description'] ?? '').toString(),
        'amount': amount,
        'currency': currency,
        'occurred_at': validOccurredAt(row, sourceId),
      });
    }

    final payments = <Map<String, dynamic>>[];
    final recoveredDebtPayments = <String, double>{};
    var generalPaidIqd = 0.0;

    for (final entry in paymentRecords.entries) {
      final row = entry.value;
      final sourceId = entry.key;
      final amount = _money(row['amount']);
      if (amount <= 0) {
        throw Exception('invalid_recovery_payment_amount:$sourceId');
      }
      final occurredAt = validOccurredAt(row, sourceId);
      final scope =
          (row['payment_scope'] ?? '').toString().trim().toLowerCase();
      final debtSourceId =
          (row['debt_id'] ?? row['debt'] ?? '').toString().trim();
      final isGeneral = scope == 'general' || debtSourceId.isEmpty;

      if (isGeneral) {
        final customerSourceId = (row['customer_id'] ??
                row['customer'] ??
                paymentCustomerHints[sourceId] ??
                '')
            .toString()
            .trim();
        if (customerSourceId.isEmpty ||
            !customerRecords.containsKey(customerSourceId)) {
          throw Exception('recovery_customer_missing_for_payment:$sourceId');
        }
        generalPaidIqd = _roundMoney(generalPaidIqd + amount);
        payments.add({
          'source_id': sourceId,
          'payment_scope': 'general',
          'customer_source_id': customerSourceId,
          'amount': amount,
          'note': (row['note'] ?? '').toString(),
          'occurred_at': occurredAt,
        });
        continue;
      }

      if (!debtRecords.containsKey(debtSourceId)) {
        throw Exception('recovery_debt_missing_for_payment:$sourceId');
      }
      recoveredDebtPayments[debtSourceId] = _roundMoney(
        (recoveredDebtPayments[debtSourceId] ?? 0) + amount,
      );
      payments.add({
        'source_id': sourceId,
        'payment_scope': 'debt',
        'debt_source_id': debtSourceId,
        'amount': amount,
        'note': (row['note'] ?? '').toString(),
        'occurred_at': occurredAt,
      });
    }

    for (final debtId in debtAmount.keys) {
      final expectedPaid = _roundMoney(
        (debtAmount[debtId] ?? 0) - (debtRemaining[debtId] ?? 0),
      );
      final recoveredPaid =
          _roundMoney(recoveredDebtPayments[debtId] ?? 0);
      if ((expectedPaid - recoveredPaid).abs() > 0.02) {
        throw Exception(
          'recovery_payment_history_incomplete:$debtId'
          ':expected=${expectedPaid.toStringAsFixed(2)}'
          ':found=${recoveredPaid.toStringAsFixed(2)}',
        );
      }
    }

    var expectedBalanceIqd = 0.0;
    for (final debtId in debtRemaining.keys) {
      if ((debtCurrency[debtId] ?? 'IQD') == 'IQD') {
        expectedBalanceIqd += debtRemaining[debtId] ?? 0;
      }
    }
    if (generalPaidIqd > expectedBalanceIqd + 0.02) {
      throw Exception('recovery_general_payment_exceeds_gross_balance');
    }
    expectedBalanceIqd = _roundMoney(
      (expectedBalanceIqd - generalPaidIqd)
          .clamp(0, double.infinity)
          .toDouble(),
    );

    return _buildBundle(
      fileName: fileName,
      fingerprint: fingerprint,
      marketName: marketName,
      expectedBalanceIqd: expectedBalanceIqd,
      customers: customers,
      debts: debts,
      payments: payments,
    );
  }

  /// Parses the read-only exporter created for an authorized Daftar Qarz
  /// account. Payments in the source are contact-level events, so they are
  /// deterministically allocated over that contact's debts by currency.
  static LegacyImportBundle parseAuthorizedApiJsonBundle(
    Uint8List bytes,
    String fileName,
  ) {
    final fingerprint = sha256.convert(bytes).toString();
    final String text;
    try {
      text = utf8.decode(bytes, allowMalformed: false).replaceFirst('\ufeff', '');
    } catch (_) {
      throw Exception('JSON ـەکە UTF-8 ـی دروست نییە');
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      throw Exception('JSON ـەکە دروست نییە');
    }
    if (decoded is! Map) throw Exception('ڕەگی JSON دەبێت object بێت');
    final root = _stringKeyedMap(decoded);
    if ('${root['format'] ?? ''}' != 'daftar-qarz-authorized-api-export-v1') {
      throw Exception('فۆرماتی JSON ـەکە پشتگیری ناکرێت');
    }

    final contacts = _authorizedExportRows(root['contacts'], 'contacts');
    final transactions = _authorizedExportRows(root['transactions'], 'transactions');
    var accountUserId = '${root['account_user_id'] ?? ''}'.trim();
    final observedUserIds = <String>{};
    for (final row in [...contacts, ...transactions]) {
      final userId = '${row['user_id'] ?? ''}'.trim();
      if (userId.isNotEmpty) observedUserIds.add(userId);
    }
    if (accountUserId.isEmpty && observedUserIds.length == 1) {
      accountUserId = observedUserIds.single;
    }
    if (observedUserIds.length > 1 ||
        (accountUserId.isNotEmpty && observedUserIds.any((id) => id != accountUserId))) {
      throw Exception('JSON ـەکە داتای زیاتر لە یەک هەژماری کۆنی تێدایە');
    }

    final customers = <Map<String, dynamic>>[];
    final customerIds = <String>{};
    for (final contact in contacts) {
      final sourceId = '${contact['id'] ?? ''}'.trim();
      final name = '${contact['name'] ?? ''}'.trim();
      if (sourceId.isEmpty || name.isEmpty) {
        throw Exception('کۆنتاکتێک ID یان ناوی دروستی نییە');
      }
      if (!customerIds.add(sourceId)) {
        throw Exception('کۆنتاکتی دووبارە لە JSON: $sourceId');
      }
      customers.add({
        'source_id': sourceId,
        'name': name,
        'phone': '${contact['phone'] ?? ''}'.trim(),
        'debt_limit': 0.0,
        'debt_duration': 30,
      });
    }

    final transactionIds = <String>{};
    final normalizedTransactions = <Map<String, dynamic>>[];
    for (final transaction in transactions) {
      final sourceId = '${transaction['id'] ?? ''}'.trim();
      final customerSourceId = '${transaction['contact_id'] ?? ''}'.trim();
      final type = '${transaction['transaction_type'] ?? ''}'.trim().toUpperCase();
      if (sourceId.isEmpty || customerSourceId.isEmpty) {
        throw Exception('مامەڵەیەک ID یان contact_id ـی نییە');
      }
      if (!transactionIds.add(sourceId)) {
        throw Exception('مامەڵەی دووبارە لە JSON: $sourceId');
      }
      if (!customerIds.contains(customerSourceId)) {
        throw Exception('کۆنتاکتی مامەڵە نەدۆزرایەوە: $customerSourceId');
      }
      if (type != 'LOAN' && type != 'PAYMENT') {
        throw Exception('transaction_type ـی نەناسراو: $type');
      }
      final transactionAmount = _money(transaction['amount']);
      if (transactionAmount <= 0) {
        throw Exception(
          'مامەڵەی بڕی سفر/نەرێنی دۆزرایەوە ($sourceId). '
          'بۆ ئەوەی هیچ مێژوویەک ون نەبێت Import وەستێنرا.',
        );
      }
      final occurredAt = _legacyOccurredAt(transaction, sourceId);
      final rawCurrency = '${transaction['currency'] ?? 'IQD'}'.trim().toUpperCase();
      normalizedTransactions.add({
        ...transaction,
        '_source_id': sourceId,
        '_customer_source_id': customerSourceId,
        '_type': type,
        '_amount': transactionAmount,
        '_currency': rawCurrency.isEmpty ? 'IQD' : rawCurrency,
        '_occurred_at': occurredAt,
      });
    }

    normalizedTransactions.sort((left, right) {
      final leftId = '${left['_source_id']}';
      final rightId = '${right['_source_id']}';
      final leftNumeric = int.tryParse(leftId);
      final rightNumeric = int.tryParse(rightId);
      if (leftNumeric != null && rightNumeric != null) {
        final byNumber = leftNumeric.compareTo(rightNumeric);
        if (byNumber != 0) return byNumber;
      }
      return leftId.compareTo(rightId);
    });

    final debts = <Map<String, dynamic>>[];
    final allocations = <_LegacyDebtAllocation>[];
    for (final transaction in normalizedTransactions.where((row) => row['_type'] == 'LOAN')) {
      final sourceId = '${transaction['_source_id']}';
      final customerSourceId = '${transaction['_customer_source_id']}';
      final currency = '${transaction['_currency']}';
      final occurredAt = '${transaction['_occurred_at']}';
      final transactionAmount = transaction['_amount'] as double;
      debts.add({
        'source_id': sourceId,
        'customer_source_id': customerSourceId,
        'description': '${transaction['note'] ?? ''}',
        'amount': transactionAmount,
        'currency': currency,
        'occurred_at': occurredAt,
      });
      allocations.add(_LegacyDebtAllocation(
        sourceId: sourceId,
        customerSourceId: customerSourceId,
        currency: currency,
        occurredAt: occurredAt,
        remaining: transactionAmount,
      ));
    }

    final payments = <Map<String, dynamic>>[];
    for (final transaction in normalizedTransactions.where((row) => row['_type'] == 'PAYMENT')) {
      final sourceId = '${transaction['_source_id']}';
      final customerSourceId = '${transaction['_customer_source_id']}';
      final currency = '${transaction['_currency']}';
      final occurredAt = '${transaction['_occurred_at']}';
      final transactionAmount = transaction['_amount'] as double;
      var remaining = transactionAmount;
      var part = 0;
      final candidates = allocations
          .where((debt) =>
              debt.customerSourceId == customerSourceId &&
              debt.currency == currency &&
              debt.remaining > 0)
          .toList()
        ..sort(_compareDebtAllocation);

      for (final debt in candidates) {
        if (remaining <= 0) break;
        final allocated = remaining < debt.remaining ? remaining : debt.remaining;
        if (allocated <= 0) continue;
        part += 1;
        final roundedAllocation = _roundMoney(allocated);
        payments.add({
          'source_id': '$sourceId:$part',
          'debt_source_id': debt.sourceId,
          'amount': roundedAllocation,
          'note': '${transaction['note'] ?? ''}',
          'occurred_at': occurredAt,
        });
        debt.remaining = _roundMoney(debt.remaining - roundedAllocation);
        remaining = _roundMoney(remaining - roundedAllocation);
      }
      if (remaining > 0.009) {
        throw Exception(
          'پارەدانەوەی $sourceId بە تەواوی بە قەرزەکان نەبەستراوە؛ '
          '${remaining.toStringAsFixed(2)} $currency ماوەتەوە. Import وەستێنرا.',
        );
      }
    }

    final expectedBalanceIqd = _roundMoney(
      allocations
          .where((debt) => debt.currency == 'IQD')
          .fold<double>(0, (sum, debt) => sum + debt.remaining),
    );
    final marketName = '${root['market_name'] ?? root['source_market_name'] ?? ''}'.trim();

    return _buildBundle(
      fileName: fileName,
      fingerprint: fingerprint,
      marketName: marketName,
      expectedBalanceIqd: expectedBalanceIqd,
      customers: customers,
      debts: debts,
      payments: payments,
    );
  }

  static List<Map<String, dynamic>> _authorizedExportRows(
    Object? rawSection,
    String sectionName,
  ) {
    if (rawSection is! Map) throw Exception('$sectionName section نییە');
    final section = _stringKeyedMap(rawSection);
    if (section['pagination_incomplete_or_unknown'] == true) {
      throw Exception('$sectionName ناتەواوە؛ هەموو پەڕەکان وەرنەگیراون');
    }
    final pages = section['pages'];
    if (pages is! List) throw Exception('$sectionName.pages لیست نییە');
    final declaredPageCount = int.tryParse('${section['page_count'] ?? ''}');
    if (declaredPageCount != null && declaredPageCount != pages.length) {
      throw Exception('$sectionName page_count لەگەڵ ژمارەی پەڕەکان یەک ناگرێتەوە');
    }

    final rows = <Map<String, dynamic>>[];
    for (var pageIndex = 0; pageIndex < pages.length; pageIndex++) {
      final page = pages[pageIndex];
      List<dynamic> pageRows;
      if (page is List) {
        pageRows = page;
      } else if (page is Map) {
        final pageMap = _stringKeyedMap(page);
        if (pageMap['success'] == false) {
          throw Exception('$sectionName page ${pageIndex + 1} سەرکەوتوو نییە');
        }
        final data = pageMap['data'];
        if (data is! List) {
          throw Exception('$sectionName page ${pageIndex + 1} data لیست نییە');
        }
        pageRows = data;
      } else {
        throw Exception('$sectionName page ${pageIndex + 1} فۆرماتی نادروستی هەیە');
      }
      for (final row in pageRows) {
        if (row is! Map) {
          throw Exception('$sectionName row فۆرماتی نادروستی هەیە');
        }
        rows.add(_stringKeyedMap(row));
      }
    }
    return rows;
  }

  static Map<String, dynamic> _stringKeyedMap(Map value) => {
        for (final entry in value.entries) '${entry.key}': entry.value,
      };

  static String _legacyOccurredAt(Map<String, dynamic> transaction, String sourceId) {
    final value = '${transaction['transaction_date'] ?? transaction['created_at'] ?? ''}'.trim();
    if (value.isEmpty || DateTime.tryParse(value) == null) {
      throw Exception('بەرواری مامەڵەی $sourceId دروست نییە');
    }
    return value;
  }

  static int _compareDebtAllocation(_LegacyDebtAllocation left, _LegacyDebtAllocation right) {
    final leftDate = DateTime.parse(left.occurredAt);
    final rightDate = DateTime.parse(right.occurredAt);
    final byDate = leftDate.compareTo(rightDate);
    if (byDate != 0) return byDate;
    final leftId = int.tryParse(left.sourceId);
    final rightId = int.tryParse(right.sourceId);
    if (leftId != null && rightId != null) return leftId.compareTo(rightId);
    return left.sourceId.compareTo(right.sourceId);
  }

  static LegacyImportBundle _buildBundle({
    required String fileName,
    required String fingerprint,
    required String marketName,
    required double expectedBalanceIqd,
    required List<Map<String, dynamic>> customers,
    required List<Map<String, dynamic>> debts,
    required List<Map<String, dynamic>> payments,
  }) {
    if (customers.isEmpty) throw Exception('CSV/ZIP/JSON هیچ کڕیارێکی تێدا نییە');
    if (debts.isEmpty) throw Exception('CSV/ZIP/JSON هیچ قەرزێکی تێدا نییە');
    if (customers.any((e) => '${e['source_id']}'.isEmpty || '${e['name']}'.isEmpty)) {
      throw Exception('هەندێک کڕیار source ID یان ناویان نییە');
    }
    if (debts.any((e) => '${e['source_id']}'.isEmpty ||
        '${e['customer_source_id']}'.isEmpty ||
        (e['amount'] as double) <= 0)) {
      throw Exception('هەندێک قەرز mapping یان بڕی دروستیان نییە');
    }
    if (payments.any((e) {
      final scope = (e['payment_scope'] ?? 'debt').toString().trim().toLowerCase();
      final mappingMissing = scope == 'general'
          ? (e['customer_source_id'] ?? '').toString().trim().isEmpty
          : (e['debt_source_id'] ?? '').toString().trim().isEmpty;
      return (e['source_id'] ?? '').toString().trim().isEmpty ||
          mappingMissing ||
          (e['amount'] as double) <= 0;
    })) {
      throw Exception('هەندێک پارەدان mapping یان بڕی دروستیان نییە');
    }

    return LegacyImportBundle(
      fileName: fileName,
      fingerprint: fingerprint,
      marketName: marketName,
      customers: List.unmodifiable(customers),
      debts: List.unmodifiable(debts),
      payments: List.unmodifiable(payments),
      expectedBalanceIqd: expectedBalanceIqd,
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

    Future<void> sendBatches(
      String action,
      List<Map<String, dynamic>> rows,
      int size,
      String phase,
    ) async {
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
    final text = utf8
        .decode(bytes, allowMalformed: false)
        .replaceFirst('\ufeff', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final rows = const CsvToListConverter(
      shouldParseNumbers: false,
      eol: '\n',
    ).convert(text);
    if (rows.isEmpty) return const [];
    final headers = rows.first.map((e) => '$e'.trim()).toList();
    return rows
        .skip(1)
        .where((row) => row.any((e) => '$e'.trim().isNotEmpty))
        .map((row) {
      final map = <String, dynamic>{};
      for (var i = 0; i < headers.length; i++) {
        map[headers[i]] = i < row.length ? row[i] : '';
      }
      return map;
    }).toList(growable: false);
  }

  static bool _looksLikeZip(Uint8List bytes) =>
      bytes.length >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4b;

  static bool _looksLikeJson(Uint8List bytes) {
    for (final byte in bytes) {
      if (byte == 0xef || byte == 0xbb || byte == 0xbf) continue;
      if (byte == 0x20 || byte == 0x09 || byte == 0x0a || byte == 0x0d) continue;
      return byte == 0x7b || byte == 0x5b;
    }
    return false;
  }

  static double _number(Object? value) {
    final n = double.tryParse('${value ?? ''}'.replaceAll(',', '').trim()) ?? 0;
    if (!n.isFinite) return 0;
    return n;
  }

  static double _money(Object? value) => _roundMoney(_number(value));

  static double _roundMoney(double value) => (value * 100).roundToDouble() / 100;
}
