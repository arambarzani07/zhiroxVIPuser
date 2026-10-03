import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zhirox/services/hikvision_admin_service.dart';

class HikvisionSettingsScreen extends StatefulWidget {
  const HikvisionSettingsScreen({super.key});

  @override
  State<HikvisionSettingsScreen> createState() => _HikvisionSettingsScreenState();
}

class _HikvisionSettingsScreenState extends State<HikvisionSettingsScreen> {
  HikvisionAdminState? _state;
  bool _loading = true;
  bool _working = false;
  String? _error;
  bool _enabled = true;
  bool _autoCapture = true;
  int _channel = 1;
  int _pre = 15;
  int _post = 30;
  int _retention = 90;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = await HikvisionAdminService.status();
      final config = state.config;
      if (!mounted) return;
      setState(() {
        _state = state;
        if (config != null) {
          _enabled = config.enabled;
          _autoCapture = config.autoCapture;
          _channel = config.cashierChannelId;
          _pre = config.preSeconds;
          _post = config.postSeconds;
          _retention = config.retentionDays;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = HikvisionAdminService.userMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await HikvisionAdminService.updateConfig(
        enabled: _enabled,
        autoCapture: _autoCapture,
        cashierChannelId: _channel,
        preSeconds: _pre,
        postSeconds: _post,
        retentionDays: _retention,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ڕێکخستنی Hikvision پاشەکەوت کرا ✅')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = HikvisionAdminService.userMessage(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _issueToken() async {
    if (_working) return;
    final paired = _state?.gateway?.paired == true;
    if (paired) {
      final ok = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('گۆڕینی Gateway Token'),
              content: const Text(
                'Token ـی نوێ، token ـی کۆن ناچالاک دەکات. دوای دروستکردن دەبێت setup ـی Gateway لە کۆمپیوتەری کاشێر دووبارە جێبەجێ بکەیت.',
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('پاشگەزبوونەوە')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('دروستکردنی نوێ')),
              ],
            ),
          ) ??
          false;
      if (!ok || !mounted) return;
    }

    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final token = await HikvisionAdminService.issueGatewayToken();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Gateway Token — تەنها یەکجار'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'ئەم token ـە تەنها لەم جارە پیشان دەدرێت. لە کۆمپیوتەری کاشێر داخل setup ـەکەی بکە. لە cloud تەنها SHA-256 ـی هەڵدەگیرێت.',
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(token, style: const TextStyle(fontFamily: 'monospace')),
                ),
              ],
            ),
          ),
          actions: [
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: token));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Token کۆپی کرا')),
                  );
                }
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('کۆپی'),
            ),
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('تەواو')),
          ],
        ),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = HikvisionAdminService.userMessage(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _date(DateTime? value) {
    if (value == null) return 'هێشتا پەیوەست نەبووە';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}/${two(value.month)}/${two(value.day)} ${two(value.hour)}:${two(value.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final config = _state?.config;
    final gateway = _state?.gateway;
    return Scaffold(
      appBar: AppBar(title: const Text('Hikvision و ڤیدیۆی مامەلە')),
      body: _loading && _state == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  _StatusCard(
                    paired: gateway?.paired == true,
                    online: gateway?.lastSeenAt != null &&
                        DateTime.now().difference(gateway!.lastSeenAt!).inMinutes < 3,
                    lastSeen: _date(gateway?.lastSeenAt),
                    queued: gateway?.queued ?? 0,
                    processing: gateway?.processing ?? 0,
                    ready: gateway?.ready ?? 0,
                    failed: gateway?.failed ?? 0,
                  ),
                  const SizedBox(height: 14),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('NVR', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 10),
                          _Info('مۆدێل', config?.nvrModel ?? '—'),
                          _Info('ناونیشان', config?.nvrHost ?? '—'),
                          _Info('Firmware', config?.nvrFirmware ?? '—'),
                          _Info('Timezone', config?.timezone ?? 'Asia/Baghdad'),
                          const Divider(height: 26),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            value: _enabled,
                            onChanged: _working ? null : (v) => setState(() => _enabled = v),
                            title: const Text('چالاککردنی Hikvision'),
                          ),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            value: _autoCapture,
                            onChanged: _working ? null : (v) => setState(() => _autoCapture = v),
                            title: const Text('بەستنی خۆکاری ڤیدیۆ بە مامەلە'),
                          ),
                          DropdownButtonFormField<int>(
                            value: _channel,
                            decoration: const InputDecoration(labelText: 'کامێرای کاشێر'),
                            items: [for (var i = 1; i <= 16; i++) DropdownMenuItem(value: i, child: Text('Channel $i'))],
                            onChanged: _working ? null : (v) => setState(() => _channel = v ?? 1),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  value: _pre,
                                  decoration: const InputDecoration(labelText: 'پێش مامەلە'),
                                  items: [5, 10, 15, 20, 30, 45, 60]
                                      .map((v) => DropdownMenuItem(value: v, child: Text('$v چرکە')))
                                      .toList(),
                                  onChanged: _working ? null : (v) => setState(() => _pre = v ?? 15),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  value: _post,
                                  decoration: const InputDecoration(labelText: 'دوای مامەلە'),
                                  items: [10, 15, 30, 45, 60, 90, 120]
                                      .map((v) => DropdownMenuItem(value: v, child: Text('$v چرکە')))
                                      .toList(),
                                  onChanged: _working ? null : (v) => setState(() => _post = v ?? 30),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<int>(
                            value: _retention,
                            decoration: const InputDecoration(labelText: 'ماوەی هەڵگرتنی ڤیدیۆ'),
                            items: [30, 60, 90, 180, 365]
                                .map((v) => DropdownMenuItem(value: v, child: Text('$v ڕۆژ')))
                                .toList(),
                            onChanged: _working ? null : (v) => setState(() => _retention = v ?? 90),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _working ? null : _save,
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('پاشەکەوتکردنی ڕێکخستن'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Secure Local Gateway', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 8),
                          const Text(
                            'پاسۆردی NVR لە Supabase هەڵناگیرێت. تەنها لە کۆمپیوتەری مارکێت بە Windows DPAPI پارێزراو دەبێت، و NVR هیچ پۆرتێک بۆ ئینتەرنێت ناکاتەوە.',
                          ),
                          const SizedBox(height: 14),
                          FilledButton.tonalIcon(
                            onPressed: _working ? null : _issueToken,
                            icon: const Icon(Icons.key_rounded),
                            label: Text(gateway?.paired == true ? 'گۆڕینی Gateway Token' : 'دروستکردنی Gateway Token'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  if (_working) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
                ],
              ),
            ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
            Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700))),
          ],
        ),
      );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.paired,
    required this.online,
    required this.lastSeen,
    required this.queued,
    required this.processing,
    required this.ready,
    required this.failed,
  });

  final bool paired;
  final bool online;
  final String lastSeen;
  final int queued;
  final int processing;
  final int ready;
  final int failed;

  @override
  Widget build(BuildContext context) {
    final color = online ? Colors.green : (paired ? Colors.orange : Colors.grey);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(online ? Icons.videocam_rounded : Icons.videocam_off_rounded, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  online ? 'Gateway Online' : (paired ? 'Gateway پەیوەستە، بەڵام Offline ـە' : 'Gateway هێشتا پەیوەست نییە'),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('کۆتا پەیوەندی: $lastSeen'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Chip('Queue', queued),
              _Chip('Processing', processing),
              _Chip('Ready', ready),
              _Chip('Failed', failed),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.value);
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text('$label: $value', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      );
}
