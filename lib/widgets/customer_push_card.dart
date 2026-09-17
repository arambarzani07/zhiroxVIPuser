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
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStatus();
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
          return AlertDialog(
            title: const Text('QR ـی ئاگادارکردنەوە'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  QrImageView(
                    key: ValueKey<String>(url),
                    data: url,
                    version: QrVersions.auto,
                    size: 240,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'ئەم QR ـە تەنها یەکجار بەکاردێت و دوای ١٥ خولەک بەسەر دەچێت.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('داخستن'),
              ),
            ],
          );
        },
      );
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

  Future<void> _revokeAll() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('پچڕاندنەوەی ئاگادارکردنەوەکان'),
        content: const Text('دڵنیایت لە پچڕاندنەوەی هەموو ئامێرەکان؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('نەخێر'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('بەڵێ، پچڕێنەوە'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final count = await widget.gateway.revokeAll(widget.customerId);
      if (!mounted) return;
      await _loadStatus();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$count ئامێر پچڕێندرایەوە')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('نەتوانرا ئامێرەکان پچڕێنرێنەوە'),
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
                    onPressed: _busy ? null : _loadStatus,
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
                  onPressed: _busy ? null : _loadStatus,
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
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _busy ? null : _showQr,
                icon: const Icon(Icons.qr_code_2_rounded),
                label: const Text('QR ـی ئاگادارکردنەوە'),
              ),
              if (status?.active == true) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _revokeAll,
                  icon: const Icon(Icons.link_off_rounded),
                  label: const Text('هەموو ئامێرەکان پچڕێنەوە'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
