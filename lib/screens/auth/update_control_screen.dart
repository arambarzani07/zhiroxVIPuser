import 'package:flutter/material.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

class UpdateControlScreen extends StatefulWidget {
  const UpdateControlScreen({super.key});

  @override
  State<UpdateControlScreen> createState() => _UpdateControlScreenState();
}

class _UpdatePolicy {
  _UpdatePolicy({
    required this.edition,
    required this.label,
    required this.mandatory,
    required this.notes,
  }) : controller = TextEditingController(text: notes);

  final String edition;
  final String label;
  bool mandatory;
  String notes;
  final TextEditingController controller;
  bool saving = false;

  void dispose() => controller.dispose();
}

class _UpdateControlScreenState extends State<UpdateControlScreen> {
  final Map<String, _UpdatePolicy> _policies = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final policy in _policies.values) {
      policy.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await PBService.ensureInitialized();
      final rows = await PBService.client
          .from('app_update_settings')
          .select('edition, mandatory, notes, updated_at')
          .order('edition');

      if (!mounted) return;
      for (final policy in _policies.values) {
        policy.dispose();
      }
      _policies.clear();
      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw);
        final edition = row['edition']?.toString() ?? '';
        if (edition != 'owner' && edition != 'user') continue;
        _policies[edition] = _UpdatePolicy(
          edition: edition,
          label: edition == 'owner' ? 'ZHIROX Owner' : 'ZHIROX User',
          mandatory: row['mandatory'] == true,
          notes: row['notes']?.toString() ?? '',
        );
      }
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'زانیاری Update Center وەرنەگیرا. دووبارە هەوڵ بدە.';
      });
    }
  }

  Future<void> _save(_UpdatePolicy policy) async {
    if (policy.saving) return;
    setState(() => policy.saving = true);
    try {
      await PBService.ensureInitialized();
      final uid = PBService.client.auth.currentUser?.id;
      if (uid == null) throw StateError('not_authenticated');
      final notes = policy.controller.text.trim();
      await PBService.client
          .from('app_update_settings')
          .update({
            'mandatory': policy.mandatory,
            'notes': notes,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
            'updated_by': uid,
          })
          .eq('edition', policy.edition);

      policy.notes = notes;
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        'ڕێکخستنی ${policy.label} پاشەکەوت کرا.',
      );
    } catch (e) {
      if (!mounted) return;
      final text = e.toString().toLowerCase();
      final message = text.contains('permission') ||
              text.contains('forbidden') ||
              text.contains('row-level security')
          ? 'تەنها خاوەن سیستەم دەتوانێت Update Center بگۆڕێت.'
          : 'پاشەکەوتکردن سەرکەوتوو نەبوو. دووبارە هەوڵ بدە.';
      AppHelpers.showSnackBar(context, message, isError: true);
    } finally {
      if (mounted) setState(() => policy.saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background =
        isDark ? AppDarkColors.background : const Color(0xFFF7F8FA);
    final surface = isDark ? AppDarkColors.card : Colors.white;
    final border = isDark ? AppDarkColors.cardBorder : const Color(0xFFE4E7EC);
    final textPrimary =
        isDark ? AppDarkColors.textPrimary : const Color(0xFF101828);
    final textSecondary =
        isDark ? AppDarkColors.textSecondary : const Color(0xFF667085);

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: const Text('کۆنترۆڵی Auto Update'),
        backgroundColor: isDark ? AppDarkColors.surface : Colors.white,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: border),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.system_update_alt_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Auto Update Center',
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'لێرە دەتوانیت نوێکردنەوەی Owner و User بە جیاوازی بکەیتە ناچاری و پەیامی وەشان بگۆڕیت، بەبێ دروستکردنەوەی IPA.',
                          style: TextStyle(
                            color: textSecondary,
                            fontSize: 11.5,
                            height: 1.65,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: border),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.cloud_off_rounded, size: 34),
                    const SizedBox(height: 10),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('دووبارە هەوڵ بدە'),
                    ),
                  ],
                ),
              )
            else ...[
              if (_policies['owner'] case final owner?)
                _buildPolicyCard(
                  owner,
                  surface: surface,
                  border: border,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                ),
              if (_policies['owner'] != null && _policies['user'] != null)
                const SizedBox(height: 14),
              if (_policies['user'] case final user?)
                _buildPolicyCard(
                  user,
                  surface: surface,
                  border: border,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPolicyCard(
    _UpdatePolicy policy, {
    required Color surface,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      policy.label,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      policy.mandatory
                          ? 'نوێکردنەوە ناچارییە'
                          : 'نوێکردنەوە ئیختیارییە',
                      style: TextStyle(
                        color: policy.mandatory ? Colors.red : textSecondary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: policy.mandatory,
                onChanged: policy.saving
                    ? null
                    : (value) => setState(() => policy.mandatory = value),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: policy.controller,
            enabled: !policy.saving,
            minLines: 3,
            maxLines: 5,
            maxLength: 1000,
            decoration: const InputDecoration(
              labelText: 'پەیامی وەشان',
              hintText: 'نموونە: چاککردنی خێرایی و زیادکردنی تایبەتمەندی نوێ...',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          if (policy.mandatory)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'کاتێک IPA ـی نوێتر بەردەست بێت، بەکارهێنەر ناتوانێت پەنجەرەی Update دابخات تا لینکی نوێکردنەوە بکاتەوە.',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 10.5,
                  height: 1.6,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: policy.saving ? null : () => _save(policy),
              icon: policy.saving
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_rounded, size: 18),
              label: Text(policy.saving ? 'پاشەکەوت دەکرێت...' : 'پاشەکەوتکردن'),
            ),
          ),
        ],
      ),
    );
  }
}
