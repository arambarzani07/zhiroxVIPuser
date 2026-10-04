import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:zhirox/services/transaction_video_service.dart';

class TransactionVideoPlayer extends StatefulWidget {
  const TransactionVideoPlayer({
    super.key,
    required this.sourceType,
    required this.sourceId,
  });
  final String sourceType;
  final String sourceId;
  @override
  State<TransactionVideoPlayer> createState() => _TransactionVideoPlayerState();
}

class _TransactionVideoPlayerState extends State<TransactionVideoPlayer> {
  VideoPlayerController? _controller;
  Map<String, dynamic>? _evidence;
  bool _loading = true;
  bool _downloading = false;
  String? _error;
  http.Client? _downloadClient;

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
    final previous = _controller;
    _controller = null;
    await previous?.dispose();
    VideoPlayerController? candidate;
    try {
      final data = await TransactionVideoService.playbackDetails(
        widget.sourceType,
        widget.sourceId,
      );
      final uri = TransactionVideoService.playbackUri(data);
      candidate = VideoPlayerController.networkUrl(uri);
      await candidate.initialize().timeout(const Duration(seconds: 30));
      if (!mounted) {
        await candidate.dispose();
        return;
      }
      _controller = candidate;
      setState(
        () => _evidence = data['evidence'] is Map
            ? Map<String, dynamic>.from(data['evidence'])
            : null,
      );
      await candidate.play();
    } catch (_) {
      _controller = null;
      await candidate?.dispose();
      if (mounted) {
        setState(() => _error = 'ڤیدیۆکە نەکرایەوە. دووبارە هەوڵ بدە.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download() async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() {
      _downloading = true;
      _error = null;
    });
    File? file;
    IOSink? sink;
    final client = http.Client();
    _downloadClient = client;
    try {
      // Refresh expiring signed links instead of saving authentication URLs.
      final uri = await TransactionVideoService.playback(
        widget.sourceType,
        widget.sourceId,
      );
      final response = await client
          .send(http.Request('GET', uri))
          .timeout(const Duration(seconds: 30));
      const limit = 100 * 1024 * 1024;
      if (response.statusCode != 200 || (response.contentLength ?? 0) > limit) {
        throw StateError('download_failed');
      }
      final directory = await getTemporaryDirectory();
      final id = widget.sourceId.replaceAll(RegExp('[^a-zA-Z0-9-]'), '');
      file = File(
        '${directory.path}/ZHIROX-$id-${DateTime.now().microsecondsSinceEpoch}.mp4',
      );
      sink = file.openWrite();
      var bytes = 0;
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        bytes += chunk.length;
        if (bytes > limit || !mounted) throw StateError('download_cancelled');
        sink.add(chunk);
      }
      await sink.close();
      sink = null;
      if (bytes == 0) throw StateError('empty_video');
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'video/mp4')],
        subject: 'ڤیدیۆی مامەڵە',
        sharePositionOrigin: origin,
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'داگرتنی ڤیدیۆ سەرکەوتوو نەبوو. دووبارە هەوڵ بدە.',
        );
      }
    } finally {
      await sink?.close();
      client.close();
      _downloadClient = null;
      // Share sheet makes its own copy; leave no transaction media in temp.
      if (file != null && await file.exists()) await file.delete();
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _downloadClient?.close();
    super.dispose();
  }

  String _date(dynamic value) {
    final date = DateTime.tryParse('$value')?.toLocal();
    if (date == null) return 'نادیارە';
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${date.year}/${pad(date.month)}/${pad(date.day)} ${pad(date.hour)}:${pad(date.minute)}:${pad(date.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: const Text('ڤیدیۆی مامەڵە')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (controller != null && !_loading)
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: controller,
              builder: (context, value, child) => Column(
                children: [
                  AspectRatio(
                    aspectRatio: value.aspectRatio > 0
                        ? value.aspectRatio
                        : 16 / 9,
                    child: VideoPlayer(controller),
                  ),
                  if (value.isBuffering) const LinearProgressIndicator(),
                  VideoProgressIndicator(
                    controller,
                    allowScrubbing: true,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: () => value.isPlaying
                            ? controller.pause()
                            : controller.play(),
                        icon: Icon(
                          value.isPlaying
                              ? Icons.pause_circle
                              : Icons.play_circle,
                        ),
                        iconSize: 40,
                      ),
                      Text(
                        '${value.position.inSeconds}s / ${value.duration.inSeconds}s',
                      ),
                      IconButton(
                        onPressed: () =>
                            controller.setVolume(value.volume == 0 ? 1 : 0),
                        icon: Icon(
                          value.volume == 0
                              ? Icons.volume_off
                              : Icons.volume_up,
                        ),
                      ),
                    ],
                  ),
                  if (value.hasError)
                    const Text(
                      'خوێندنەوەی ڤیدیۆ هەڵەی هەیە؛ دووبارە هەوڵ بدە.',
                    ),
                ],
              ),
            ),
          if (_evidence != null) ...[
            Text('کاتی مامەڵە: ${_date(_evidence!['transaction_at'])}'),
            Text('کەناڵی کامێرا: ${_evidence!['channel_id']}'),
            Text(
              'ماوەی داواکراو: ${_date(_evidence!['clip_start_at'])} — ${_date(_evidence!['clip_end_at'])}',
            ),
            const SizedBox(height: 12),
            Text(
              TransactionVideoService.clockLabel(_evidence),
              style: TextStyle(
                color: TransactionVideoService.clockMismatch(_evidence)
                    ? Colors.deepOrange
                    : null,
              ),
            ),
            if (_evidence!['integrity'] is Map &&
                _evidence!['integrity']['duplicate_warning'] == true)
              const Text(
                'ئاگاداری: هەمان فایل بۆ مامەڵەیەکی تر لە کاتی جیاواز بەستراوە.',
                style: TextStyle(color: Colors.deepOrange),
              ),
          ],
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loading || _downloading || controller == null
                ? null
                : _download,
            icon: const Icon(Icons.download),
            label: Text(
              _downloading ? 'داگرتن…' : 'داگرتن / پاشەکەوت لە Files',
            ),
          ),
          OutlinedButton.icon(
            onPressed: _loading || _downloading ? null : _load,
            icon: const Icon(Icons.refresh),
            label: const Text('دووبارە هەوڵدان'),
          ),
        ],
      ),
    );
  }
}
