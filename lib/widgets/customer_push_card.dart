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
    final isDark = theme.brightness == Brightness.dark;
    final status = _status;
    final canRevoke =
        status != null && (status.hasActiveLink || status.deviceCount > 0);
    final surface = isDark ? theme.colorScheme.surface : Colors.white;
    final subtle = isDark
        ? Colors.white.withValues(alpha: 0.045)
        : const Color(0xFFF8FAFC);
    final border = theme.colorScheme.outlineVariant.withValues(
      alpha: isDark ? 0.8 : 0.72,
    );

    Widget metric({
      required IconData icon,
      required String text,
      required Color accent,
    }) {
      return Expanded(
        child: Container(
          minHeight: 52,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: subtle,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 17, color: accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    Icons.notifications_active_outlined,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ئاگادارکردنەوەی کڕیار',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        status?.active == true
                            ? 'پەیوەندی چالاکە و ئامێرەکان ئامادەن'
                            : 'QR و پەیوەندی ئاگادارکردنەوە لێرە بەڕێوەببە',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 10.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_loading && _error == null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: (status?.active == true
                              ? Colors.green
                              : theme.colorScheme.outline)
                          .withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      status?.active == true ? 'چالاک' : 'ناچالاک',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: status?.active == true
                            ? Colors.green.shade700
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  SizedBox(
                    width: 34,
                    height: 34,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      tooltip: 'نوێکردنەوە',
                      onPressed: _busy ? null : _loadAll,
                      icon: const Icon(Icons.refresh_rounded, size: 19),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 11),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                ),
              )
            else if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 11.5,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.center,
                child: TextButton.icon(
                  onPressed: _busy ? null : _loadAll,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('دووبارە هەوڵبدەوە'),
                ),
              ),
            ] else ...[
              Row(
                children: [
                  metric(
                    icon: Icons.smartphone_rounded,
                    text: 'ئامێری چالاک: ${status?.deviceCount ?? 0}',
                    accent: Colors.green,
                  ),
                  const SizedBox(width: 8),
                  metric(
                    icon: Icons.qr_code_2_rounded,
                    text: 'QR لینکی چالاک: ${status?.activeLinkCount ?? 0}',
                    accent: theme.colorScheme.primary,
                  ),
                ],
              ),
              if ((status?.latestStatus ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: subtle,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        size: 16,
                        color: Colors.green.shade700,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          'دۆخی دوایین ناردن: ${status!.latestStatus}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (status?.active != true &&
                  (status?.activeLinkCount ?? 0) == 0) ...[
                const SizedBox(height: 8),
                Text(
                  'هێشتا هیچ ئامێرێک پەیوەست نییە',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 11),
              SizedBox(
                height: 44,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _showQr,
                  icon: const Icon(Icons.qr_code_2_rounded, size: 19),
                  label: const Text('QR ـی ئاگادارکردنەوە'),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              if (status?.active == true) ...[
                const SizedBox(height: 7),
                SizedBox(
                  height: 42,
                  child: FilledButton.tonalIcon(
                    onPressed: _busy ? null : _sendManual,
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: const Text('ناردنی ئاگاداری'),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
              if (canRevoke) ...[
                const SizedBox(height: 3),
                TextButton.icon(
                  onPressed: _busy ? null : _revokeAll,
                  icon: const Icon(Icons.link_off_rounded, size: 17),
                  label: const Text('هەموو لینک و ئامێرەکان ڕابگرە'),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Divider(height: 1, color: border),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'مێژووی ئاگادارکردنەوەکان',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (_history.isNotEmpty)
                    Container(
                      margin: const EdgeInsetsDirectional.only(end: 3),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: subtle,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${_history.length}',
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      tooltip: 'نوێکردنەوەی مێژوو',
                      onPressed: _busy ? null : _loadHistory,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                    ),
                  ),
                ],
              ),
              if (_historyLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (_historyError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Text(
                    _historyError!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontSize: 11,
                    ),
                  ),
                )
              else if (_history.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'هێشتا هیچ ئاگادارکردنەوەیەک تۆمار نەکراوە',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 10.5),
                  ),
                )
              else
                ..._history.take(10).map(
                  (item) => Container(
                    margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      color: subtle,
                      border: Border.all(color: border),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: ListTile(
                      dense: true,
                      visualDensity: const VisualDensity(
                        horizontal: -2,
                        vertical: -2,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 1,
                      ),
                      leading: Icon(_statusIcon(item.status), size: 19),
                      title: Text(
                        item.message?.trim().isNotEmpty == true
                            ? item.message!
                            : _eventLabel(item.eventType),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        _historyDetail(item),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 9.5),
                      ),
                      trailing: item.canRetry && status?.active == true
                          ? TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _retryNotification(item),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                ),
                              ),
                              child: const Text(
                                'دووبارە ناردنەوە',
                                style: TextStyle(fontSize: 10),
                              ),
                            )
                          : null,
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