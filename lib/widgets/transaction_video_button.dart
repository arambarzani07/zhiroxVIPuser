import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/widgets/transaction_video_player.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/services/transaction_video_service.dart';

/// Load evidence only when opened, so scrolling a financial history does not
/// create a request for every transaction. Playback currently requires admin.
class TransactionVideoButton extends StatelessWidget {
  const TransactionVideoButton({
    super.key,
    required this.sourceType,
    required this.sourceId,
  });

  final String sourceType;
  final String sourceId;

  @override
  Widget build(BuildContext context) {
    if (context.watch<AuthProvider>().userRole != 'admin') {
      return const SizedBox.shrink();
    }
    return TextButton.icon(
      icon: const Icon(Icons.videocam_outlined, size: 18),
      label: const Text('ڤیدیۆی مامەڵە'),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) =>
            _TransactionVideoPanel(sourceType: sourceType, sourceId: sourceId),
      ),
    );
  }
}

class _TransactionVideoPanel extends StatefulWidget {
  const _TransactionVideoPanel({
    required this.sourceType,
    required this.sourceId,
  });
  final String sourceType;
  final String sourceId;

  @override
  State<_TransactionVideoPanel> createState() => _TransactionVideoPanelState();
}

class _TransactionVideoPanelState extends State<_TransactionVideoPanel> {
  Map<String, dynamic>? _evidence;
  bool _loading = true;
  bool _opening = false;
  bool _rebuilding = false;
  String? _error;

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
      final evidence = await TransactionVideoService.status(
        widget.sourceType,
        widget.sourceId,
      );
      if (!mounted) {
        return;
      }
      setState(() => _evidence = evidence);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(
        () => _error =
            'دۆخی کلیپ وەرنەگیرا. ئینتەرنێت بپشکنەوە و دووبارە هەوڵ بدە.',
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _open() async {
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => TransactionVideoPlayer(
            sourceType: widget.sourceType,
            sourceId: widget.sourceId,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(
        () => _error =
            'کلیپەکە نەکرایەوە. دۆخەکە نوێ بکەرەوە و دووبارە هەوڵ بدە.',
      );
    } finally {
      if (mounted) {
        setState(() => _opening = false);
      }
    }
  }

  Future<void> _rebuild() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('دروستکردنەوەی کلیپ'),
        content: const Text(
          'Gateway دووبارە کلیپی ئەم مامەڵەیە وەردەگرێت. ئەگەر تۆمار لە NVR ماوە و کاتەکە دروست بێت، کلیپی نوێ جێگای ئەمە دەگرێتەوە.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('پاشگەزبوونەوە'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('داواکردن'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _rebuilding = true);
    try {
      await TransactionVideoService.rebuild(widget.sourceType, widget.sourceId);
      await _load();
    } catch (_) {
      if (mounted)
        setState(
          () => _error = 'داواکاری سەرکەوتوو نەبوو؛ دۆخ نوێ بکەرەوە و دڵنیابە Gatewayی نوێ چالاکە.',
        );
    } finally {
      if (mounted) setState(() => _rebuilding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _evidence?['status']?.toString();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'ڤیدیۆی مامەڵە',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error == null) ...[
              Text(TransactionVideoService.statusLabel(status)),
              if (status == 'ready')
                Text(TransactionVideoService.clockLabel(_evidence)),
              if (_evidence?['integrity'] is Map &&
                  _evidence!['integrity']['duplicate_warning'] == true) ...[
                const SizedBox(height: 12),
                const Text(
                  'ئاگاداری: ئەم فایلە ڤیدیۆیە بۆ مامەڵەیەکی تر لە کاتێکی جیاوازیش بەستراوە. دیمەن و کاتی مامەڵەکە لە Playback پشتڕاست بکەرەوە.',
                  style: TextStyle(
                    color: Colors.deepOrange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
              if (status == 'ready' &&
                  _evidence?['integrity'] is Map &&
                  _evidence!['integrity']['checked'] != true)
                const Text('پشکنینی دووبارەبوونەوەی کلیپ بەردەست نییە.'),
              if (_evidence?['channel_id'] != null) ...[
                const SizedBox(height: 8),
                Text('کەناڵی کامێرا: ${_evidence!['channel_id']}'),
              ],
              if (status == 'ready') ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _opening ? null : _open,
                  icon: const Icon(Icons.play_circle_outline),
                  label: Text(_opening ? 'دەکرێتەوە…' : 'بینینی ڤیدیۆ'),
                ),
              ],
            ],
            if (!_loading && _evidence != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed:
                    _opening || _rebuilding || _evidence?['can_rebuild'] != true
                    ? null
                    : _rebuild,
                icon: const Icon(Icons.restart_alt),
                label: Text(_rebuilding ? 'داواکاری…' : 'دروستکردنەوەی کلیپ'),
              ),
              if (_evidence?['can_rebuild'] != true)
                const Text(
                  'دروستکردنەوە پێویستی بە Gatewayی نوێی چالاک هەیە؛ لە کاتی کارکردنی کلیپیش چاوەڕوان بە.',
                ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loading || _opening || _rebuilding ? null : _load,
              icon: const Icon(Icons.refresh),
              label: const Text('نوێکردنەوەی دۆخی کلیپ'),
            ),
          ],
        ),
      ),
    );
  }
}
