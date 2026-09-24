import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:zhirox/utils/kurdish_reshaper.dart';

class CustomerPeriodStatementScreen extends StatefulWidget {
  final String customerId;
  final String customerName;
  final bool canExport;

  const CustomerPeriodStatementScreen({
    super.key,
    required this.customerId,
    required this.customerName,
    required this.canExport,
  });

  @override
  State<CustomerPeriodStatementScreen> createState() =>
      _CustomerPeriodStatementScreenState();
}

class _CustomerPeriodStatementScreenState
    extends State<CustomerPeriodStatementScreen> {
  DateTime _fromDate =
      DateTime(DateTime.now().year, 1, 1);
  DateTime _toDate = DateTime.now();
  Map<String, dynamic>? _statement;
  bool _loading = false;
  String? _error;
  String _query = '';
  String _sort = 'date_asc';

  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadStatement();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _isoDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  String _dateLabel(dynamic value) {
    final raw = value?.toString() ?? '';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw.isEmpty ? '—' : raw;
    return DateFormat('dd / MM / yyyy', 'en').format(parsed.toLocal());
  }

  double _num(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  String _money(dynamic value, dynamic currency) {
    final formatter = NumberFormat('#,##0.##', 'en');
    return '${formatter.format(_num(value))} ${currency?.toString().isNotEmpty == true ? currency : 'IQD'}';
  }

  List<Map<String, dynamic>> get _sourceRows {
    final raw = _statement?['rows'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  List<Map<String, dynamic>> get _visibleRows {
    final normalized = _query.trim().toLowerCase();
    final rows = _sourceRows.where((row) {
      if (normalized.isEmpty) return true;
      final searchable = [
        row['name'],
        row['amount'],
        row['currency'],
        row['date'],
      ].where((value) => value != null).join(' ').toLowerCase();
      return searchable.contains(normalized);
    }).toList();

    rows.sort((a, b) {
      switch (_sort) {
        case 'date_desc':
          return '${b['occurred_at'] ?? b['date'] ?? ''}'
              .compareTo('${a['occurred_at'] ?? a['date'] ?? ''}');
        case 'name_asc':
          return '${a['name'] ?? ''}'.compareTo('${b['name'] ?? ''}');
        case 'amount_desc':
          return _num(b['amount']).compareTo(_num(a['amount']));
        case 'amount_asc':
          return _num(a['amount']).compareTo(_num(b['amount']));
        case 'date_asc':
        default:
          return '${a['occurred_at'] ?? a['date'] ?? ''}'
              .compareTo('${b['occurred_at'] ?? b['date'] ?? ''}');
      }
    });
    return rows;
  }

  Map<String, double> _totalsFor(List<Map<String, dynamic>> rows) {
    final totals = <String, double>{};
    for (final row in rows) {
      final currency = (row['currency']?.toString().trim().isNotEmpty == true
              ? row['currency'].toString()
              : 'IQD')
          .toUpperCase();
      totals[currency] = (totals[currency] ?? 0) + _num(row['amount']);
    }
    return totals;
  }

  Future<void> _loadStatement() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await PBService.getCustomerPeriodStatement(
        customerId: widget.customerId,
        fromDate: _fromDate,
        toDate: _toDate,
      );
      if (!mounted) return;
      if (data['truncated'] == true) {
        setState(() {
          _statement = null;
          _error = 'ژمارەی بابەتەکان زۆرە؛ ماوەکە کورتتر بکە.';
        });
        return;
      }
      setState(() {
        _statement = data;
        _query = '';
        _sort = 'date_asc';
        _searchController.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statement = null;
        _error = AppHelpers.backendErrorMessage(
          e,
          fallback: 'نەتوانرا کەشفی حیساب وەربگیرێت. دووبارە هەوڵ بدە.',
        );
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate({required bool from}) async {
    final initial = from ? _fromDate : _toDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: from ? 'لە بەروار' : 'تا بەروار',
      cancelText: 'پاشگەزبوونەوە',
      confirmText: 'هەڵبژاردن',
    );
    if (!mounted || picked == null) return;
    setState(() {
      if (from) {
        _fromDate = DateTime(picked.year, picked.month, picked.day);
        if (_fromDate.isAfter(_toDate)) _toDate = _fromDate;
      } else {
        _toDate = DateTime(picked.year, picked.month, picked.day);
        if (_toDate.isBefore(_fromDate)) _fromDate = _toDate;
      }
    });
  }

  void _applyPreset(String preset) {
    final now = DateTime.now();
    setState(() {
      _toDate = DateTime(now.year, now.month, now.day);
      switch (preset) {
        case '7d':
          _fromDate = _toDate.subtract(const Duration(days: 6));
          break;
        case '30d':
          _fromDate = _toDate.subtract(const Duration(days: 29));
          break;
        case 'month':
          _fromDate = DateTime(now.year, now.month, 1);
          break;
        case 'year':
          _fromDate = DateTime(now.year, 1, 1);
          break;
        case 'all':
          _fromDate = DateTime(2000, 1, 1);
          break;
      }
    });
  }

  Future<void> _exportCsv() async {
    if (!widget.canExport) return;
    final rows = _visibleRows;
    if (rows.isEmpty) {
      AppHelpers.showSnackBar(context, 'هیچ بابەتێک بۆ CSV نییە.', isError: true);
      return;
    }

    String cell(Object? value) =>
        '"${(value ?? '').toString().replaceAll('"', '""')}"';

    final lines = <String>[
      ['ژمارەی ڕیز', 'ناوی بابەت', 'نرخ', 'دراو', 'بەروار']
          .map(cell)
          .join(','),
      for (var i = 0; i < rows.length; i++)
        [
          i + 1,
          rows[i]['name'] ?? 'بابەت',
          _num(rows[i]['amount']),
          rows[i]['currency'] ?? 'IQD',
          rows[i]['date'] ?? '',
        ].map(cell).join(','),
    ];

    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/${_safeFileName(_statement?['market_name'])}-'
      '${_safeFileName(_statement?['customer_name'] ?? widget.customerName)}-'
      'statement-${_isoDate(_fromDate).replaceAll('-', '')}-'
      '${_isoDate(_toDate).replaceAll('-', '')}.csv',
    );
    await file.writeAsString('\uFEFF${lines.join('\r\n')}', flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: 'کەشفی حیساب',
    );
  }

  String _safeFileName(dynamic value) {
    final text = value?.toString().trim() ?? '';
    final cleaned = text.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '-');
    return cleaned.isEmpty ? 'ZHIROX' : cleaned;
  }

  Future<void> _exportPdf() async {
    if (!widget.canExport) return;
    final data = _statement;
    final rows = _visibleRows;
    if (data == null || rows.isEmpty) {
      AppHelpers.showSnackBar(context, 'هیچ بابەتێک بۆ PDF نییە.', isError: true);
      return;
    }

    final regularData = await rootBundle.load('assets/fonts/NotoKufiArabic.ttf');
    final boldData =
        await rootBundle.load('assets/fonts/NotoKufiArabic-Bold.ttf');
    final regular = pw.Font.ttf(regularData);
    final bold = pw.Font.ttf(boldData);
    String k(String value) => KurdishReshaper.convert(value);

    final totals = _totalsFor(rows);
    final marketName = data['market_name']?.toString() ?? 'ZHIROX';
    final marketPhone = data['market_phone']?.toString() ?? '';
    final marketAddress = data['market_address']?.toString() ?? '';
    final customerName =
        data['customer_name']?.toString() ?? widget.customerName;
    final footerNote = data['footer_note']?.toString() ?? '';

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 30, 28, 30),
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        textDirection: pw.TextDirection.rtl,
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        k('پسووڵەی ماوە'),
                        style: pw.TextStyle(
                          font: bold,
                          fontSize: 10,
                          color: PdfColors.blue700,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        k(marketName),
                        style: pw.TextStyle(font: bold, fontSize: 19),
                      ),
                      if (marketPhone.isNotEmpty || marketAddress.isNotEmpty)
                        pw.Text(
                          k([marketPhone, marketAddress]
                              .where((e) => e.isNotEmpty)
                              .join(' • ')),
                          style: const pw.TextStyle(
                            fontSize: 8,
                            color: PdfColors.grey600,
                          ),
                        ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 16),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    _pdfMeta(k('کڕیار'), k(customerName), regular, bold),
                    _pdfMeta(
                      k('ماوە'),
                      '${_dateLabel(_fromDate)} — ${_dateLabel(_toDate)}',
                      regular,
                      bold,
                    ),
                    _pdfMeta(
                      k('ژمارەی بابەت'),
                      rows.length.toString(),
                      regular,
                      bold,
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Divider(color: PdfColors.grey300),
            pw.SizedBox(height: 6),
          ],
        ),
        footer: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                footerNote.isEmpty ? '' : k(footerNote),
                style: const pw.TextStyle(
                  fontSize: 7,
                  color: PdfColors.grey500,
                ),
              ),
              pw.Text(
                '${context.pageNumber} / ${context.pagesCount}',
                style: const pw.TextStyle(
                  fontSize: 7,
                  color: PdfColors.grey500,
                ),
              ),
            ],
          ),
        ),
        build: (_) => [
          pw.TableHelper.fromTextArray(
            headers: [
              k('ژمارەی ڕیز'),
              k('ناوی بابەت'),
              k('نرخ'),
              k('بەروار'),
            ],
            data: [
              for (var i = 0; i < rows.length; i++)
                [
                  (i + 1).toString(),
                  k(rows[i]['name']?.toString() ?? 'بابەت'),
                  _money(rows[i]['amount'], rows[i]['currency']),
                  _dateLabel(rows[i]['date']),
                ],
            ],
            headerStyle: pw.TextStyle(
              font: bold,
              fontSize: 8,
              color: PdfColors.grey800,
            ),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF3F5F9)),
            cellStyle: pw.TextStyle(font: regular, fontSize: 8),
            cellAlignment: pw.Alignment.centerRight,
            headerAlignment: pw.Alignment.centerRight,
            border: const pw.TableBorder(
              horizontalInside: pw.BorderSide(
                color: PdfColor.fromInt(0xFFE1E5EC),
                width: 0.5,
              ),
            ),
            oddRowDecoration:
                const pw.BoxDecoration(color: PdfColor.fromInt(0xFFFAFBFC)),
          ),
          pw.SizedBox(height: 12),
          for (final entry in totals.entries)
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 6),
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: pw.BoxDecoration(
                color: const PdfColor.fromInt(0xFFFAFBFC),
                border: pw.Border.all(
                  color: const PdfColor.fromInt(0xFFCCD4E2),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    k(totals.length > 1
                        ? 'کۆی گشتی — ${entry.key}'
                        : 'کۆی گشتی'),
                    style: pw.TextStyle(font: bold, fontSize: 9),
                  ),
                  pw.Text(
                    _money(entry.value, entry.key),
                    style: pw.TextStyle(font: bold, fontSize: 13),
                    textDirection: pw.TextDirection.ltr,
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    final bytes = await pdf.save();
    final filename =
        '${_safeFileName(marketName)}-${_safeFileName(customerName)}-'
        'statement-${_isoDate(_fromDate).replaceAll('-', '')}-'
        '${_isoDate(_toDate).replaceAll('-', '')}.pdf';

    await Printing.layoutPdf(
      name: filename,
      onLayout: (_) async => bytes,
    );
  }

  pw.Widget _pdfMeta(
    String label,
    String value,
    pw.Font regular,
    pw.Font bold,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              font: regular,
              fontSize: 7,
              color: PdfColors.grey600,
            ),
          ),
          pw.SizedBox(width: 5),
          pw.Text(value, style: pw.TextStyle(font: bold, fontSize: 8)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rows = _visibleRows;
    final totals = _totalsFor(rows);
    final days = rows
        .map((row) => row['date']?.toString() ?? '')
        .where((value) => value.isNotEmpty)
        .toSet()
        .length;
    final currencies = rows
        .map((row) => (row['currency']?.toString() ?? 'IQD').toUpperCase())
        .toSet()
        .length;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor:
            isDark ? AppDarkColors.background : AppColors.background,
        appBar: AppBar(
          title: const Text('کەشفی حیساب'),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'نوێکردنەوە',
              onPressed: _loading ? null : _loadStatement,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
            children: [
              _buildRangeCard(isDark),
              if (_loading) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(minHeight: 2),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                _buildErrorCard(isDark),
              ],
              if (_statement != null) ...[
                const SizedBox(height: 12),
                _buildSummaryRow(
                  itemCount: _sourceRows.length,
                  dayCount: days,
                  currencyCount: currencies,
                  isDark: isDark,
                ),
                const SizedBox(height: 10),
                _buildToolsCard(isDark),
                const SizedBox(height: 10),
                _buildTableHeader(isDark),
                if (rows.isEmpty)
                  _buildEmptyRows(isDark)
                else
                  for (var i = 0; i < rows.length; i++)
                    _buildTableRow(i, rows[i], isDark),
                const SizedBox(height: 10),
                Text(
                  '${rows.length} بابەت',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppDarkColors.textSecondary
                        : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                ...totals.entries.map(
                  (entry) => _buildTotalCard(
                    entry.key,
                    entry.value,
                    totals.length > 1,
                    isDark,
                  ),
                ),
                if (widget.canExport) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: rows.isEmpty ? null : _exportCsv,
                          icon: const Icon(Icons.table_view_outlined),
                          label: const Text('CSV'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: rows.isEmpty ? null : _exportPdf,
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('PDF / چاپ'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRangeCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppDarkColors.cardBorder : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'ماوەکە دیاری بکە',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'هەموو بابەتەکانی ئەو ماوەیە لە یەک کەشفدا کۆدەکرێنەوە.',
            style: TextStyle(
              fontSize: 10.5,
              color: isDark
                  ? AppDarkColors.textSecondary
                  : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _dateButton('لە بەروار', _fromDate, true)),
              const SizedBox(width: 8),
              Expanded(child: _dateButton('تا بەروار', _toDate, false)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _presetChip('٧ ڕۆژ', '7d'),
              _presetChip('٣٠ ڕۆژ', '30d'),
              _presetChip('ئەم مانگە', 'month'),
              _presetChip('ئەم ساڵە', 'year'),
              _presetChip('هەموو', 'all'),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _loading ? null : _loadStatement,
            icon: const Icon(Icons.receipt_long_rounded),
            label: const Text('دروستکردنی کەشف'),
          ),
        ],
      ),
    );
  }

  Widget _dateButton(String label, DateTime value, bool from) {
    return OutlinedButton(
      onPressed: () => _pickDate(from: from),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 9)),
          const SizedBox(height: 3),
          Text(
            DateFormat('dd / MM / yyyy', 'en').format(value),
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _presetChip(String label, String preset) {
    return ActionChip(
      label: Text(label),
      onPressed: () => _applyPreset(preset),
      labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
    );
  }

  Widget _buildSummaryRow({
    required int itemCount,
    required int dayCount,
    required int currencyCount,
    required bool isDark,
  }) {
    return Row(
      children: [
        Expanded(child: _summaryCard('ژمارەی بابەت', itemCount, isDark)),
        const SizedBox(width: 7),
        Expanded(child: _summaryCard('ژمارەی ڕۆژ', dayCount, isDark)),
        const SizedBox(width: 7),
        Expanded(child: _summaryCard('ژمارەی دراو', currencyCount, isDark)),
      ],
    );
  }

  Widget _summaryCard(String label, int value, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: isDark ? AppDarkColors.cardBorder : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 8.5,
              color: isDark
                  ? AppDarkColors.textSecondary
                  : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '$value',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Widget _buildToolsCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppDarkColors.cardBorder : AppColors.border,
        ),
      ),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'گەڕان بە ناوی بابەت...',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _sort,
            decoration: const InputDecoration(
              labelText: 'ڕیزکردن',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: 'date_asc',
                child: Text('بەروار: کۆن → نوێ'),
              ),
              DropdownMenuItem(
                value: 'date_desc',
                child: Text('بەروار: نوێ → کۆن'),
              ),
              DropdownMenuItem(value: 'name_asc', child: Text('ناوی بابەت')),
              DropdownMenuItem(
                value: 'amount_desc',
                child: Text('نرخ: زۆر → کەم'),
              ),
              DropdownMenuItem(
                value: 'amount_asc',
                child: Text('نرخ: کەم → زۆر'),
              ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _sort = value);
            },
          ),
          if (_query.isNotEmpty || _sort != 'date_asc') ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _query = '';
                    _sort = 'date_asc';
                    _searchController.clear();
                  });
                },
                icon: const Icon(Icons.restart_alt_rounded, size: 17),
                label: const Text('پاککردنەوەی فلتەر'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTableHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      color: isDark ? AppDarkColors.surface : const Color(0xFFF3F5F9),
      child: const Row(
        children: [
          SizedBox(
            width: 44,
            child: Text('#', textAlign: TextAlign.center),
          ),
          Expanded(
            flex: 5,
            child: Text('ناوی بابەت', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          Expanded(
            flex: 3,
            child: Text('نرخ', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          Expanded(
            flex: 3,
            child: Text('بەروار', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _buildTableRow(int index, Map<String, dynamic> row, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: index.isOdd
            ? (isDark
                ? Colors.white.withValues(alpha: 0.02)
                : const Color(0xFFFAFBFC))
            : (isDark ? AppDarkColors.card : Colors.white),
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppDarkColors.cardBorder : AppColors.border,
            width: 0.7,
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              '${index + 1}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10),
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(
              row['name']?.toString() ?? 'بابەت',
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              _money(row['amount'], row['currency']),
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              _dateLabel(row['date']),
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontSize: 9,
                color: isDark
                    ? AppDarkColors.textSecondary
                    : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyRows(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 30),
      color: isDark ? AppDarkColors.card : Colors.white,
      child: const Center(
        child: Text('هیچ بابەتێک لەم فلتەرەدا نەدۆزرایەوە'),
      ),
    );
  }

  Widget _buildTotalCard(
    String currency,
    double value,
    bool multiCurrency,
    bool isDark,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppDarkColors.cardBorder : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Text(
            multiCurrency ? 'کۆی گشتی — $currency' : 'کۆی گشتی',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          Text(
            _money(value, currency),
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: isDark ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.red),
          const SizedBox(width: 9),
          Expanded(child: Text(_error!)),
          TextButton(onPressed: _loadStatement, child: const Text('دووبارە')),
        ],
      ),
    );
  }
}
