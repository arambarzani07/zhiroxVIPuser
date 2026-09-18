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
    required this.rolloutPercent,
    required this.minimumBuild,
  })  : notesController = TextEditingController(text: notes),
        minimumBuildController =
            TextEditingController(text: minimumBuild.toString());

  final String edition;
  final String label;
  bool mandatory;
  String notes;
  int rolloutPercent;
  int minimumBuild;
  final TextEditingController notesController;
  final TextEditingController minimumBuildController;
  bool saving = false;

  void dispose() {
    notesController.dispose();
    minimumBuildController.dispose();
  }
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
          .select(
            'edition, mandatory, notes, rollout_percent, minimum_build, updated_at',
          )
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

        final rollout =
            int.tryParse('${row['rollout_percent'] ?? 100}')?.clamp(0, 100) ??
                100;
        final minimumBuild =
            int.tryParse('${row['minimum_build'] ?? 0}') ?? 0;

        _policies[edition] = _UpdatePolicy(
          edition: edition,
          label: edition == 'owner' ? 'ZHIROX Owner' : 'ZHIROX User',
          mandatory: row['mandatory'] == true,
          notes: row['notes']?.toString() ?? '',
          rolloutPercent: rollout,
          minimumBuild: minimumBuild < 0 ? 0 : minimumBuild,
        );
      }

      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'زانیاری Release Center وەرنەگیرا. دووبارە هەوڵ بدە.';
      });
    }
  }

  Future<void> _save(_UpdatePolicy policy) async {
    if (policy.saving) return;

    final minimumBuild =
        int.tryParse(policy.minimumBuildController.text.trim());
    if (minimumBuild == null || minimumBuild < 0 || minimumBuild > 99999999) {
      AppHelpers.showSnackBar(
        context,
        'Minimum build دەبێت ژمارەیەکی دروست بێت.',
        isError: true,
      );
      return;
    }

    setState(() => policy.saving = true);
    try {
      await PBService.ensureInitialized();
      final uid = PBService.client.auth.currentUser?.id;
      if (uid == null) throw StateError('not_authenticated');

      final notes = policy.notesController.text.trim();
      await PBService.client
          .from('app_update_settings')
          .update({
            'mandatory': policy.mandatory,
            'notes': notes,
            'rollout_percent': policy.rolloutPercent.clamp(0, 100),
            'minimum_build': minimumBuild,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
            'updated_by': uid,
          })
          .eq('edition', policy.edition);

      policy.notes = notes;
      policy.minimumBuild = minimumBuild;
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        'Release policy ـی ${policy.label} پاشەکەوت کرا.',
      );
    } catch (e) {
      if (!mounted) return;
      final text = e.toString().toLowerCase();
      final message = text.contains('permission') ||
              text.contains('forbidden') ||
              text.contains('row-level security')
          ? 'تەنها خاوەن سیستەم دەتوانێت Release Center بگۆڕێت.'
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
    final border =
        isDark ? AppDarkColors.cardBorder : const Color(0xFFE4E7EC);
    final textPrimary =
        isDark ? AppDarkColors.textPrimary : const Color(0xFF101828);
    final textSecondary =
        isDark ? AppDarkColors.textSecondary : const Color(0xFF667085);

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: const Text('Release & Auto Update Center'),
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
                      Icons.rocket_launch_outlined,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Staged Release Control',
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'وەشانی Owner و User بە جیاوازی کۆنترۆڵ بکە: '
                          'Mandatory، rollout percentage، minimum build و release notes. '
                          'ئەم بەشە هیچ business data ـی مارکێت ناخوێنێتەوە.',
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
    final rolloutLabel = policy.rolloutPercent == 0
        ? 'وەستاندراوە'
        : policy.rolloutPercent == 100
            ? 'هەمووان'
            : '${policy.rolloutPercent}%';

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
                          : 'نوێکردنەوە بەپێی rollout policy',
                      style: TextStyle(
                        color:
                            policy.mandatory ? Colors.red : textSecondary,
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
                    : (value) =>
                        setState(() => policy.mandatory = value),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Rollout: $rolloutLabel',
            style: TextStyle(
              color: textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Slider(
            value: policy.rolloutPercent.toDouble(),
            min: 0,
            max: 100,
            divisions: 20,
            label: '${policy.rolloutPercent}%',
            onChanged: policy.saving || policy.mandatory
                ? null
                : (value) => setState(
                      () => policy.rolloutPercent = value.round(),
                    ),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [0, 10, 25, 50, 100]
                .map(
                  (value) => ChoiceChip(
                    label: Text(value == 0 ? 'Pause' : '$value%'),
                    selected: policy.rolloutPercent == value,
                    onSelected: policy.saving || policy.mandatory
                        ? null
                        : (_) => setState(
                              () => policy.rolloutPercent = value,
                            ),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: policy.minimumBuildController,
            enabled: !policy.saving,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Minimum supported build',
              hintText: '0 = ناچالاک',
              prefixIcon: Icon(Icons.vertical_align_bottom_rounded),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'ئەگەر build ـی ئێستا لە Minimum build کەمتر بێت، '
            'نوێکردنەوە خۆکار Mandatory دەبێت و rollout percentage پشتگوێ دەخرێت.',
            style: TextStyle(
              color: textSecondary,
              fontSize: 10.5,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: policy.notesController,
            enabled: !policy.saving,
            minLines: 3,
            maxLines: 5,
            maxLength: 1000,
            decoration: const InputDecoration(
              labelText: 'Release notes',
              hintText:
                  'نموونە: چاککردنی خێرایی و زیادکردنی تایبەتمەندی نوێ...',
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
                'Mandatory mode هەموو بەکارهێنەران ناچار دەکات '
                'و rollout percentage لەم دۆخەدا کاریگەری نییە.',
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
              label: Text(
                policy.saving
                    ? 'پاشەکەوت دەکرێت...'
                    : 'پاشەکەوتکردنی Release Policy',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
