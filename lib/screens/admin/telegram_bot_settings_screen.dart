import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/services/telegram_admin_service.dart';
import 'package:zhirox/widgets/app_design.dart';

class TelegramBotSettingsScreen extends StatefulWidget {
  const TelegramBotSettingsScreen({super.key});

  @override
  State<TelegramBotSettingsScreen> createState() =>
      _TelegramBotSettingsScreenState();
}

class _TelegramBotSettingsScreenState
    extends State<TelegramBotSettingsScreen> {
  final _tokenController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _obscure = true;
  TelegramAdminStatus? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await TelegramAdminService.status();
      if (!mounted) return;
      setState(() => _status = status);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _error = 'Bot Token بنووسە');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final status = await TelegramAdminService.setToken(token);
      _tokenController.clear();
      if (!mounted) return;
      setState(() => _status = status);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status.botUsername == null
                ? 'Telegram bot بە سەرکەوتوویی چالاک کرا'
                : '${status.botUsername} بە سەرکەوتوویی چالاک کرا',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('ناچالاککردنی Telegram bot'),
            content: const Text(
              'دڵنیایت؟ Webhook دادەخرێت و Bot Token لە Vault دەسڕدرێتەوە.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('نەخێر'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('بەڵێ'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final status = await TelegramAdminService.clearToken();
      if (!mounted) return;
      setState(() => _status = status);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isOwner = auth.user?.getBoolValue('is_system_owner') ?? false;
    final scheme = Theme.of(context).colorScheme;

    if (!isOwner) {
      return Scaffold(
        appBar: AppBar(title: const Text('Telegram Bot')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'تەنها خاوەنی سیستەم دەتوانێت ئەم ڕێکخستنە بگۆڕێت.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final status = _status;
    final configured = status?.configured == true;
    final verified = status?.verified == true;

    return Scaffold(
      appBar: AppBar(title: const Text('ڕێکخستنی Telegram Bot')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppSurface(
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.telegram_rounded,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _loading
                              ? 'پشکنین...'
                              : verified
                                  ? 'چالاک و پشتڕاستکراوە'
                                  : configured
                                      ? 'Token هەیە، بەڵام پشتڕاست نییە'
                                      : 'هێشتا چالاک نەکراوە',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        if ((status?.botUsername ?? '').isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(status!.botUsername!),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _loading || _saving ? null : _refresh,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bot Token',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Token تەنها بۆ verify و ناردن بۆ backend بەکاردێت؛ لە مۆبایل هەڵناگیرێت و دووبارە پیشان نادرێت.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _tokenController,
                    obscureText: _obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.visiblePassword,
                    decoration: InputDecoration(
                      labelText: 'Token ـی BotFather',
                      hintText: '123456789:AA...',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: scheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.verified_user_outlined),
                      label: const Text('پشتڕاستکردنەوە و چالاککردن'),
                    ),
                  ),
                  if (configured) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : _clear,
                        icon: const Icon(Icons.link_off_rounded),
                        label: const Text('ناچالاککردنی Telegram bot'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
