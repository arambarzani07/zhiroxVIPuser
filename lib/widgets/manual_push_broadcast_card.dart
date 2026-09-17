import 'package:flutter/material.dart';
import 'package:zhirox/services/customer_push_service.dart';

class ManualPushBroadcastCard extends StatefulWidget {
  final CustomerPushGateway gateway;

  const ManualPushBroadcastCard({
    super.key,
    this.gateway = const CustomerPushService(),
  });

  @override
  State<ManualPushBroadcastCard> createState() =>
      _ManualPushBroadcastCardState();
}

class _ManualPushBroadcastCardState extends State<ManualPushBroadcastCard> {
  bool _busy = false;

  Future<String?> _composeMessage() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final message = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ئاگاداری گشتی'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'ناوی ئاگادارکردنەوە خۆکارانە ناوی سوپەرمارکێتەکەیە.',
              ),
              const SizedBox(height: 8),
              const Text(
                'ئەم ئاگادارییە تەنها بۆ کڕیارانی پەیوەستکراو بە Web Push دەنێردرێت.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('broadcast-manual-push-message'),
                controller: controller,
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                maxLength: CustomerPushService.manualMessageMaxLength,
                decoration: const InputDecoration(
                  labelText: 'پەیامی ئاگادارکردنەوە',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final normalized = value?.trim() ?? '';
                  if (normalized.isEmpty) return 'پەیام بنووسە';
                  if (normalized.length >
                      CustomerPushService.manualMessageMaxLength) {
                    return 'پەیام زۆر درێژە';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('پاشگەزبوونەوە'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.of(dialogContext).pop(controller.text.trim());
            },
            child: const Text('بەردەوام بە'),
          ),
        ],
      ),
    );
    controller.dispose();
    return message;
  }

  Future<bool> _confirmBroadcast() async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('پشتڕاستکردنەوەی ناردن'),
            content: const Text(
              'ئەم پەیامە بۆ هەموو کڕیارە پەیوەستکراوەکان دەنێردرێت. دڵنیایت؟',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('نەخێر'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                icon: const Icon(Icons.campaign_rounded),
                label: const Text('بەڵێ، بۆ هەمووان بنێرە'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _sendBroadcast() async {
    if (_busy) return;
    final message = await _composeMessage();
    if (!mounted || message == null) return;
    final confirmed = await _confirmBroadcast();
    if (!mounted || !confirmed) return;

    setState(() => _busy = true);
    try {
      final result = await widget.gateway.broadcastManual(message);
      if (!mounted) return;
      final text = result.targetDevices > 0
          ? 'ئاگاداری بە ناوی ${result.marketName} بۆ ${result.queuedCustomers} کڕیار / ${result.targetDevices} ئامێر ڕیزکرا'
          : 'هیچ کڕیارێکی پەیوەستکراو بۆ ئاگاداری نەدۆزرایەوە';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ناردنی ئاگاداری گشتی سەرکەوتوو نەبوو')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.campaign_rounded,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ئاگاداری گشتی',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'ناردنی پەیام بۆ هەموو کڕیارە پەیوەستکراوەکان',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : _sendBroadcast,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.edit_notifications_rounded),
              label: const Text('نووسینی ئاگاداری'),
            ),
          ],
        ),
      ),
    );
  }
}
