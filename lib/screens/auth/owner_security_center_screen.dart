import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:zhirox/widgets/app_design.dart';

class OwnerSecurityCenterScreen extends StatefulWidget {
  const OwnerSecurityCenterScreen({super.key});

  @override
  State<OwnerSecurityCenterScreen> createState() =>
      _OwnerSecurityCenterScreenState();
}

class _OwnerSecurityCenterScreenState
    extends State<OwnerSecurityCenterScreen> {
  Map<String, dynamic> _overview = const {};
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;

  int _asInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('${value ?? 0}') ?? 0;

  String _date(dynamic value) {
    final parsed = DateTime.tryParse('${value ?? ''}');
    if (parsed == null) return '—';
    return DateFormat('yyyy/MM/dd HH:mm').format(parsed.toLocal());
  }

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
        PBService.getOwnerSecurityOverview(),
        PBService.getOwnerSecurityPage(page: 1, perPage: 100),
      ]);
      final rows = <Map<String, dynamic>>[];
      final raw = results[1]['items'];
      if (raw is List) {
        for (final item in raw) {
          if (item is Map) rows.add(Map<String, dynamic>.from(item));
        }
      }
      if (!mounted) return;
      setState(() {
        _overview = results[0];
        _items = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppHelpers.backendErrorMessage(
          error,
          fallback: 'نەتوانرا زانیاری پاراستن بهێنرێت.',
        );
      });
    }
  }

  Future<void> _revokeSessions(Map<String, dynamic> item) async {
    final ok = await AppHelpers.showConfirmDialog(
      context,
      title: 'دەرکردن لە هەموو ئامێرەکان',
      message:
          'هەموو session ـەکانی ئەم هەژمارە ڕادەگیرێن و پێویستە دووبارە بچێتە ژوورەوە. دڵنیایت؟',
    );
    if (!ok) return;

    try {
      final result = await PBService.revokeOwnerAdminSessions(
        item['id'].toString(),
      );
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        '${_asInt(result['revoked_session_count'])} session ڕاگیرا.',
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          error,
          fallback: 'ڕاگرتنی session ـەکان سەرکەوتوو نەبوو.',
        ),
        isError: true,
      );
    }
  }

  Future<void> _toggleLock(Map<String, dynamic> item) async {
    final locked = item['locked'] == true;
    final market = (item['market_name'] ?? 'مارکێت').toString();
    final ok = await AppHelpers.showConfirmDialog(
      context,
      title: locked ? 'کردنەوەی هەژمار' : 'قوفڵکردنی هەژمار',
      message: locked
          ? 'هەژماری $market دووبارە چالاک بکرێتەوە؟'
          : 'هەژماری $market قوفڵ دەکرێت و هەموو session ـەکانی ڕادەگیرێن. دڵنیایت؟',
    );
    if (!ok) return;

    try {
      await PBService.setOwnerAdminLock(
        adminId: item['id'].toString(),
        locked: !locked,
      );
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        locked ? 'هەژمار چالاک کرایەوە.' : 'هەژمار قوفڵ کرا.',
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          error,
          fallback: 'گۆڕینی دۆخی پاراستن سەرکەوتوو نەبوو.',
        ),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ناوەندی پاراستن'),
        actions: [
          IconButton(
            tooltip: 'نوێکردنەوە',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
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
                    padding: const EdgeInsets.all(16),
                    children: [
                      AppSurface(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.security_rounded,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'خاوەنی سیستەم تەنها زانیاریی سیستەمی چوونەژوورەوە، دانیشتن و دۆخی '
                                'پاراستنی هەژماری بەڕێوەبەر دەبینێت. وردەکاری ناونیشانی تۆڕ و ئامێر '
                                'و ناوەڕۆکی مارکێت پیشان نادرێن.',
                                style: TextStyle(
                                  color: secondary,
                                  height: 1.55,
                                ),
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
                            'هەژماری بەڕێوەبەر',
                            _asInt(_overview['total_admin_accounts']).toString(),
                            Icons.admin_panel_settings_outlined,
                          ),
                          _metric(
                            context,
                            'دانیشتنی چالاک',
                            _asInt(_overview['active_sessions']).toString(),
                            Icons.devices_outlined,
                          ),
                          _metric(
                            context,
                            'قوفڵکراو',
                            _asInt(_overview['locked_admin_accounts']).toString(),
                            Icons.lock_outline_rounded,
                          ),
                          _metric(
                            context,
                            'پێویستی بە پشکنین',
                            _asInt(_overview['accounts_needing_review'])
                                .toString(),
                            Icons.gpp_maybe_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const AppSectionHeader(
                        title: 'هەژمار و دانیشتن',
                        subtitle:
                            'کۆنترۆڵی دەستگەیشتن بەبێ دەستگەیشتن بە داتای کاروبار',
                      ),
                      const SizedBox(height: 10),
                      if (_items.isEmpty)
                        const AppSurface(
                          child: Center(
                            child: Padding(
                              padding: EdgeInsets.all(18),
                              child: Text('هیچ هەژماری بەڕێوەبەر نییە.'),
                            ),
                          ),
                        )
                      else
                        ..._items.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _accountCard(context, item),
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

  Widget _accountCard(
    BuildContext context,
    Map<String, dynamic> item,
  ) {
    final market = (item['market_name'] ?? 'مارکێت').toString();
    final admin = (item['admin_name'] ?? '').toString();
    final phone = (item['phone'] ?? '').toString();
    final state = (item['security_state'] ?? 'normal').toString();
    final locked = item['locked'] == true;

    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                backgroundColor: AppColors.primarySoft,
                child: Icon(
                  Icons.admin_panel_settings_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      market,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      admin.isEmpty ? phone : '$admin • $phone',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              _statusChip(state),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _mini(
                Icons.devices_outlined,
                '${_asInt(item['active_sessions'])} session',
              ),
              _mini(
                Icons.verified_user_outlined,
                '${_asInt(item['aal2_sessions'])} AAL2',
              ),
              _mini(
                Icons.network_check_rounded,
                '${_asInt(item['recent_ip_count_24h'])} IP/24h',
              ),
              _mini(
                Icons.devices_other_outlined,
                '${_asInt(item['recent_device_count_30d'])} device/30d',
              ),
              _mini(
                Icons.event_available_outlined,
                'Login: ${_date(item['last_sign_in_at'])}',
              ),
              _mini(
                Icons.history_rounded,
                'Session: ${_date(item['last_session_at'])}',
              ),
              _mini(
                Icons.rule_rounded,
                'Limit: ${_asInt(item['device_limit'])}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _asInt(item['active_sessions']) == 0
                      ? null
                      : () => _revokeSessions(item),
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('ڕاگرتنی دانیشتنەکان'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: locked
                        ? Colors.green
                        : Theme.of(context).colorScheme.error,
                  ),
                  onPressed: () => _toggleLock(item),
                  icon: Icon(
                    locked
                        ? Icons.lock_open_rounded
                        : Icons.lock_outline_rounded,
                    size: 18,
                  ),
                  label: Text(locked ? 'کردنەوە' : 'قوفڵکردن'),
                ),
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

  Widget _statusChip(String state) {
    final (label, color) = switch (state) {
      'locked' => ('قوفڵکراو', Colors.red),
      'review' => ('پشکنین', Colors.orange),
      _ => ('ئاسایی', Colors.green),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
