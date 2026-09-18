import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:zhirox/widgets/app_design.dart';

class OwnerRecoveryDeviceCenterScreen extends StatefulWidget {
  const OwnerRecoveryDeviceCenterScreen({super.key});

  @override
  State<OwnerRecoveryDeviceCenterScreen> createState() =>
      _OwnerRecoveryDeviceCenterScreenState();
}

class _OwnerRecoveryDeviceCenterScreenState
    extends State<OwnerRecoveryDeviceCenterScreen> {
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
        PBService.getOwnerRecoveryDeviceOverview(),
        PBService.getOwnerRecoveryDevicePage(page: 1, perPage: 100),
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
          fallback: 'نەتوانرا زانیاری گەڕاندنەوەی هەژمار و ئامێر بهێنرێت.',
        );
      });
    }
  }

  Future<void> _changePolicy(Map<String, dynamic> item) async {
    var policy = (item['device_policy_mode'] ?? 'observe').toString();
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('${item['market_name'] ?? 'مارکێت'}'),
          content: DropdownButtonFormField<String>(
            initialValue: policy,
            decoration: const InputDecoration(
              labelText: 'سیاسەتی ئامێر',
              prefixIcon: Icon(Icons.phonelink_lock_outlined),
            ),
            items: const [
              DropdownMenuItem(
                value: 'observe',
                child: Text('چاودێری — ئامێری نوێ خۆکار پەسەندە'),
              ),
              DropdownMenuItem(
                value: 'approval_required',
                child: Text('پێویستی بە پەسەندکردن — خاوەنی سیستەم پەسەندی دەکات'),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                setDialogState(() => policy = value);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('پاشگەزبوونەوە'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, policy),
              child: const Text('پاشەکەوت'),
            ),
          ],
        ),
      ),
    );

    if (selected == null) return;
    try {
      await PBService.setOwnerAdminDevicePolicy(
        adminId: item['id'].toString(),
        policy: selected,
      );
      if (!mounted) return;
      AppHelpers.showSnackBar(context, 'سیاسەتی ئامێر نوێ کرایەوە.');
      await _load();
    } catch (error) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          error,
          fallback: 'گۆڕینی سیاسەتی ئامێر سەرکەوتوو نەبوو.',
        ),
        isError: true,
      );
    }
  }

  Future<void> _setDeviceStatus(
    Map<String, dynamic> device,
    String status,
  ) async {
    final label = (device['device_label'] ?? 'ئامێر').toString();
    final ok = await AppHelpers.showConfirmDialog(
      context,
      title: status == 'approved'
          ? 'پەسەندکردنی ئامێر'
          : status == 'revoked'
              ? 'ڕاگرتنی ئامێر'
              : 'گواستنەوە بۆ چاوەڕوان',
      message: status == 'revoked'
          ? '$label ڕادەگیرێت و دانیشتنی پەیوەست پچڕێنرێت. دڵنیایت؟'
          : '$label بگۆڕدرێت بۆ $status؟',
    );
    if (!ok) return;

    try {
      await PBService.setOwnerAdminDeviceAuthorization(
        deviceId: device['id'].toString(),
        status: status,
      );
      if (!mounted) return;
      AppHelpers.showSnackBar(context, 'دۆخی ئامێر نوێ کرایەوە.');
      await _load();
    } catch (error) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          error,
          fallback: 'نوێکردنەوەی دۆخی ئامێر سەرکەوتوو نەبوو.',
        ),
        isError: true,
      );
    }
  }

  Future<void> _recoverAccount(Map<String, dynamic> item) async {
    final pass = TextEditingController();
    final confirm = TextEditingController();
    final reason = TextEditingController();
    var obscure1 = true;
    var obscure2 = true;

    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            scrollable: true,
            title: const Text('گەڕاندنەوەی هەژمار'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${item['market_name'] ?? 'مارکێت'} — وشەی نهێنی نوێ '
                  'دادەنرێت، هەموو دانیشتنەکان ڕادەگیرێن و ئامێرەکان '
                  'دەچنە چاوەڕوان.',
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: pass,
                  obscureText: obscure1,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: 'وشەی نهێنی نوێ',
                    prefixIcon: const Icon(Icons.password_rounded),
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setDialogState(() => obscure1 = !obscure1),
                      icon: Icon(
                        obscure1
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirm,
                  obscureText: obscure2,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: 'دووبارەکردنەوە',
                    prefixIcon: const Icon(Icons.lock_reset_rounded),
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setDialogState(() => obscure2 = !obscure2),
                      icon: Icon(
                        obscure2
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reason,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'هۆکار / تێبینی',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.note_alt_outlined),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'وشەی نهێنی لە تۆماری چاودێری یان داتابەیس تۆمار ناکرێت.',
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
                onPressed: () {
                  if (pass.text.length < 8) {
                    AppHelpers.showSnackBar(
                      context,
                      'وشەی نهێنی لانیکەم ٨ پیت بێت.',
                      isError: true,
                    );
                    return;
                  }
                  if (pass.text != confirm.text) {
                    AppHelpers.showSnackBar(
                      context,
                      'وشە نهێنییەکان یەکسان نین.',
                      isError: true,
                    );
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: const Text('Recovery'),
              ),
            ],
          ),
        ),
      );

      if (accepted != true) return;

      final result = await PBService.recoverOwnerAdminAccount(
        adminId: item['id'].toString(),
        newPassword: pass.text,
        reason: reason.text.trim(),
      );
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        'گەڕاندنەوەی هەژمار تەواو بوو — '
        '${_asInt(result['revoked_session_count'])} دانیشتن ڕاگیرا.',
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          error,
          fallback: 'گەڕاندنەوەی هەژمار سەرکەوتوو نەبوو.',
        ),
        isError: true,
      );
    } finally {
      pass.dispose();
      confirm.dispose();
      reason.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('گەڕاندنەوەی هەژمار و مۆڵەتی ئامێر'),
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
                      const AppSurface(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.admin_panel_settings_outlined,
                              color: AppColors.primary,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'خاوەنی سیستەم تەنها زانیاریی چوونەژوورەوە و ئامێر '
                                'بەڕێوەدەبات. ناوەڕۆکی کاروباری مارکێت '
                                'لەم ناوەندەدا نییە.',
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
                            'Admin',
                            _asInt(_overview['admin_accounts']).toString(),
                            Icons.admin_panel_settings_outlined,
                          ),
                          _metric(
                            context,
                            'ئامێر',
                            _asInt(_overview['registered_devices']).toString(),
                            Icons.devices_outlined,
                          ),
                          _metric(
                            context,
                            'چاوەڕوان',
                            _asInt(_overview['pending_devices']).toString(),
                            Icons.hourglass_top_rounded,
                          ),
                          _metric(
                            context,
                            'ڕاگیراو',
                            _asInt(_overview['revoked_devices']).toString(),
                            Icons.phonelink_erase_rounded,
                          ),
                          _metric(
                            context,
                            'پێویستی بە پەسەندکردن',
                            _asInt(_overview['approval_required_accounts'])
                                .toString(),
                            Icons.verified_user_outlined,
                          ),
                          _metric(
                            context,
                            'گەڕاندنەوە / ٣٠ ڕۆژ',
                            _asInt(_overview['recoveries_30d']).toString(),
                            Icons.manage_accounts_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const AppSectionHeader(
                        title: 'هەژمارەکانی بەڕێوەبەر',
                        subtitle:
                            'گەڕاندنەوەی هەژمار، سیاسەتی ئامێر و پەسەندکردنی ئامێر',
                      ),
                      const SizedBox(height: 10),
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
    final rawDevices = item['devices'];
    final devices = <Map<String, dynamic>>[];
    if (rawDevices is List) {
      for (final row in rawDevices) {
        if (row is Map) devices.add(Map<String, dynamic>.from(row));
      }
    }
    final policy = (item['device_policy_mode'] ?? 'observe').toString();

    return AppSurface(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: const CircleAvatar(
          backgroundColor: AppColors.primarySoft,
          child: Icon(Icons.storefront_rounded, color: AppColors.primary),
        ),
        title: Text(
          '${item['market_name'] ?? 'مارکێت'}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${item['admin_name'] ?? ''} • '
          '${_asInt(item['approved_device_count'])} پەسەندکراو / '
          '${_asInt(item['pending_device_count'])} چاوەڕوان',
        ),
        trailing: Chip(
          label: Text(
            policy == 'approval_required' ? 'Approval' : 'Observe',
          ),
        ),
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _changePolicy(item),
                  icon: const Icon(Icons.policy_outlined, size: 18),
                  label: const Text('سیاسەتی ئامێر'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _recoverAccount(item),
                  icon: const Icon(Icons.manage_accounts_outlined, size: 18),
                  label: const Text('Recovery'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _mini(
                Icons.devices_outlined,
                '${_asInt(item['device_count'])} ئامێر',
              ),
              const SizedBox(width: 12),
              _mini(
                Icons.rule_outlined,
                'سنوور: ${_asInt(item['device_limit'])}',
              ),
              const SizedBox(width: 12),
              _mini(
                Icons.history_rounded,
                'کۆتا گەڕاندنەوە: ${_date(item['last_recovery_at'])}',
              ),
            ],
          ),
          if (devices.isNotEmpty) ...[
            const Divider(height: 24),
            ...devices.map((device) => _deviceRow(context, device)),
          ] else ...[
            const SizedBox(height: 14),
            const Text(
              'هێشتا هیچ ئامێرێک تۆمار نەکراوە.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _deviceRow(
    BuildContext context,
    Map<String, dynamic> device,
  ) {
    final status = (device['status'] ?? 'pending').toString();
    final color = switch (status) {
      'approved' => Colors.green,
      'revoked' => Colors.red,
      _ => Colors.orange,
    };
    final statusLabel = switch (status) {
      'approved' => 'پەسەندکراو',
      'revoked' => 'ڕاگیراو',
      _ => 'چاوەڕوان',
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.smartphone_rounded, color: color),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${device['device_label'] ?? 'ZHIROX app'}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${device['platform'] ?? 'unknown'} • '
                    'وەشان ${device['app_version'] ?? 'unknown'} • '
                    '${_date(device['last_seen_at'])}',
                    style: Theme.of(context).textTheme.bodySmall,
                    textDirection: TextDirection.ltr,
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) => _setDeviceStatus(device, value),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'approved',
                  child: Text('پەسەندکردن'),
                ),
                PopupMenuItem(
                  value: 'pending',
                  child: Text('چاوەڕوان'),
                ),
                PopupMenuItem(
                  value: 'revoked',
                  child: Text('ڕاگرتن'),
                ),
              ],
              child: Chip(
                label: Text(statusLabel),
                labelStyle: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
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
