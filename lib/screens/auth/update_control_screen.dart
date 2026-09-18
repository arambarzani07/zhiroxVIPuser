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
  Map<String, dynamic> _overview = const {};
  List<Map<String, dynamic>> _compliance = const [];
  bool _loading = true;
  String? _error;

  int _asInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('${value ?? 0}') ?? 0;

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
      final results = await Future.wait([
        PBService.getOwnerReleaseOverview(),
        PBService.getOwnerReleaseCompliancePage(page: 1, perPage: 100),
      ]);
      final overview = results[0];
      final page = results[1];
      final rows = overview['policies'] is List
          ? overview['policies'] as List
          : const <dynamic>[];

      final compliance = <Map<String, dynamic>>[];
      final rawCompliance = page['items'];
      if (rawCompliance is List) {
        for (final item in rawCompliance) {
          if (item is Map) {
            compliance.add(Map<String, dynamic>.from(item));
          }
        }
      }

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
          label: edition == 'owner' ? 'ژیرۆکس — خاوەنی سیستەم' : 'ژیرۆکس — بەکارهێنەر',
          mandatory: row['mandatory'] == true,
          notes: row['notes']?.toString() ?? '',
          rolloutPercent: rollout,
          minimumBuild: minimumBuild < 0 ? 0 : minimumBuild,
        );
      }

      setState(() {
        _overview = Map<String, dynamic>.from(overview);
        _compliance = compliance;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'زانیاری ناوەندی وەشان وەرنەگیرا. دووبارە هەوڵ بدە.';
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
        'کەمترین بێلد دەبێت ژمارەیەکی دروست بێت.',
        isError: true,
      );
      return;
    }

    setState(() => policy.saving = true);
    try {
      final notes = policy.notesController.text.trim();
      await PBService.setOwnerReleasePolicy(
        edition: policy.edition,
        mandatory: policy.mandatory,
        notes: notes,
        rolloutPercent: policy.rolloutPercent.clamp(0, 100),
        minimumBuild: minimumBuild,
      );

      policy.notes = notes;
      policy.minimumBuild = minimumBuild;
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        'سیاسەتی وەشانی ${policy.label} پاشەکەوت کرا.',
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      final text = e.toString().toLowerCase();
      final message = text.contains('permission') ||
              text.contains('forbidden') ||
              text.contains('row-level security')
          ? 'تەنها خاوەن سیستەم دەتوانێت ناوەندی وەشان بگۆڕێت.'
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
        title: const Text('ناوەندی وەشان و نوێکردنەوەی خۆکار'),
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
                          'کۆنترۆڵی بڵاوکردنەوەی قۆناغ‌قۆناغ',
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'وەشانی خاوەنی سیستەم و بەکارهێنەر بە جیاوازی کۆنترۆڵ بکە: '
                          'نوێکردنەوەی ناچاری، ڕێژەی بڵاوکردنەوە، کەمترین بێلد و تێبینی وەشان. '
                          'ئەم بەشە هیچ داتای کاروباری مارکێت ناخوێنێتەوە.',
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
              const SizedBox(height: 18),
              _buildComplianceSummary(
                surface: surface,
                border: border,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
              ),
              const SizedBox(height: 14),
              ..._compliance.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _buildComplianceCard(
                    item,
                    surface: surface,
                    border: border,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildComplianceSummary({
    required Color surface,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    final minimumBuild = _asInt(_overview['user_minimum_build']);
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
          Text(
            'پابەندبوون بە وەشان — ژیرۆکس بەکارهێنەر',
            style: TextStyle(
              color: textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'تەنها زانیاریی بێلد و ئامێری ٣٠ ڕۆژی دوایی؛ '
            'هیچ business data ـی مارکێت ناخوێنرێتەوە.',
            style: TextStyle(
              color: textSecondary,
              fontSize: 11,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _summaryChip(
                Icons.vertical_align_bottom_rounded,
                'کەمترین: $minimumBuild',
                AppColors.primary,
              ),
              _summaryChip(
                Icons.devices_outlined,
                'ئامێر: ${_asInt(_overview['active_devices_30d'])}',
                Colors.blue,
              ),
              _summaryChip(
                Icons.warning_amber_rounded,
                'کۆن: ${_asInt(_overview['outdated_devices_30d'])}',
                Colors.orange,
              ),
              _summaryChip(
                Icons.storefront_outlined,
                'مارکێت: ${_asInt(_overview['outdated_tenants_30d'])}',
                Colors.red,
              ),
              _summaryChip(
                Icons.help_outline_rounded,
                'نەناسراو: ${_asInt(_overview['unknown_build_devices_30d'])}',
                Colors.grey,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
            textDirection: TextDirection.ltr,
          ),
        ],
      ),
    );
  }

  Widget _buildComplianceCard(
    Map<String, dynamic> item, {
    required Color surface,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    final state = (item['compliance_state'] ?? 'no_telemetry').toString();
    final (label, color, icon) = switch (state) {
      'outdated' => ('Outdated', Colors.red, Icons.system_update_alt_rounded),
      'review' => ('Review', Colors.orange, Icons.help_outline_rounded),
      'current' => ('Current', Colors.green, Icons.verified_rounded),
      _ => ('هیچ داتای تەکنیکی نییە', Colors.grey, Icons.devices_other_outlined),
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.10),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item['market_name'] ?? 'مارکێت'}',
                      style: TextStyle(
                        color: textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${item['admin_name'] ?? ''}',
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Chip(
                label: Text(label),
                labelStyle: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
                backgroundColor: color.withValues(alpha: 0.08),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _complianceMini(
                Icons.vertical_align_bottom_rounded,
                'کەمترین ${_asInt(item['minimum_build'])}',
                textSecondary,
              ),
              _complianceMini(
                Icons.new_releases_outlined,
                'نوێترین ${item['latest_build'] ?? '—'}',
                textSecondary,
              ),
              _complianceMini(
                Icons.devices_outlined,
                '${_asInt(item['active_device_count_30d'])} ئامێر',
                textSecondary,
              ),
              _complianceMini(
                Icons.warning_amber_rounded,
                '${_asInt(item['outdated_device_count_30d'])} کۆن',
                textSecondary,
              ),
              _complianceMini(
                Icons.help_outline_rounded,
                '${_asInt(item['unknown_build_device_count_30d'])} نەناسراو',
                textSecondary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _complianceMini(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(color: color, fontSize: 11),
          textDirection: TextDirection.ltr,
        ),
      ],
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
                          : 'نوێکردنەوە بەپێی سیاسەتی بڵاوکردنەوە',
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
            'بڵاوکردنەوە: $rolloutLabel',
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
              labelText: 'کەمترین بێلدی پشتگیریکراو',
              hintText: '0 = ناچالاک',
              prefixIcon: Icon(Icons.vertical_align_bottom_rounded),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'ئەگەر بێلدی ئێستا لە کەمترین بێلد کەمتر بێت، '
            'نوێکردنەوە خۆکار ناچاری دەبێت و ڕێژەی بڵاوکردنەوە پشتگوێ دەخرێت.',
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
              labelText: 'تێبینی وەشان',
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
                'دۆخی ناچاری هەموو بەکارهێنەران ناچار دەکات '
                'و ڕێژەی بڵاوکردنەوە لەم دۆخەدا کاریگەری نییە.',
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
                    : 'پاشەکەوتکردنی سیاسەتی وەشان',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
