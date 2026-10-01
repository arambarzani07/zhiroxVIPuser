import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zhirox/services/telegram_integration_service.dart';
import 'package:zhirox/utils/constants.dart';

class TelegramSettingsDialog extends StatefulWidget {
  const TelegramSettingsDialog({super.key});

  @override
  State<TelegramSettingsDialog> createState() => _TelegramSettingsDialogState();
}

class _TelegramSettingsDialogState extends State<TelegramSettingsDialog> {
  TelegramIntegrationStatus? _status;
  bool _loading = true;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await TelegramIntegrationService.status();
      if (!mounted) return;
      setState(() => _status = status);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = TelegramIntegrationService.userMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _connect() async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final link = await TelegramIntegrationService.createConnectLink();
      final opened = await launchUrl(link.url, mode: LaunchMode.externalApplication);
      if (!opened) throw Exception('telegram_launch_failed');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'لە ${link.botUsername} کلیک لە Start بکە، پاشان بگەڕێوە و «نوێکردنەوە» بکە.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = TelegramIntegrationService.userMessage(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _test() async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await TelegramIntegrationService.testConnection();
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('پەیامی تاقیکردنەوە نێردرا ✅')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = TelegramIntegrationService.userMessage(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _disconnect() async {
    if (_working) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('پچڕاندنی Telegram'),
            content: const Text(
              'دڵنیایت دەتەوێت پەیوەندی Telegram لەم هەژمارە بپچڕێنیت؟',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('نەخێر'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('بەڵێ، بپچڕێنەوە'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await TelegramIntegrationService.disconnect();
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = TelegramIntegrationService.userMessage(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '—';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}/${two(value.month)}/${two(value.day)}  ${two(value.hour)}:${two(value.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final connected = status?.connected == true;
    final configured = status?.serviceConfigured == true;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.telegram, color: Colors.blue),
          SizedBox(width: 10),
          Text('Telegram'),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: _loading && status == null
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: connected
                            ? Colors.green.withValues(alpha: 0.08)
                            : Colors.grey.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: connected
                              ? Colors.green.withValues(alpha: 0.25)
                              : Colors.grey.withValues(alpha: 0.20),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            connected
                                ? Icons.check_circle_rounded
                                : Icons.link_off_rounded,
                            color: connected ? Colors.green : Colors.grey,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  connected ? 'پەیوەستە' : 'پەیوەست نییە',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                                if (connected)
                                  Text(
                                    [
                                      if ((status?.telegramUsername ?? '').isNotEmpty)
                                        '@${status!.telegramUsername}',
                                      if ((status?.chatHint ?? '').isNotEmpty)
                                        status!.chatHint!,
                                    ].join(' • '),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (!configured)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'خزمەتگوزاری Telegram هێشتا لەلایەن خاوەنی سیستەمەوە چالاک نەکراوە. Bot Token لە ئەپدا داواناکرێت و تەنها لە backend هەڵدەگیرێت.',
                          style: TextStyle(fontSize: 12.5, height: 1.5),
                        ),
                      ),
                    if (connected) ...[
                      _InfoRow(
                        label: 'پەیوەستکراوە لە',
                        value: _formatDate(status?.connectedAt),
                      ),
                      _InfoRow(
                        label: 'کۆتا تاقیکردنەوە',
                        value: _formatDate(status?.lastTestedAt),
                      ),
                    ] else if (configured) ...[
                      const Text(
                        'کلیک لە «پەیوەستکردن» بکە. Telegram دەکرێتەوە و تەنها Start دەکەیت؛ پێویست بە Bot Token یان Chat ID نییە.',
                        style: TextStyle(fontSize: 13, height: 1.6),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.red, fontSize: 12.5),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (_working) const LinearProgressIndicator(),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _working ? null : _refresh,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('نوێکردنەوە'),
        ),
        if (connected)
          TextButton.icon(
            onPressed: _working ? null : _disconnect,
            icon: const Icon(Icons.link_off_rounded, size: 18, color: Colors.red),
            label: const Text('پچڕاندن'),
          ),
        if (connected)
          OutlinedButton.icon(
            onPressed: _working ? null : _test,
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('تاقیکردنەوە'),
          ),
        if (!connected)
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: !configured || _working ? null : _connect,
            icon: const Icon(Icons.telegram, size: 19),
            label: const Text('پەیوەستکردن'),
          ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodySmall?.color,
                fontSize: 12,
              ),
            ),
          ),
          Text(value, style: const TextStyle(fontSize: 12.5)),
        ],
      ),
    );
  }
}
