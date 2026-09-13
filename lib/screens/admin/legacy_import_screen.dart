import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/services/legacy_import_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

class LegacyImportScreen extends StatefulWidget {
  const LegacyImportScreen({super.key});

  @override
  State<LegacyImportScreen> createState() => _LegacyImportScreenState();
}

class _LegacyImportScreenState extends State<LegacyImportScreen> {
  bool _checking = true;
  bool _allowed = false;
  bool _busy = false;
  String? _error;
  LegacyImportBundle? _bundle;
  int _done = 0;
  int _total = 0;
  String _phase = '';

  @override
  void initState() {
    super.initState();
    _runPreflight();
  }

  Future<void> _runPreflight() async {
    try {
      final result = await LegacyImportService.preflight();
      if (!mounted) return;
      setState(() {
        _allowed = result['can_import_data'] == true;
        _checking = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      setState(() {
        _checking = false;
        _allowed = false;
        _error = raw.contains('import_permission_required')
            ? 'مۆڵەتی Import بۆ ئەم هەژمارە کراوە نییە. پەیوەندی بە خاوەنی سیستەم بکە.'
            : 'نەتوانرا دەسەڵاتی Import بپشکنرێت.';
      });
    }
  }

  Future<void> _pick() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bundle = await LegacyImportService.pickBundle();
      if (!mounted) return;
      if (bundle != null) {
        final auth = context.read<AuthProvider>();
        if (bundle.marketName.isNotEmpty &&
            auth.marketName.isNotEmpty &&
            bundle.marketName != auth.marketName) {
          throw Exception('market_mismatch');
        }
        setState(() {
          _bundle = bundle;
          _done = 0;
          _total = bundle.customers.length + bundle.debts.length + bundle.payments.length;
          _phase = 'ئامادەیە';
        });
      }
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      setState(() {
        _error = raw.contains('market_mismatch')
            ? 'ناوی مارکێتی ناو فایلەکە لەگەڵ هەژمارەکەت یەک ناگرێتەوە.'
            : 'فایلە CSV/ZIP ـەکە ناتوانرێت وەک Zhirox Import Package بخوێندرێتەوە. ($raw)';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final bundle = _bundle;
    if (bundle == null || _busy) return;
    final ok = await AppHelpers.showConfirmDialog(
      context,
      title: 'دەستپێکردنی Import',
      message:
          'داتاکانی ناو فایلەکە دەخرێنە ناو هەمان هەژماری مارکێتەکەت. '
          'Import دووبارە پارێزراوە و لە کۆتایی بالانس پشتڕاست دەکرێتەوە. بەردەوام بیت؟',
    );
    if (!ok || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
      _done = 0;
      _phase = 'دەستپێکردن';
    });
    try {
      await LegacyImportService.importBundle(
        bundle,
        onProgress: (done, total, phase) {
          if (!mounted) return;
          setState(() {
            _done = done;
            _total = total;
            _phase = phase;
          });
        },
      );
      if (!mounted) return;
      AppHelpers.showSnackBar(context, 'Import بە سەرکەوتوویی تەواو بوو');
      setState(() => _phase = 'تەواو و پشتڕاستکراو');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Import وەستا. دەتوانیت هەمان فایل دووبارە هەڵبژێریت و بەردەوام بیت. (${e.toString()})';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bundle = _bundle;
    final progress = _total <= 0 ? 0.0 : (_done / _total).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(title: const Text('گواستنەوەی داتای کۆن')),
      body: SafeArea(
        child: _checking
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? AppDarkColors.card : Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isDark ? AppDarkColors.cardBorder : const Color(0xFFEAECF0),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: AppColors.primary.withValues(alpha: 0.10),
                              child: const Icon(Icons.move_to_inbox_rounded, color: AppColors.primary),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Zhirox Import Center', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                                  SizedBox(height: 3),
                                  Text('CSV یان ZIP ـی داتای کڕیار، قەرز و پارەدانەوە', style: TextStyle(fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (!_allowed)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Import بۆ ئەم هەژمارە مۆڵەتی نییە. خاوەنی سیستەم دەتوانێت مۆڵەتەکە بکاتەوە.',
                              style: TextStyle(height: 1.6),
                            ),
                          ),
                        if (_allowed) ...[
                          const Text(
                            'فایلەکە پێش هیچ نووسینێک پشکنین دەکرێت. CSV ـی یەک‌فایل یان ZIP هەردووکیان پشتگیری دەکرێن. داتا تەنها بە admin_id ـی هەژمارەکەت دەبەسترێتەوە و ناتوانێت بچێتە tenant ـێکی تر.',
                            style: TextStyle(height: 1.7),
                          ),
                          const SizedBox(height: 14),
                          FilledButton.icon(
                            onPressed: _busy ? null : _pick,
                            icon: const Icon(Icons.file_open_rounded),
                            label: Text(bundle == null ? 'هەڵبژاردنی CSV یان ZIP' : 'گۆڕینی فایل'),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(_error!, style: const TextStyle(color: AppColors.danger, height: 1.6)),
                    ),
                  ],
                  if (bundle != null) ...[
                    const SizedBox(height: 16),
                    _summaryCard(bundle, isDark),
                    const SizedBox(height: 14),
                    if (_busy || _done > 0) ...[
                      LinearProgressIndicator(value: progress),
                      const SizedBox(height: 8),
                      Text('$_phase — $_done / $_total', textAlign: TextAlign.center),
                      const SizedBox(height: 14),
                    ],
                    FilledButton.icon(
                      onPressed: (!_allowed || _busy) ? null : _import,
                      icon: const Icon(Icons.cloud_upload_rounded),
                      label: const Text('دەستپێکردنی Import'),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _summaryCard(LegacyImportBundle bundle, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? AppDarkColors.cardBorder : const Color(0xFFEAECF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('پێشبینینی Import', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 12),
          _line('فایل', bundle.fileName),
          if (bundle.marketName.isNotEmpty) _line('مارکێت', bundle.marketName),
          _line('کڕیار', '${bundle.customers.length}'),
          _line('قەرز', '${bundle.debts.length}'),
          _line('پارەدانەوە', '${bundle.payments.length}'),
          _line('بالانسی چاوەڕوانکراو', '${bundle.expectedBalanceIqd.toStringAsFixed(0)} د.ع'),
        ],
      ),
    );
  }

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(color: AppColors.textSecondary))),
            Flexible(child: Text(value, textAlign: TextAlign.left, style: const TextStyle(fontWeight: FontWeight.w700))),
          ],
        ),
      );
}
