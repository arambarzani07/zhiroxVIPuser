import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:zhirox/services/legacy_import_service.dart';
import 'package:zhirox/utils/constants.dart';

class LegacyImportScreen extends StatefulWidget {
  const LegacyImportScreen({super.key});

  @override
  State<LegacyImportScreen> createState() => _LegacyImportScreenState();
}

class _LegacyImportScreenState extends State<LegacyImportScreen> {
  final LegacyImportService _service = LegacyImportService();

  LegacyImportPackage? _package;
  LegacyImportResult? _result;
  bool _isReading = false;
  bool _isImporting = false;
  String _stage = '';
  int _current = 0;
  int _total = 0;
  String? _error;

  double get _progress {
    if (_total <= 0) return 0;
    return (_current / _total).clamp(0.0, 1.0).toDouble();
  }

  Future<void> _pickZip() async {
    if (_isImporting) return;
    setState(() {
      _isReading = true;
      _error = null;
      _result = null;
      _package = null;
    });

    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'پاکەتی Zhirox Import هەڵبژێرە',
        type: FileType.custom,
        allowedExtensions: const ['zip'],
      );
      if (file == null) {
        if (mounted) setState(() => _isReading = false);
        return;
      }

      final bytes = await file.readAsBytes();
      final parsed = LegacyImportService.parseZip(
        fileName: file.name,
        bytes: bytes,
      );
      await _service.preflight(parsed);

      if (!mounted) return;
      setState(() {
        _package = parsed;
        _isReading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isReading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _startImport() async {
    final package = _package;
    if (package == null || _isImporting) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 10),
            Expanded(child: Text('پشتڕاستکردنەوەی Import')),
          ],
        ),
        content: const Text(
          'ئەم کردارە داتای قەرزە کۆنەکان دەخاتە داتابەیسی ڕاستەقینە. '
          'Import ـەکە duplicate-safe ـە؛ ئەگەر لە ناوەڕاستدا بوەستێت '
          'دەتوانیت دووبارە دەستی پێ بکەیت و تۆمارە پێشووەکان دووبارە نابن.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('پاشگەزبوونەوە'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('دەستپێکردن'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isImporting = true;
      _error = null;
      _result = null;
      _stage = 'ئامادەکردن';
      _current = 0;
      _total = 1;
    });

    try {
      final result = await _service.run(
        package: package,
        onProgress: (stage, current, total) {
          if (!mounted) return;
          setState(() {
            _stage = stage;
            _current = current;
            _total = total;
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _result = result;
        _isImporting = false;
        _stage = 'تەواو بوو';
        _current = 1;
        _total = 1;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isImporting = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final package = _package;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor:
            isDark ? AppDarkColors.background : const Color(0xFFF5F7FA),
        appBar: AppBar(
          title: const Text('گواستنەوەی داتای کۆن'),
          centerTitle: true,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildInfoCard(isDark),
              const SizedBox(height: 14),
              _buildPickerCard(isDark),
              if (_error != null) ...[
                const SizedBox(height: 14),
                _buildErrorCard(isDark),
              ],
              if (package != null) ...[
                const SizedBox(height: 14),
                _buildPackageCard(package, isDark),
                const SizedBox(height: 14),
                _buildSafetyCard(isDark),
                const SizedBox(height: 14),
                if (_isImporting) _buildProgressCard(isDark),
                if (_result != null) _buildResultCard(_result!, isDark),
                if (!_isImporting && _result == null)
                  SizedBox(
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: _startImport,
                      icon: const Icon(Icons.cloud_upload_rounded),
                      label: const Text(
                        'Import بۆ سیستەم دەستپێبکە',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary,
            AppColors.primary.withOpacity(0.78),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.move_to_inbox_rounded, color: Colors.white, size: 28),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Zhirox Legacy Import Center',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Text(
            'پاکەتی تایبەتی سوپەرمارکێتی کانی چنار هەڵبژێرە. '
            'سیستەم پێش نووسین schema، tenant، ژمارەی تۆمارەکان و '
            'بالانسی چاوەڕوانکراو دەپشکنێت.',
            style: TextStyle(
              color: Colors.white,
              height: 1.7,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPickerCard(bool isDark) {
    return _card(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '١. پاکەتی Import',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            _package?.fileName ??
                'Kanichnar_ZhiroxVIPuser_Import_Ready_2026-09-13.zip',
            style: TextStyle(
              color: isDark
                  ? AppDarkColors.textSecondary
                  : Colors.grey.shade700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: (_isReading || _isImporting) ? null : _pickZip,
              icon: _isReading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.folder_zip_rounded),
              label: Text(
                _isReading ? 'پشکنین...' : 'ZIP هەڵبژێرە و پشکنینی بکە',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPackageCard(LegacyImportPackage package, bool isDark) {
    return _card(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.verified_rounded, color: Colors.green),
              SizedBox(width: 8),
              Text(
                'پاکەت پشتڕاستکرایەوە',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _detailRow('مارکێت', package.targetMarket),
          _detailRow('کڕیار', _formatInt(package.customerCount)),
          _detailRow('قەرز / LOAN', _formatInt(package.debtCount)),
          _detailRow('Payment row', _formatInt(package.paymentCount)),
          _detailRow(
            'بالانسی چاوەڕوانکراو',
            '${_formatMoney(package.expectedBalanceIqd)} IQD',
          ),
          _detailRow(
            'USD',
            package.expectedBalanceUsd.toStringAsFixed(2),
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyCard(bool isDark) {
    return _card(
      isDark: isDark,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_rounded, color: Colors.teal),
              SizedBox(width: 8),
              Text(
                'پاراستنی Import',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
              ),
            ],
          ),
          SizedBox(height: 10),
          Text(
            '• تەنها Admin ـی مارکێتی ئامانج دەتوانێت Import بکات.\n'
            '• Debt ID ـەکان deterministic ـن و دووبارە نابن.\n'
            '• Payment ـەکان legacy marker ـیان هەیە و rerun پارە دووبارە ناکات.\n'
            '• هیچ Service Role Key ـێک لە ناو ئەپدا نییە.\n'
            '• لە کۆتاییدا بالانسی imported debts بە فایلەکە بەراورد دەکرێت.',
            style: TextStyle(height: 1.8, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _card(
        isDark: isDark,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _stage,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: _progress,
              minHeight: 8,
              borderRadius: BorderRadius.circular(10),
            ),
            const SizedBox(height: 8),
            Text(
              '${_formatInt(_current)} / ${_formatInt(_total)}',
              textDirection: TextDirection.ltr,
              style: TextStyle(
                color: isDark
                    ? AppDarkColors.textSecondary
                    : Colors.grey.shade700,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'ئەگەر پەیوەندی پچڕا، دووبارە هەمان ZIP هەڵبژێرە و Import '
              'دەستپێبکە؛ تۆمارە تەواوبووەکان دووبارە نابن.',
              style: TextStyle(fontSize: 12, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(LegacyImportResult result, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(isDark ? 0.14 : 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.green.withOpacity(0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.green),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'IMPORT VERIFIED ✅',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _detailRow(
              'کڕیاری نوێ / پێشوو',
              '${result.customersCreated} / ${result.customersReused}',
            ),
            _detailRow(
              'قەرزی نوێ / پێشوو',
              '${result.debtsInserted} / ${result.debtsReused}',
            ),
            _detailRow(
              'Payment نوێ / پێشوو',
              '${result.paymentsInserted} / ${result.paymentsReused}',
            ),
            _detailRow(
              'بالانسی imported',
              '${_formatMoney(result.importedBalanceIqd)} IQD',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(isDark ? 0.15 : 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.red.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(height: 1.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required bool isDark, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.06)
              : Colors.black.withOpacity(0.05),
        ),
        boxShadow: isDark
            ? const []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: child,
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.left,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  String _formatInt(int value) {
    final text = value.toString();
    return text.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
  }

  String _formatMoney(double value) {
    final rounded = value.toStringAsFixed(0);
    return rounded.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
  }
}
