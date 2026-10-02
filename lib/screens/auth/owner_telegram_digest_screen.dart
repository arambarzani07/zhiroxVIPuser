import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zhirox/services/telegram_integration_service.dart';
import 'package:zhirox/widgets/app_design.dart';

class OwnerTelegramDigestScreen extends StatefulWidget {
  const OwnerTelegramDigestScreen({super.key});

  @override
  State<OwnerTelegramDigestScreen> createState() => _OwnerTelegramDigestScreenState();
}

class _OwnerTelegramDigestScreenState extends State<OwnerTelegramDigestScreen>
    with WidgetsBindingObserver {
  TelegramIntegrationStatus? _status;
  bool _loading = true;
  bool _working = false;
  bool _awaitingReturn = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingReturn) {
      _awaitingReturn = false;
      _refresh();
    }
  }

  Future<void> _refresh() async {
    setState(() { _loading = true; _error = null; });
    try {
      final status = await TelegramIntegrationService.status();
      if (mounted) setState(() => _status = status);
    } catch (error) {
      if (mounted) setState(() => _error = TelegramIntegrationService.userMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _connect() async {
    setState(() { _working = true; _error = null; });
    try {
      final link = await TelegramIntegrationService.createConnectLink();
      _awaitingReturn = true;
      final opened = await launchUrl(link.url, mode: LaunchMode.externalApplication);
      if (!opened) throw Exception('telegram_launch_failed');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('لە ${link.botUsername} کلیک لە Start بکە، پاشان بگەڕێوە بۆ ئەپ.')),
      );
    } catch (error) {
      _awaitingReturn = false;
      if (mounted) setState(() => _error = TelegramIntegrationService.userMessage(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _test() async {
    setState(() { _working = true; _error = null; });
    try {
      await TelegramIntegrationService.testConnection();
      await _refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('پەیامی تاقیکردنەوە نێردرا ✅')));
    } catch (error) {
      if (mounted) setState(() => _error = TelegramIntegrationService.userMessage(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _disconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('پچڕاندنی Telegramی Owner'),
        content: const Text('Daily Owner Digest نامێنێت تا دووبارە Telegram پەیوەست بکەیت.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('نەخێر')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('بەڵێ')),
        ],
      ),
    ) ?? false;
    if (!ok) return;
    setState(() { _working = true; _error = null; });
    try {
      await TelegramIntegrationService.disconnect();
      await _refresh();
    } catch (error) {
      if (mounted) setState(() => _error = TelegramIntegrationService.userMessage(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final connected = status?.connected == true;
    final configured = status?.serviceConfigured == true;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Daily Owner Digest')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppSurface(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  CircleAvatar(
                    backgroundColor: connected ? const Color(0xFF0B9270).withValues(alpha: .12) : scheme.surfaceContainerHighest,
                    child: Icon(connected ? Icons.check_circle_rounded : Icons.telegram_rounded, color: connected ? const Color(0xFF0B9270) : scheme.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(connected ? 'Telegramی Owner پەیوەستە' : 'Telegramی Owner پەیوەست نییە', style: const TextStyle(fontWeight: FontWeight.w900)),
                    if (connected) Text([if ((status?.telegramUsername ?? '').isNotEmpty) '@${status!.telegramUsername}', if ((status?.chatHint ?? '').isNotEmpty) status!.chatHint!].join(' • '), style: Theme.of(context).textTheme.bodySmall),
                  ])),
                  IconButton(onPressed: _loading || _working ? null : _refresh, icon: const Icon(Icons.refresh_rounded)),
                ]),
                const SizedBox(height: 14),
                const Text('هەر ڕۆژ 08:30 بە کاتی عێراق، کورتەی Health، Queue، Dead-letter، Telegram/PDF و Risk بۆ Telegramی Owner دەنێردرێت.', style: TextStyle(height: 1.6)),
                const SizedBox(height: 8),
                const Text('ئەگەر ناردن سەرکەوتوو نەبێت، worker هەر 15 خولەک retry دەکات تا سەرکەوتن؛ لە هەر ڕۆژێک تەنها یەک Digest نێردرێت.', style: TextStyle(fontSize: 12.5, height: 1.6)),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: scheme.error, fontWeight: FontWeight.w700)),
                ],
                if (_working) ...[const SizedBox(height: 12), const LinearProgressIndicator()],
                const SizedBox(height: 16),
                if (!connected)
                  SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: !configured || _working ? null : _connect, icon: const Icon(Icons.telegram_rounded), label: const Text('پەیوەستکردنی Telegramی Owner'))),
                if (connected) ...[
                  SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _working ? null : _test, icon: const Icon(Icons.send_rounded), label: const Text('تاقیکردنەوەی پەیوەندی'))),
                  const SizedBox(height: 8),
                  SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _working ? null : _disconnect, icon: const Icon(Icons.link_off_rounded), label: const Text('پچڕاندنی پەیوەندی'))),
                ],
              ]),
            ),
            const SizedBox(height: 14),
            AppSurface(
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.security_rounded, color: scheme.secondary),
                const SizedBox(width: 10),
                const Expanded(child: Text('Chat ID یان Bot Token بە دەست نانووسرێت. پەیوەندی بە deep-link ـی کاتی و backend ـی پارێزراو دروست دەبێت.', style: TextStyle(fontSize: 12.5, height: 1.6))),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
