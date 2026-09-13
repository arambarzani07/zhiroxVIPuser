import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zhirox/services/pb_service.dart';

typedef LegacyImportProgress = void Function(
  String stage,
  int current,
  int total,
);

class LegacyImportPackage {
  final String fileName;
  final String targetProjectRef;
  final String targetMarket;
  final String targetAdminId;
  final double expectedBalanceIqd;
  final double expectedBalanceUsd;
  final List<Map<String, String>> customers;
  final List<Map<String, String>> debts;
  final List<Map<String, String>> payments;

  const LegacyImportPackage({
    required this.fileName,
    required this.targetProjectRef,
    required this.targetMarket,
    required this.targetAdminId,
    required this.expectedBalanceIqd,
    required this.expectedBalanceUsd,
    required this.customers,
    required this.debts,
    required this.payments,
  });

  int get customerCount => customers.length;
  int get debtCount => debts.length;
  int get paymentCount => payments.length;
}

class LegacyImportResult {
  final int customersCreated;
  final int customersReused;
  final int debtsInserted;
  final int debtsReused;
  final int paymentsInserted;
  final int paymentsReused;
  final double importedBalanceIqd;
  final double importedBalanceUsd;

  const LegacyImportResult({
    required this.customersCreated,
    required this.customersReused,
    required this.debtsInserted,
    required this.debtsReused,
    required this.paymentsInserted,
    required this.paymentsReused,
    required this.importedBalanceIqd,
    required this.importedBalanceUsd,
  });
}

class LegacyImportService {
  static const String supportedProjectRef = 'hsoyfbtpvwfmjokudznx';
  static const String supportedMarket = 'سوپەرمارکێتی کانی چنار';
  static const String markerPrefix = '[#ZHIROX_LEGACY:';

  static LegacyImportPackage parseZip({
    required String fileName,
    required Uint8List bytes,
  }) {
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);

    String readRequired(String suffix) {
      ArchiveFile? match;
      for (final file in archive) {
        if (file.isFile && file.name.replaceAll('\\', '/').endsWith(suffix)) {
          match = file;
          break;
        }
      }
      if (match == null) {
        throw FormatException('فایلی پێویست لە ZIP نەدۆزرایەوە: $suffix');
      }
      return utf8.decode(match.content, allowMalformed: false);
    }

    final summaryRows = _decodeCsv(
      readRequired('meta/migration_summary.csv'),
    );
    if (summaryRows.length != 1) {
      throw const FormatException('migration_summary.csv دروست نییە');
    }
    final summary = summaryRows.first;

    final customers = _decodeCsv(
      readRequired('data/01_customers_zhirox.csv'),
    );
    final debts = _decodeCsv(
      readRequired('data/02_debts_zhirox.csv'),
    );
    final payments = _decodeCsv(
      readRequired('data/03_payments_zhirox.csv'),
    );

    final targetProjectRef = summary['target_project_ref'] ?? '';
    final targetMarket = summary['target_market'] ?? '';
    final targetAdminId = summary['target_admin_id'] ?? '';
    final expectedBalanceIqd =
        double.tryParse(summary['expected_final_balance_iqd'] ?? '') ??
        double.nan;

    if (targetProjectRef != supportedProjectRef) {
      throw FormatException(
        'ئەم پاکەتە بۆ project ـی ترە: $targetProjectRef',
      );
    }
    if (targetMarket != supportedMarket) {
      throw FormatException('ناوی مارکێت ناگونجێت: $targetMarket');
    }
    if (targetAdminId.isEmpty) {
      throw const FormatException('target_admin_id بەتاڵە');
    }
    if (!expectedBalanceIqd.isFinite) {
      throw const FormatException('بالانسی چاوەڕوانکراو دروست نییە');
    }

    final declaredCustomers =
        int.tryParse(summary['customers'] ?? '') ?? customers.length;
    final declaredDebts =
        int.tryParse(summary['source_loans'] ?? '') ?? debts.length;
    final declaredPayments =
        int.tryParse(summary['zhirox_payment_rows_after_allocation'] ?? '') ??
        payments.length;

    if (customers.length != declaredCustomers ||
        debts.length != declaredDebts ||
        payments.length != declaredPayments) {
      throw const FormatException(
        'ژمارەی ڕیزەکانی پاکەت لەگەڵ migration summary ناگونجێت',
      );
    }

    _requireColumns(
      customers,
      const ['legacy_customer_id', 'name', 'zhirox_phone', 'auth_email'],
      'customers',
    );
    _requireColumns(
      debts,
      const [
        'debt_id',
        'legacy_customer_id',
        'customer_lookup_phone',
        'amount',
        'currency',
        'custom_date',
        'created_at',
      ],
      'debts',
    );
    _requireColumns(
      payments,
      const ['payment_id', 'debt_id', 'amount', 'created_at'],
      'payments',
    );

    return LegacyImportPackage(
      fileName: fileName,
      targetProjectRef: targetProjectRef,
      targetMarket: targetMarket,
      targetAdminId: targetAdminId,
      expectedBalanceIqd: expectedBalanceIqd,
      expectedBalanceUsd: 0,
      customers: customers,
      debts: debts,
      payments: payments,
    );
  }

  static List<Map<String, String>> _decodeCsv(String source) {
    var normalized = source;
    if (normalized.startsWith('\ufeff')) {
      normalized = normalized.substring(1);
    }
    final rows = csv.decode(normalized);
    if (rows.isEmpty) return <Map<String, String>>[];

    final headers = rows.first.map((e) => e.toString().trim()).toList();
    final result = <Map<String, String>>[];
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.every((e) => e.toString().trim().isEmpty)) continue;
      final map = <String, String>{};
      for (var c = 0; c < headers.length; c++) {
        map[headers[c]] = c < row.length ? row[c].toString() : '';
      }
      result.add(map);
    }
    return result;
  }

  static void _requireColumns(
    List<Map<String, String>> rows,
    List<String> columns,
    String label,
  ) {
    if (rows.isEmpty) {
      throw FormatException('$label بەتاڵە');
    }
    final first = rows.first;
    for (final column in columns) {
      if (!first.containsKey(column)) {
        throw FormatException('$label خانەی $column ـی نییە');
      }
    }
  }

  Future<void> preflight(LegacyImportPackage package) async {
    await PBService.ensureInitialized();
    final user = PBService.client.auth.currentUser;
    if (user == null) {
      throw Exception('پێویستە دووبارە بچیتە ژوورەوە');
    }
    if (user.id != package.targetAdminId) {
      throw Exception(
        'ئەم پاکەتە بۆ هەژماری ئەدمینی تر ئامادە کراوە',
      );
    }

    final profile = await PBService.client
        .from('profiles')
        .select('id,role,market_name,active,approved,subscription_end')
        .eq('id', user.id)
        .maybeSingle();

    if (profile == null ||
        profile['role'] != 'admin' ||
        profile['active'] != true ||
        profile['approved'] != true) {
      throw Exception('تەنها ئەدمینی چالاک دەتوانێت Import ئەنجام بدات');
    }
    if ((profile['market_name']?.toString() ?? '') != package.targetMarket) {
      throw Exception(
        'مارکێتی ئەم هەژمارە لەگەڵ پاکەتی Import ناگونجێت',
      );
    }

    final subscription = profile['subscription_end']?.toString();
    if (subscription != null && subscription.isNotEmpty) {
      final end = DateTime.tryParse(subscription);
      if (end != null && end.isBefore(DateTime.now())) {
        throw Exception('ماوەی بەشداربوونی ئەدمین تەواو بووە');
      }
    }
  }

  Future<LegacyImportResult> run({
    required LegacyImportPackage package,
    LegacyImportProgress? onProgress,
  }) async {
    await preflight(package);
    final adminId = package.targetAdminId;

    onProgress?.call('پشکنینی کڕیارەکان', 0, package.customerCount);
    var customersCreated = 0;
    var customersReused = 0;

    for (var start = 0; start < package.customers.length; start += 4) {
      final end = min(start + 4, package.customers.length);
      final chunk = package.customers.sublist(start, end);
      final results = await Future.wait(
        chunk.map((row) => _ensureCustomer(row, adminId)),
      );
      for (final created in results) {
        if (created) {
          customersCreated++;
        } else {
          customersReused++;
        }
      }
      onProgress?.call(
        'دروستکردنی کڕیارەکان',
        end,
        package.customerCount,
      );
    }

    final customerByPhone = await _loadCustomerMap(adminId);
    for (final customer in package.customers) {
      final phone = customer['zhirox_phone'] ?? '';
      if (!customerByPhone.containsKey(phone)) {
        throw Exception('کڕیار دوای Import نەدۆزرایەوە: $phone');
      }
    }

    onProgress?.call('گواستنەوەی قەرزەکان', 0, package.debtCount);
    var debtsInserted = 0;
    var debtsReused = 0;

    for (var start = 0; start < package.debts.length; start += 100) {
      final end = min(start + 100, package.debts.length);
      final chunk = package.debts.sublist(start, end);

      final ids = chunk.map((e) => e['debt_id'] ?? '').toList();
      final existing = await PBService.client
          .from('debts')
          .select('id')
          .inFilter('id', ids);
      final existingIds = <String>{
        for (final row in (existing as List))
          (row as Map<String, dynamic>)['id'].toString(),
      };

      final inserts = <Map<String, dynamic>>[];
      for (final row in chunk) {
        final debtId = row['debt_id'] ?? '';
        if (existingIds.contains(debtId)) {
          debtsReused++;
          continue;
        }

        final phone = row['customer_lookup_phone'] ?? '';
        final customerId = customerByPhone[phone];
        if (customerId == null) {
          throw Exception('کڕیاری قەرز نەدۆزرایەوە: $phone');
        }

        final amount = double.tryParse(row['amount'] ?? '');
        if (amount == null || amount <= 0) {
          throw Exception('بڕی قەرز دروست نییە: $debtId');
        }
        final currency = (row['currency'] ?? 'IQD').toUpperCase();
        if (currency != 'IQD' && currency != 'USD') {
          throw Exception('دراو دروست نییە: $currency');
        }
        final createdAt = row['created_at'] ?? '';
        if (DateTime.tryParse(createdAt) == null) {
          throw Exception('بەرواری قەرز دروست نییە: $debtId');
        }

        inserts.add({
          'id': debtId,
          'customer_id': customerId,
          'description': row['description'] ?? '',
          'amount': amount,
          'remaining': amount,
          'due_date': null,
          'status': 'pending',
          'created_by': adminId,
          'currency': currency,
          'dollar_rate': 0,
          'amount_usd': currency == 'USD' ? amount : 0,
          'items': <Map<String, dynamic>>[],
          'custom_date': (row['custom_date'] ?? '').isEmpty
              ? createdAt
              : row['custom_date'],
          'receipt_image_path': '',
          'created_at': createdAt,
          'updated_at': createdAt,
          'subtotal': amount,
          'discount_percent': 0,
          'discount_amount': 0,
        });
      }

      if (inserts.isNotEmpty) {
        await PBService.client.from('debts').upsert(
              inserts,
              onConflict: 'id',
              ignoreDuplicates: true,
            );
        debtsInserted += inserts.length;
      }

      onProgress?.call('گواستنەوەی قەرزەکان', end, package.debtCount);
    }

    final existingMarkers = await _loadImportedPaymentMarkers(package.debts);
    final sortedPayments = [...package.payments]
      ..sort((a, b) {
        final ad = DateTime.tryParse(a['created_at'] ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        final bd = DateTime.tryParse(b['created_at'] ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        final byDate = ad.compareTo(bd);
        if (byDate != 0) return byDate;
        final aTx = int.tryParse(a['legacy_transaction_id'] ?? '') ?? 0;
        final bTx = int.tryParse(b['legacy_transaction_id'] ?? '') ?? 0;
        if (aTx != bTx) return aTx.compareTo(bTx);
        final aPart = int.tryParse(a['allocation_part'] ?? '') ?? 0;
        final bPart = int.tryParse(b['allocation_part'] ?? '') ?? 0;
        return aPart.compareTo(bPart);
      });

    onProgress?.call('گواستنەوەی پارەدانەکان', 0, sortedPayments.length);
    var paymentsInserted = 0;
    var paymentsReused = 0;

    for (var start = 0; start < sortedPayments.length; start += 5) {
      final end = min(start + 5, sortedPayments.length);
      final chunk = sortedPayments.sublist(start, end);
      final results = await Future.wait(
        chunk.map((row) async {
          final paymentId = row['payment_id'] ?? '';
          if (existingMarkers.contains(paymentId)) {
            return false;
          }
          await _importPayment(row);
          existingMarkers.add(paymentId);
          return true;
        }),
      );
      for (final inserted in results) {
        if (inserted) {
          paymentsInserted++;
        } else {
          paymentsReused++;
        }
      }
      onProgress?.call(
        'گواستنەوەی پارەدانەکان',
        end,
        sortedPayments.length,
      );
    }

    onProgress?.call('پشتڕاستکردنەوەی کۆتایی', 0, package.debtCount);
    final verification = await _verifyImportedPackage(package, onProgress);

    if ((verification.balanceIqd - package.expectedBalanceIqd).abs() > 0.001 ||
        (verification.balanceUsd - package.expectedBalanceUsd).abs() > 0.001) {
      throw Exception(
        'بالانسی کۆتایی ناگونجێت: '
        '${verification.balanceIqd.toStringAsFixed(2)} IQD / '
        '${verification.balanceUsd.toStringAsFixed(2)} USD',
      );
    }
    if (verification.debtCount != package.debtCount) {
      throw Exception(
        'هەموو قەرزەکان پشتڕاست نەکرانەوە '
        '(${verification.debtCount}/${package.debtCount})',
      );
    }
    if (verification.paymentMarkerCount != package.paymentCount) {
      throw Exception(
        'هەموو پارەدانەکان پشتڕاست نەکرانەوە '
        '(${verification.paymentMarkerCount}/${package.paymentCount})',
      );
    }

    return LegacyImportResult(
      customersCreated: customersCreated,
      customersReused: customersReused,
      debtsInserted: debtsInserted,
      debtsReused: debtsReused,
      paymentsInserted: paymentsInserted,
      paymentsReused: paymentsReused,
      importedBalanceIqd: verification.balanceIqd,
      importedBalanceUsd: verification.balanceUsd,
    );
  }

  Future<bool> _ensureCustomer(
    Map<String, String> row,
    String adminId,
  ) async {
    final phone = (row['zhirox_phone'] ?? '').trim();
    final name = (row['name'] ?? '').trim();
    final email = (row['auth_email'] ?? '').trim();
    if (phone.isEmpty || name.isEmpty || email.isEmpty) {
      throw Exception('زانیاری کڕیار تەواو نییە');
    }

    final existing = await PBService.client
        .from('profiles')
        .select('id,role,admin_id')
        .eq('phone', phone)
        .maybeSingle();

    if (existing != null) {
      if (existing['role'] != 'customer' ||
          existing['admin_id']?.toString() != adminId) {
        throw Exception('ژمارە/ناسنامەی کڕیار لە tenant ـێکی تر هەیە: $phone');
      }
      return false;
    }

    final response = await PBService.client.functions.invoke(
      'account-admin',
      body: {
        'action': 'create_user',
        'role': 'customer',
        'name': name,
        'father_name': '',
        'grandfather_name': '',
        'phone': phone,
        'password': _randomPassword(),
        'admin_id': adminId,
        'debt_limit': 0,
      },
    );

    final data = response.data;
    if (data is Map && data['error'] != null) {
      final error = data['error'].toString();
      if (error == 'phone_exists') {
        final retry = await PBService.client
            .from('profiles')
            .select('id,role,admin_id')
            .eq('phone', phone)
            .maybeSingle();
        if (retry != null &&
            retry['role'] == 'customer' &&
            retry['admin_id']?.toString() == adminId) {
          return false;
        }
      }
      throw Exception('دروستکردنی کڕیار سەرکەوتوو نەبوو: $error');
    }
    return true;
  }

  String _randomPassword() {
    const alphabet =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
    final random = Random.secure();
    final body = List.generate(
      24,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
    return 'Imp9!$body';
  }

  Future<Map<String, String>> _loadCustomerMap(String adminId) async {
    final rows = await PBService.client
        .from('profiles')
        .select('id,phone')
        .eq('role', 'customer')
        .eq('admin_id', adminId);

    return {
      for (final dynamic row in rows as List)
        (row as Map<String, dynamic>)['phone'].toString():
            row['id'].toString(),
    };
  }

  Future<Set<String>> _loadImportedPaymentMarkers(
    List<Map<String, String>> debts,
  ) async {
    final debtIds = debts.map((e) => e['debt_id'] ?? '').toList();
    final result = <String>{};
    final regex = RegExp(
      r'\[#ZHIROX_LEGACY:([0-9a-fA-F-]{36})\]',
    );

    for (var start = 0; start < debtIds.length; start += 80) {
      final end = min(start + 80, debtIds.length);
      final rows = await PBService.client
          .from('payments')
          .select('note')
          .inFilter('debt_id', debtIds.sublist(start, end));
      for (final dynamic raw in rows as List) {
        final note = (raw as Map<String, dynamic>)['note']?.toString() ?? '';
        for (final match in regex.allMatches(note)) {
          final id = match.group(1);
          if (id != null) result.add(id);
        }
      }
    }
    return result;
  }

  Future<void> _importPayment(Map<String, String> row) async {
    final paymentId = row['payment_id'] ?? '';
    final debtId = row['debt_id'] ?? '';
    final amount = double.tryParse(row['amount'] ?? '');
    final createdAt = row['created_at'] ?? '';
    if (paymentId.isEmpty ||
        debtId.isEmpty ||
        amount == null ||
        amount <= 0 ||
        DateTime.tryParse(createdAt) == null) {
      throw Exception('ڕیزی پارەدان دروست نییە: $paymentId');
    }

    final sourceNote = (row['note'] ?? '').trim();
    final marker = '$markerPrefix$paymentId]';
    final note = sourceNote.isEmpty ? marker : '$sourceNote\n$marker';

    final response = await PBService.client.functions.invoke(
      'record-payment',
      body: {
        'debt_id': debtId,
        'amount': amount,
        'note': note,
        'import_created_at': createdAt,
      },
    );

    final data = response.data;
    if (data is Map && data['error'] != null) {
      throw Exception('پارەدان Import نەکرا: ${data['error']}');
    }

    if (data is Map && data['id'] != null) {
      // Compatibility fallback for older record-payment function versions:
      // if the server has not yet applied import_created_at, preserve the
      // historical timestamp with an admin-authorized row update.
      final id = data['id'].toString();
      final returnedCreatedAt = data['created_at']?.toString() ?? '';
      if (returnedCreatedAt != createdAt) {
        await PBService.client
            .from('payments')
            .update({'created_at': createdAt})
            .eq('id', id);
      }
    }
  }

  Future<_Verification> _verifyImportedPackage(
    LegacyImportPackage package,
    LegacyImportProgress? onProgress,
  ) async {
    final debtIds = package.debts.map((e) => e['debt_id'] ?? '').toList();
    var debtCount = 0;
    var balanceIqd = 0.0;
    var balanceUsd = 0.0;

    for (var start = 0; start < debtIds.length; start += 80) {
      final end = min(start + 80, debtIds.length);
      final rows = await PBService.client
          .from('debts')
          .select('id,remaining,currency')
          .inFilter('id', debtIds.sublist(start, end));
      for (final dynamic raw in rows as List) {
        final row = raw as Map<String, dynamic>;
        final remaining = (row['remaining'] as num?)?.toDouble() ??
            double.tryParse(row['remaining']?.toString() ?? '') ??
            0;
        final currency = (row['currency']?.toString() ?? 'IQD').toUpperCase();
        if (currency == 'USD') {
          balanceUsd += remaining;
        } else {
          balanceIqd += remaining;
        }
      }
      debtCount += (rows as List).length;
      onProgress?.call(
        'پشتڕاستکردنەوەی قەرزەکان',
        end,
        package.debtCount,
      );
    }

    final markers = await _loadImportedPaymentMarkers(package.debts);
    return _Verification(
      debtCount: debtCount,
      paymentMarkerCount: markers.length,
      balanceIqd: balanceIqd,
      balanceUsd: balanceUsd,
    );
  }
}

class _Verification {
  final int debtCount;
  final int paymentMarkerCount;
  final double balanceIqd;
  final double balanceUsd;

  const _Verification({
    required this.debtCount,
    required this.paymentMarkerCount,
    required this.balanceIqd,
    required this.balanceUsd,
  });
}
