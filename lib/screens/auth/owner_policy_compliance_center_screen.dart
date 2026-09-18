import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:zhirox/widgets/app_design.dart';

class OwnerPolicyComplianceCenterScreen extends StatefulWidget {
  const OwnerPolicyComplianceCenterScreen({super.key});

  @override
  State<OwnerPolicyComplianceCenterScreen> createState() =>
      _OwnerPolicyComplianceCenterScreenState();
}

class _OwnerPolicyComplianceCenterScreenState
    extends State<OwnerPolicyComplianceCenterScreen> {
  Map<String, dynamic> _overview = const {};
  Map<String, dynamic> _retention = const {};
  List<Map<String, dynamic>> _documents = const [];
  List<Map<String, dynamic>> _admins = const [];
  bool _loading = true;
  String? _error;

  int _asInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('${value ?? 0}') ?? 0;

  String _date(dynamic value) {
    final parsed = DateTime.tryParse('${value ?? ''}');
    if (parsed == null) return '—';
    return DateFormat('yyyy/MM/dd HH:mm').format(parsed.toLocal());
  }

  String _policyLabel(String key) => switch (key) {
        'terms' => 'مەرجەکانی خزمەتگوزاری',
        'privacy' => 'سیاسەتی تایبەتمەندی',
        'security_notice' => 'ئاگاداری پاراستن',
        'service_policy' => 'سیاسەتی خزمەتگوزاری',
        _ => key,
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        PBService.getOwnerPolicyOverview(),
        PBService.getOwnerPolicyPage(page: 1, perPage: 100),
      ]);
      final page = results[1];

      final docs = <Map<String, dynamic>>[];
      final rawDocs = page['documents'];
      if (rawDocs is List) {
        for (final item in rawDocs) {
          if (item is Map) docs.add(Map<String, dynamic>.from(item));
        }
      }

      final admins = <Map<String, dynamic>>[];
      final rawAdmins = page['admins'];
      if (rawAdmins is List) {
        for (final item in rawAdmins) {
          if (item is Map) admins.add(Map<String, dynamic>.from(item));
        }
      }

      if (!mounted) return;
      setState(() {
        _overview = results[0];
        _documents = docs;
        _admins = admins;
        _retention = page['retention'] is Map
            ? Map<String, dynamic>.from(page['retention'] as Map)
            : const {};
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppHelpers.backendErrorMessage(
          error,
          fallback: 'نەتوانرا زانیاری سیاسەت و پابەندبوون بهێنرێت.',
        );
      });
    }
  }

  Future<void> _publishPolicy() async {
    var policyKey = 'terms';
    var requiresReacceptance = true;
    final title = TextEditingController();
    final body = TextEditingController();

    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            scrollable: true,
            title: const Text('بڵاوکردنەوەی سیاسەتی نوێ'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: policyKey,
                  decoration: const InputDecoration(
                    labelText: 'جۆری سیاسەت',
                    prefixIcon: Icon(Icons.policy_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'terms',
                      child: Text('مەرجەکانی خزمەتگوزاری'),
                    ),
                    DropdownMenuItem(
                      value: 'privacy',
                      child: Text('سیاسەتی تایبەتمەندی'),
                    ),
                    DropdownMenuItem(
                      value: 'security_notice',
                      child: Text('ئاگاداری پاراستن'),
                    ),
                    DropdownMenuItem(
                      value: 'service_policy',
                      child: Text('سیاسەتی خزمەتگوزاری'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => policyKey = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: title,
                  maxLength: 160,
                  decoration: const InputDecoration(
                    labelText: 'ناونیشان',
                    prefixIcon: Icon(Icons.title_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: body,
                  minLines: 8,
                  maxLines: 16,
                  decoration: const InputDecoration(
                    labelText: 'ناوەڕۆکی سیاسەت',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.description_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: requiresReacceptance,
                  onChanged: (value) =>
                      setDialogState(() => requiresReacceptance = value),
                  title: const Text('داوای پەسەندکردنەوەی نوێ'),
                  subtitle: const Text(
                    'ئەگەر چالاک بێت، بەڕێوەبەرەکان دەبێت وەشانی نوێ پەسەند بکەن.',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('پاشگەزبوونەوە'),
              ),
              FilledButton(
                onPressed: () {
                  if (title.text.trim().isEmpty) {
                    AppHelpers.showSnackBar(
                      context,
                      'ناونیشان پێویستە.',
                      isError: true,
                    );
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: const Text('بڵاوکردنەوە'),
              ),
            ],
          ),
        ),
      );

      if (accepted != true) return;

      final result = await PBService.publishOwnerPolicyDocument(
        policyKey: policyKey,
        title: title.text.trim(),
        bodyMarkdown: body.text,
        requiresReacceptance: requiresReacceptance,
      );
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        '${_policyLabel(policyKey)} v${_asInt(result['version'])} بڵاوکرایەوە.',
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          error,
          fallback: 'بڵاوکردنەوەی سیاسەت سەرکەوتوو نەبوو.',
        ),
        isError: true,
      );
    } finally {
      title.dispose();
      body.dispose();
    }
  }

  Future<void> _editRetention() async {
    final technical = TextEditingController(
      text: _asInt(_retention['technical_log_days']).toString(),
    );
    final audit = TextEditingController(
      text: _asInt(_retention['audit_log_days']).toString(),
    );
    final auth = TextEditingController(
      text: _asInt(_retention['auth_session_days']).toString(),
    );

    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          scrollable: true,
          title: const Text('سیاسەتی ماوەی هەڵگرتنی داتا'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: technical,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'تۆماری تەکنیکی — ڕۆژ',
                  prefixIcon: Icon(Icons.article_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: audit,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'تۆماری چاودێری خاوەنی سیستەم — ڕۆژ',
                  prefixIcon: Icon(Icons.fact_check_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: auth,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'زانیاریی دانیشتنی چوونەژوورەوە — ڕۆژ',
                  prefixIcon: Icon(Icons.login_rounded),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'ئەمە تەنها ماوەی هەڵگرتنی زانیاریی تەکنیکی پلاتفۆرمە؛ '
                'هیچ ناوەڕۆکی کاروباری مارکێت بەڕێوە نابردرێت.',
                style: TextStyle(fontSize: 11),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('پاشگەزبوونەوە'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('پاشەکەوت'),
            ),
          ],
        ),
      );

      if (accepted != true) return;

      final technicalDays = int.tryParse(technical.text.trim()) ?? 0;
      final auditDays = int.tryParse(audit.text.trim()) ?? 0;
      final authDays = int.tryParse(auth.text.trim()) ?? 0;

      await PBService.setOwnerRetentionPolicy(
        technicalLogDays: technicalDays,
        auditLogDays: auditDays,
        authSessionDays: authDays,
      );
      if (!mounted) return;
      AppHelpers.showSnackBar(context, 'سیاسەتی ماوەی هەڵگرتن نوێ کرایەوە.');
      await _load();
    } catch (error) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          error,
          fallback: 'نوێکردنەوەی سیاسەتی ماوەی هەڵگرتن سەرکەوتوو نەبوو.',
        ),
        isError: true,
      );
    } finally {
      technical.dispose();
      audit.dispose();
      auth.dispose();
    }
  }

  void _showPolicy(Map<String, dynamic> doc) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text('${doc['title'] ?? 'Policy'}'),
        content: SelectableText('${doc['body_markdown'] ?? ''}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('داخستن'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('سیاسەت و پابەندبوون'),
        actions: [
          IconButton(
            tooltip: 'نوێکردنەوە',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _publishPolicy,
        icon: const Icon(Icons.post_add_rounded),
        label: const Text('سیاسەتی نوێ'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off_rounded, size: 44),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('دووبارە هەوڵ بدە'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    children: [
                      const AppSurface(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.privacy_tip_outlined,
                              color: AppColors.primary,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'خاوەنی سیستەم تەنها سیاسەت و زانیاریی پەسەندکردن '
                                'و ماوەی هەڵگرتنی داتای تەکنیکی بەڕێوەدەبات. زانیاریی '
                                'کاروباری مارکێت لەم ناوەندەدا نییە.',
                                style: TextStyle(height: 1.55),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _metric(
                            context,
                            'سیاسەتە چالاکەکان',
                            _asInt(_overview['active_policy_count']).toString(),
                            Icons.policy_outlined,
                          ),
                          _metric(
                            context,
                            'بەڕێوەبەر',
                            _asInt(_overview['admin_account_count']).toString(),
                            Icons.admin_panel_settings_outlined,
                          ),
                          _metric(
                            context,
                            'پابەند',
                            _asInt(_overview['compliant_admin_count']).toString(),
                            Icons.verified_user_outlined,
                          ),
                          _metric(
                            context,
                            'Pending',
                            _asInt(_overview['pending_admin_count']).toString(),
                            Icons.pending_actions_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          const Expanded(
                            child: AppSectionHeader(
                              title: 'ماوەی هەڵگرتنی داتا',
                              subtitle: 'زانیاریی تەکنیکی پلاتفۆرم',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _editRetention,
                            icon: const Icon(Icons.edit_calendar_outlined),
                            label: const Text('دەستکاری'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      AppSurface(
                        child: Wrap(
                          spacing: 16,
                          runSpacing: 10,
                          children: [
                            _mini(
                              Icons.article_outlined,
                              'Technical: ${_asInt(_retention['technical_log_days'])} ڕۆژ',
                            ),
                            _mini(
                              Icons.fact_check_outlined,
                              'Audit: ${_asInt(_retention['audit_log_days'])} ڕۆژ',
                            ),
                            _mini(
                              Icons.login_rounded,
                              'Auth: ${_asInt(_retention['auth_session_days'])} ڕۆژ',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const AppSectionHeader(
                        title: 'سیاسەتە چالاکەکان',
                        subtitle: 'بەڵگەنامە چالاکەکانی پلاتفۆرم',
                      ),
                      const SizedBox(height: 10),
                      if (_documents.isEmpty)
                        const AppSurface(
                          child: Padding(
                            padding: EdgeInsets.all(18),
                            child: Center(
                              child: Text('هێشتا هیچ سیاسەتێک بڵاونەکراوەتەوە.'),
                            ),
                          ),
                        )
                      else
                        ..._documents.map(
                          (doc) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _policyCard(context, doc),
                          ),
                        ),
                      const SizedBox(height: 18),
                      const AppSectionHeader(
                        title: 'پابەندبوونی بەڕێوەبەر',
                        subtitle: 'دۆخی پەسەندکردنی وەشانی چالاک',
                      ),
                      const SizedBox(height: 10),
                      if (_admins.isEmpty)
                        const AppSurface(
                          child: Padding(
                            padding: EdgeInsets.all(18),
                            child: Center(child: Text('هیچ Admin ـێک نییە.')),
                          ),
                        )
                      else
                        ..._admins.map(
                          (admin) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _adminCard(context, admin),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _metric(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return SizedBox(
      width: 160,
      child: AppSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.primary, size: 22),
            const SizedBox(height: 10),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
              textDirection: TextDirection.ltr,
            ),
            const SizedBox(height: 2),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _policyCard(
    BuildContext context,
    Map<String, dynamic> doc,
  ) {
    final key = (doc['policy_key'] ?? '').toString();
    final version = _asInt(doc['version']);
    final required = doc['requires_reacceptance'] == true;

    return AppSurface(
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: AppColors.primarySoft,
            child: Icon(Icons.policy_rounded, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${doc['title'] ?? _policyLabel(key)}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_policyLabel(key)} • v$version • ${_date(doc['published_at'])}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Chip(
                label: Text(required ? 'پەسەندکردنەوە' : 'پێویستی بە پەسەندکردنەوە نییە'),
              ),
              TextButton(
                onPressed: () => _showPolicy(doc),
                child: const Text('بینین'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _adminCard(
    BuildContext context,
    Map<String, dynamic> admin,
  ) {
    final compliant = admin['compliant'] == true;
    return AppSurface(
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: compliant
                ? Colors.green.withValues(alpha: 0.10)
                : Colors.orange.withValues(alpha: 0.10),
            child: Icon(
              compliant
                  ? Icons.verified_user_rounded
                  : Icons.pending_actions_rounded,
              color: compliant ? Colors.green : Colors.orange,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${admin['market_name'] ?? 'مارکێت'}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  '${admin['admin_name'] ?? ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                compliant ? 'پابەند' : 'Pending',
                style: TextStyle(
                  color: compliant ? Colors.green : Colors.orange,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_asInt(admin['accepted_current_count'])}/'
                '${_asInt(admin['active_policy_count'])}',
                style: Theme.of(context).textTheme.bodySmall,
                textDirection: TextDirection.ltr,
              ),
              Text(
                _date(admin['last_acceptance_at']),
                style: Theme.of(context).textTheme.bodySmall,
                textDirection: TextDirection.ltr,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mini(IconData icon, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      );
}
