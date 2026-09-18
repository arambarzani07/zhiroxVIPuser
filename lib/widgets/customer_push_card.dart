import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:zhirox/services/customer_push_service.dart';

class CustomerPushCard extends StatefulWidget {
  final String customerId;
  final CustomerPushGateway gateway;

  const CustomerPushCard({
    super.key,
    required this.customerId,
    this.gateway = const CustomerPushService(),
  });

  @override
  State<CustomerPushCard> createState() => _CustomerPushCardState();
}

class _CustomerPushCardState extends State<CustomerPushCard> {
  CustomerPushStatus? _status;
  List<CustomerPushHistoryItem> _history = const [];
  bool _loading = true;
  bool _historyLoading = true;
  bool _busy = false;
  String? _error;
  String? _historyError;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait<void>([
      _loadStatus(),
      _loadHistory(),
    ]);
  }

  Future<void> _loadStatus() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final status = await widget.gateway.loadStatus(widget.customerId);
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'نەتوانرا دۆخی ئاگادارکردنەوە بخوێندرێتەوە';
      });
    }
  }

  Future<void> _loadHistory() async {
    if (!mounted) return;
    setState(() {
      _historyLoading = true;
      _historyError = null;
    });

    try {
      final history = await widget.gateway.loadHistory(widget.customerId);
      if (!mounted) return;
      setState(() {
        _history = history;
        _historyLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _historyLoading = false;
        _historyError = 'نەتوانرا مێژووی ئاگادارکردنەوەکان بخوێندرێتەوە';
      });
    }
  }

  String _eventLabel(String eventType) {
    switch (eventType) {
      case 'debt_created':
        return 'قەرز';
      case 'payment_created':
        return 'پارەدانەوە';
      case 'manual':
        return 'ئاگاداری دەستی';
      case 'due_reminder':
        return 'یادخستنەوە';
      default:
        return 'ئاگادارکردنەوە';
    }
  }

  String _statusLabel(String value) {
    switch (value) {
      case 'sent':
        return 'نێردرا';
      case 'pending':
        return 'لە ڕیزدایە';
      case 'partial':
        return 'بەشێکی نێردرا';
      case 'failed':
        return 'شکست';
      case 'no_device':
        return 'ئامێری چالاک نییە';
      default:
        return value;
    }
  }

  IconData _statusIcon(String value) {
    switch (value) {
      case 'sent':
        return Icons.check_circle_outline_rounded;
      case 'pending':
        return Icons.schedule_rounded;
      case 'partial':
        return Icons.warning_amber_rounded;
      case 'failed':
        return Icons.error_outline_rounded;
      case 'no_device':
        return Icons.phone_iphone_rounded;
      default:
        return Icons.notifications_none_rounded;
    }
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    String two(int input) => input.toString().padLeft(2, '0');
    return '${local.year}/${two(local.month)}/${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  String _historyDetail(CustomerPushHistoryItem item) {
    final parts = <String>[
      _statusLabel(item.status),
      _formatDate(item.createdAt),
    ];
    if (item.amount != null) {
      parts.add('${item.amount} ${item.currency ?? 'IQD'}');
    }
    if (item.deviceCount > 0) {
      parts.add('ئامێر: ${item.deviceCount}');
    }
    return parts.join(' • ');
  }

  Future<void> _retryNotification(CustomerPushHistoryItem item) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await widget.gateway.retryNotification(
        widget.customerId,
        item.id,
      );
      if (!mounted) return;
      await _loadAll();
      if (!mounted) return;
      final message = result.alreadySent
          ? 'ئەم ئاگادارکردنەوەیە پێشتر بە سەرکەوتوویی نێردراوە'
          : 'دووبارە ناردنەوە بۆ ${result.retryDevices} ئامێر ڕیزکرا';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (error) {
      if (!mounted) return;
      final text = error.toString().contains('no_active_push_subscription')
          ? 'هیچ ئامێرێکی چالاک نییە؛ کڕیار دەبێت ئاگادارکردنەوە چالاک بکات'
          : 'دووبارە ناردنەوە سەرکەوتوو نەبوو';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showQr() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final link = await widget.gateway.createLink(widget.customerId);
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          final url = link.url.toString();
          return Dialog(
            child: SizedBox(
              width: 320,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'QR ـی ئاگادارکردنەوە',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: 240,
                      height: 240,
                      child: QrImageView(
                        key: ValueKey<String>(url),
                        data: url,
                        version: QrVersions.auto,
                        size: 240,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'ئەم لینکە بەردەوام کار دەکات تا بەڕێوەبەر ڕایدەگرێت.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('داخستن'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
      if (mounted) await _loadAll();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('نەتوانرا QR ـی ئاگادارکردنەوە دروست بکرێت'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendManual() async {
    if (_busy) return;
    final formKey = GlobalKey<FormState>();
    var draft = '';
    final message = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('ئاگاداری بۆ ئەم کڕیارە'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'ناوی ئاگادارکردنەوە خۆکارانە ناوی سوپەرمارکێتەکەیە.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('customer-manual-push-message'),
                autofocus: true,
                minLines: 3,
                maxLines: 5,
                maxLength: CustomerPushService.manualMessageMaxLength,
                onChanged: (value) => draft = value,
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
          FilledButton.icon(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.of(dialogContext).pop(draft.trim());
            },
            icon: const Icon(Icons.send_rounded),
            label: const Text('ناردن'),
          ),
        ],
      ),
    );
    if (!mounted || message == null) return;

    setState(() => _busy = true);
    try {
      final result = await widget.gateway.sendManual(widget.customerId, message);
      if (!mounted) return;
      final text = result.targetDevices > 0
          ? 'ئاگاداری بە ناوی ${result.marketName} بۆ ${result.targetDevices} ئامێر ڕیزکرا'
          : 'هیچ ئامێرێکی چالاک بۆ ئەم کڕیارە نەدۆزرایەوە';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ناردنی ئاگاداری سەرکەوتوو نەبوو')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revokeAll() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ڕاگرتنی لینک و ئاگادارکردنەوەکان'),
        content: const Text(
          'دڵنیایت لە ڕاگرتنی هەموو QR لینک و ئامێرە چالاکەکان؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('نەخێر'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('بەڵێ، ڕایانبگرە'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final count = await widget.gateway.revokeAll(widget.customerId);
      if (!mounted) return;
      await _loadAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('هەموو لینکەکان ڕاگیران و $count ئامێر ناچالاک کرا'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('نەتوانرا لینک و ئامێرەکان ڕابگیرێن'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _status;
    final canRevoke = status != null &&
        (status.hasActiveLink || status.deviceCount > 0);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.notifications_active_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'ئاگادارکردنەوەی کڕیار',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (!_loading && _error == null)
                  IconButton(
                    tooltip: 'نوێکردنەوە',
                    onPressed: _busy ? null : _loadAll,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null) ...[
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.center,
                child: TextButton.icon(
                  onPressed: _busy ? null : _loadAll,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('دووبارە هەوڵبدەوە'),
                ),
              ),
            ] else ...[
              if (status?.active == true) ...[
                Text(
                  'ئامێری چالاک: ${status!.deviceCount}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if ((status.latestStatus ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'دۆخی دوایین ناردن: ${status.latestStatus}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ] else
                const Text(
                  'هێشتا هیچ ئامێرێک پەیوەست نییە',
                  textAlign: TextAlign.center,
                ),
              if ((status?.activeLinkCount ?? 0) > 0) ...[
                const SizedBox(height: 6),
                Text(
                  'QR لینکی چالاک: ${status!.activeLinkCount}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _busy ? null : _showQr,
                icon: const Icon(Icons.qr_code_2_rounded),
                label: const Text('QR ـی ئاگادارکردنەوە'),
              ),
              if (status?.active == true) ...[
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _sendManual,
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('ناردنی ئاگاداری'),
                ),
              ],
              if (canRevoke) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _revokeAll,
                  icon: const Icon(Icons.link_off_rounded),
                  label: const Text('هەموو لینک و ئامێرەکان ڕابگرە'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'مێژووی ئاگادارکردنەوەکان',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'نوێکردنەوەی مێژوو',
                    onPressed: _busy ? null : _loadHistory,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              if (_historyLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (_historyError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _historyError!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                )
              else if (_history.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'هێشتا هیچ ئاگادارکردنەوەیەک تۆمار نەکراوە',
                    textAlign: TextAlign.center,
                  ),
                )
              else
                ..._history.take(10).map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: Icon(_statusIcon(item.status)),
                        title: Text(
                          item.message?.trim().isNotEmpty == true
                              ? item.message!
                              : _eventLabel(item.eventType),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(_historyDetail(item)),
                        trailing: item.canRetry && status?.active == true
                            ? TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _retryNotification(item),
                                child: const Text('دووبارە ناردنەوە'),
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
