import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zhirox/services/pb_service.dart';

class A11CameraConfig {
  const A11CameraConfig({
    required this.enabled,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.path,
  });
  final bool enabled;
  final String host;
  final int port;
  final String username;
  final String password;
  final String path;

  String get rtspUrl => Uri(
        scheme: 'rtsp',
        userInfo: '$username:$password',
        host: host,
        port: port,
        path: path.startsWith('/') ? path : '/$path',
      ).toString();
}

class A11CameraService {
  A11CameraService._();
  static final A11CameraService instance = A11CameraService._();
  static const _storage = FlutterSecureStorage();
  static const _segmentSeconds = 5;
  static const _segmentCount = 24;
  int? _bufferSessionId;
  Directory? _bufferDirectory;
  bool _starting = false;

  Future<A11CameraConfig> loadConfig() async {
    final values = await Future.wait([
      _storage.read(key: 'a11_camera_enabled'),
      _storage.read(key: 'a11_camera_host'),
      _storage.read(key: 'a11_camera_port'),
      _storage.read(key: 'a11_camera_username'),
      _storage.read(key: 'a11_camera_password'),
      _storage.read(key: 'a11_camera_path'),
    ]);
    return A11CameraConfig(
      enabled: values[0] == 'true',
      host: (values[1] ?? '192.168.1.16').trim(),
      port: int.tryParse(values[2] ?? '') ?? 10554,
      username: (values[3] ?? 'admin').trim(),
      password: values[4] ?? '',
      path: (values[5] ?? '/tcp/av0_0').trim(),
    );
  }

  Future<void> saveConfig({
    required String password,
    String host = '192.168.1.16',
    int port = 10554,
    String username = 'admin',
    String path = '/tcp/av0_0',
  }) async {
    if (password.isEmpty) throw ArgumentError('Camera password is required');
    await _storage.write(key: 'a11_camera_enabled', value: 'true');
    await _storage.write(key: 'a11_camera_host', value: host.trim());
    await _storage.write(key: 'a11_camera_port', value: port.toString());
    await _storage.write(key: 'a11_camera_username', value: username.trim());
    await _storage.write(key: 'a11_camera_password', value: password);
    await _storage.write(
      key: 'a11_camera_path',
      value: path.startsWith('/') ? path : '/$path',
    );
  }

  Future<bool> testConnection() async {
    final config = await loadConfig();
    if (!config.enabled || config.password.isEmpty) return false;
    await stopBuffer();
    final session = await FFmpegKit.executeWithArguments([
      '-hide_banner', '-loglevel', 'error', '-rtsp_transport', 'tcp',
      '-rw_timeout', '7000000', '-i', config.rtspUrl,
      '-map', '0:v:0', '-t', '1', '-an', '-f', 'null', '-'
    ]);
    final ok = ReturnCode.isSuccess(await session.getReturnCode());
    if (ok) unawaited(ensureBufferRunning());
    return ok;
  }

  Future<void> setProvider(String marketId, String provider) async {
    if (provider != 'a11_local_rtsp' && provider != 'local_gateway') {
      throw ArgumentError('Unsupported provider');
    }
    await PBService.ensureInitialized();
    await Supabase.instance.client
        .from('hikvision_market_config')
        .update({'capture_provider': provider})
        .eq('market_id', marketId);
  }

  Future<String?> currentProvider(String marketId) async {
    await PBService.ensureInitialized();
    final row = await Supabase.instance.client
        .from('hikvision_market_config')
        .select('capture_provider')
        .eq('market_id', marketId)
        .maybeSingle();
    return row?['capture_provider']?.toString();
  }

  Future<Directory> _dir() async {
    if (_bufferDirectory != null) return _bufferDirectory!;
    final temp = await getTemporaryDirectory();
    final dir = Directory('${temp.path}/zhirox_a11_buffer');
    await dir.create(recursive: true);
    _bufferDirectory = dir;
    return dir;
  }

  Future<void> ensureBufferRunning() async {
    if (_starting) return;
    final config = await loadConfig();
    if (!config.enabled || config.password.isEmpty) return;
    final dir = await _dir();
    if (_bufferSessionId != null) {
      final files = await dir.list().where((e) => e is File && e.path.endsWith('.ts')).cast<File>().toList();
      DateTime? newest;
      for (final file in files) {
        final modified = await file.lastModified();
        if (newest == null || modified.isAfter(newest)) newest = modified;
      }
      if (newest != null && DateTime.now().difference(newest).inSeconds <= 15) return;
      await stopBuffer();
    }
    _starting = true;
    try {
      for (final entity in await dir.list().toList()) {
        if (entity is File && (entity.path.endsWith('.ts') || entity.path.endsWith('.txt'))) {
          try { await entity.delete(); } catch (_) {}
        }
      }
      final session = await FFmpegKit.executeWithArgumentsAsync([
        '-hide_banner', '-loglevel', 'warning', '-rtsp_transport', 'tcp',
        '-rw_timeout', '12000000', '-i', config.rtspUrl,
        '-map', '0:v:0', '-an', '-c:v', 'copy', '-f', 'segment',
        '-segment_format', 'mpegts', '-segment_time', '$_segmentSeconds',
        '-segment_wrap', '$_segmentCount', '-reset_timestamps', '1',
        '${dir.path}/segment_%03d.ts'
      ]);
      _bufferSessionId = session.getSessionId();
    } finally {
      _starting = false;
    }
  }

  Future<void> stopBuffer() async {
    final id = _bufferSessionId;
    _bufferSessionId = null;
    if (id != null) {
      try { await FFmpegKit.cancel(id); } catch (_) {}
    }
  }

  Future<File> _capture(DateTime transactionAt) async {
    await ensureBufferRunning();
    final desiredEnd = transactionAt.add(const Duration(seconds: 15));
    final wait = desiredEnd.difference(DateTime.now());
    if (!wait.isNegative) await Future<void>.delayed(wait + const Duration(milliseconds: 800));

    final dir = await _dir();
    final files = await dir.list().where((e) => e is File && e.path.endsWith('.ts')).cast<File>().toList();
    if (files.isEmpty) throw StateError('a11_buffer_empty');
    final timed = <({File file, DateTime modified})>[];
    for (final file in files) {
      timed.add((file: file, modified: await file.lastModified()));
    }
    timed.sort((a, b) => a.modified.compareTo(b.modified));
    final start = transactionAt.subtract(const Duration(seconds: 15));
    final selected = timed.where((entry) {
      final approxStart = entry.modified.subtract(const Duration(seconds: 7));
      return entry.modified.add(const Duration(seconds: 1)).isAfter(start) && approxStart.isBefore(desiredEnd);
    }).toList();
    if (selected.length < 4) throw StateError('a11_insufficient_prebuffer');

    final concat = File('${dir.path}/concat_${transactionAt.microsecondsSinceEpoch}.txt');
    await concat.writeAsString('${selected.map((e) => "file '${e.file.path.replaceAll("'", "'\\''")}'").join('\n')}\n');
    final firstStart = selected.first.modified.subtract(const Duration(seconds: _segmentSeconds));
    final offset = math.max(0.0, start.difference(firstStart).inMilliseconds / 1000.0);
    final output = File('${dir.path}/evidence_${transactionAt.microsecondsSinceEpoch}.mp4');
    final remux = await FFmpegKit.executeWithArguments([
      '-hide_banner', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', concat.path,
      '-ss', offset.toStringAsFixed(3), '-t', '30', '-an', '-c:v', 'copy',
      '-avoid_negative_ts', 'make_zero', '-movflags', '+faststart', output.path
    ]);
    if (!ReturnCode.isSuccess(await remux.getReturnCode()) || !await output.exists() || await output.length() < 20000) {
      throw StateError('a11_mp4_remux_failed');
    }
    final probe = await FFprobeKit.getMediaInformation(output.path);
    final info = await probe.getMediaInformation();
    final duration = double.tryParse(info?.getDuration() ?? '') ?? 0;
    if (duration < 27.5 || duration > 32.5) throw StateError('a11_quality_gate_duration');
    try { await concat.delete(); } catch (_) {}
    return output;
  }

  Future<void> captureUploadFinalize({
    required String jobId,
    required String attemptToken,
    required String marketId,
    required String sourceType,
    required String sourceId,
    required DateTime transactionAt,
    required int attemptGeneration,
  }) async {
    final file = await _capture(transactionAt);
    final bytes = await file.readAsBytes();
    final utc = transactionAt.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    final path = '$marketId/${utc.year}/${two(utc.month)}/${two(utc.day)}/$sourceType/$sourceId-a$attemptGeneration-${DateTime.now().microsecondsSinceEpoch}.mp4';
    await Supabase.instance.client.storage.from('transaction-camera-clips').uploadBinary(
      path, bytes,
      fileOptions: const FileOptions(contentType: 'video/mp4', upsert: false, cacheControl: '3600'),
    );
    final completed = await Supabase.instance.client.rpc('a11_video_complete_v2_service', params: {
      'p_job_id': jobId,
      'p_attempt_token': attemptToken,
      'p_object_path': path,
      'p_byte_size': bytes.length,
      'p_duration_seconds': 30,
      'p_content_sha256': null,
      'p_playback_metadata': {
        'provider': 'a11_local_rtsp',
        'exact_trim': true,
        'on_device_capture': true,
        'attempt_generation': attemptGeneration,
      },
    });
    if (completed != true) throw StateError('a11_finalize_rejected');
    try { await file.delete(); } catch (_) {}
  }

  Future<void> failJob({required String jobId, required String attemptToken, required Object error}) async {
    try {
      await Supabase.instance.client.rpc('a11_video_fail_v2_service', params: {
        'p_job_id': jobId,
        'p_attempt_token': attemptToken,
        'p_error': error.toString(),
        'p_retryable': true,
      });
    } catch (_) {}
  }
}
