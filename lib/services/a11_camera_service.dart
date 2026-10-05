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

class A11CapturedClip {
  const A11CapturedClip({
    required this.file,
    required this.transactionAt,
    required this.clipStartAt,
    required this.clipEndAt,
    required this.durationSeconds,
  });

  final File file;
  final DateTime transactionAt;
  final DateTime clipStartAt;
  final DateTime clipEndAt;
  final double durationSeconds;
}

class A11UploadResult {
  const A11UploadResult({
    required this.objectPath,
    required this.byteSize,
    required this.durationSeconds,
  });

  final String objectPath;
  final int byteSize;
  final double durationSeconds;
}

/// On-device recorder for the O-KAM/A11 camera.
///
/// The recorder keeps a small MPEG-TS ring buffer on the phone while ZHIROX is
/// in use. When a transaction is saved it keeps 15 seconds before and 15
/// seconds after the database creation instant, remuxes those segments into a
/// normal MP4, uploads the MP4 to Supabase Storage and finalizes the fenced
/// evidence job. No NVR, Windows gateway or paid cloud VM is required.
class A11CameraService {
  A11CameraService._();

  static final A11CameraService instance = A11CameraService._();

  static const _storage = FlutterSecureStorage();
  static const _keyEnabled = 'a11_camera_enabled';
  static const _keyHost = 'a11_camera_host';
  static const _keyPort = 'a11_camera_port';
  static const _keyUsername = 'a11_camera_username';
  static const _keyPassword = 'a11_camera_password';
  static const _keyPath = 'a11_camera_path';

  static const int _segmentSeconds = 5;
  static const int _segmentCount = 24; // about two minutes of safety buffer

  int? _bufferSessionId;
  Directory? _bufferDirectory;
  bool _starting = false;

  Future<A11CameraConfig> loadConfig() async {
    final values = await Future.wait([
      _storage.read(key: _keyEnabled),
      _storage.read(key: _keyHost),
      _storage.read(key: _keyPort),
      _storage.read(key: _keyUsername),
      _storage.read(key: _keyPassword),
      _storage.read(key: _keyPath),
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
    bool enabled = true,
    String host = '192.168.1.16',
    int port = 10554,
    String username = 'admin',
    required String password,
    String path = '/tcp/av0_0',
  }) async {
    if (host.trim().isEmpty) throw ArgumentError('Camera host is required');
    if (port < 1 || port > 65535) throw ArgumentError('Invalid camera port');
    if (username.trim().isEmpty) throw ArgumentError('Camera username is required');
    if (password.isEmpty) throw ArgumentError('Camera password is required');

    await _storage.write(key: _keyEnabled, value: enabled.toString());
    await _storage.write(key: _keyHost, value: host.trim());
    await _storage.write(key: _keyPort, value: port.toString());
    await _storage.write(key: _keyUsername, value: username.trim());
    await _storage.write(key: _keyPassword, value: password);
    await _storage.write(
      key: _keyPath,
      value: path.startsWith('/') ? path : '/$path',
    );

    await restartBuffer();
  }

  Future<void> disable() async {
    await _storage.write(key: _keyEnabled, value: 'false');
    await stopBuffer();
  }

  Future<bool> testConnection() async {
    final config = await loadConfig();
    if (!config.enabled || config.password.isEmpty) return false;

    final session = await FFmpegKit.executeWithArguments([
      '-hide_banner',
      '-loglevel',
      'error',
      '-rtsp_transport',
      'tcp',
      '-rw_timeout',
      '7000000',
      '-i',
      config.rtspUrl,
      '-map',
      '0:v:0',
      '-t',
      '1',
      '-an',
      '-f',
      'null',
      '-',
    ]);
    return ReturnCode.isSuccess(await session.getReturnCode());
  }

  Future<bool> isProviderActive(String marketId) async {
    await PBService.ensureInitialized();
    final row = await Supabase.instance.client
        .from('hikvision_market_config')
        .select('capture_provider,enabled,auto_capture')
        .eq('market_id', marketId)
        .maybeSingle();
    return row != null &&
        row['capture_provider'] == 'a11_local_rtsp' &&
        row['enabled'] == true &&
        row['auto_capture'] == true;
  }

  /// Admin-only through the existing RLS policy. This is called only after a
  /// local RTSP test succeeds on the phone.
  Future<void> activateProvider(String marketId) async {
    await PBService.ensureInitialized();
    await Supabase.instance.client
        .from('hikvision_market_config')
        .update({'capture_provider': 'a11_local_rtsp'})
        .eq('market_id', marketId);
  }

  Future<Directory> _getBufferDirectory() async {
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

    final dir = await _getBufferDirectory();
    final files = await dir
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.ts'))
        .cast<File>()
        .toList();

    DateTime? newest;
    for (final file in files) {
      final modified = await file.lastModified();
      if (newest == null || modified.isAfter(newest)) newest = modified;
    }

    final fresh = newest != null &&
        DateTime.now().difference(newest).inSeconds <= (_segmentSeconds * 3);
    if (_bufferSessionId != null && fresh) return;

    _starting = true;
    try {
      if (_bufferSessionId != null) {
        await FFmpegKit.cancel(_bufferSessionId);
        _bufferSessionId = null;
      }

      for (final entity in await dir.list().toList()) {
        if (entity is File &&
            (entity.path.endsWith('.ts') || entity.path.endsWith('.txt'))) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }

      final outputPattern = '${dir.path}/segment_%03d.ts';
      final session = await FFmpegKit.executeWithArgumentsAsync([
        '-hide_banner',
        '-loglevel',
        'warning',
        '-rtsp_transport',
        'tcp',
        '-rw_timeout',
        '12000000',
        '-i',
        config.rtspUrl,
        '-map',
        '0:v:0',
        '-an',
        '-c:v',
        'copy',
        '-f',
        'segment',
        '-segment_format',
        'mpegts',
        '-segment_time',
        _segmentSeconds.toString(),
        '-segment_wrap',
        _segmentCount.toString(),
        '-reset_timestamps',
        '1',
        outputPattern,
      ]);
      _bufferSessionId = session.getSessionId();
    } finally {
      _starting = false;
    }
  }

  Future<void> restartBuffer() async {
    await stopBuffer();
    await ensureBufferRunning();
  }

  Future<void> stopBuffer() async {
    final id = _bufferSessionId;
    _bufferSessionId = null;
    if (id != null) {
      try {
        await FFmpegKit.cancel(id);
      } catch (_) {}
    }
  }

  Future<A11CapturedClip> captureAroundTransaction(
    DateTime transactionAt, {
    int preSeconds = 15,
    int postSeconds = 15,
  }) async {
    await ensureBufferRunning();

    final desiredEnd = transactionAt.add(Duration(seconds: postSeconds));
    final remaining = desiredEnd.difference(DateTime.now());
    if (!remaining.isNegative) {
      await Future<void>.delayed(remaining + const Duration(milliseconds: 750));
    }

    final dir = await _getBufferDirectory();
    final candidates = await dir
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.ts'))
        .cast<File>()
        .toList();
    if (candidates.isEmpty) {
      throw StateError('a11_buffer_empty');
    }

    final withTimes = <({File file, DateTime modified})>[];
    for (final file in candidates) {
      withTimes.add((file: file, modified: await file.lastModified()));
    }
    withTimes.sort((a, b) => a.modified.compareTo(b.modified));

    final windowStart = transactionAt.subtract(Duration(seconds: preSeconds));
    final windowEnd = desiredEnd;
    final selected = withTimes.where((entry) {
      final approxStart = entry.modified.subtract(
        const Duration(seconds: _segmentSeconds + 2),
      );
      final approxEnd = entry.modified.add(const Duration(seconds: 1));
      return approxEnd.isAfter(windowStart) && approxStart.isBefore(windowEnd);
    }).toList();

    if (selected.length < 4) {
      throw StateError('a11_insufficient_prebuffer');
    }

    final concatFile = File('${dir.path}/concat_${transactionAt.microsecondsSinceEpoch}.txt');
    final concatBody = selected
        .map((entry) => "file '${entry.file.path.replaceAll("'", "'\\''")}'")
        .join('\n');
    await concatFile.writeAsString('$concatBody\n', flush: true);

    final firstApproxStart = selected.first.modified.subtract(
      const Duration(seconds: _segmentSeconds),
    );
    final offset = math.max(
      0.0,
      windowStart.difference(firstApproxStart).inMilliseconds / 1000.0,
    );
    final expectedSeconds = preSeconds + postSeconds;
    final output = File(
      '${dir.path}/evidence_${transactionAt.microsecondsSinceEpoch}.mp4',
    );
    if (await output.exists()) await output.delete();

    final remux = await FFmpegKit.executeWithArguments([
      '-hide_banner',
      '-loglevel',
      'error',
      '-f',
      'concat',
      '-safe',
      '0',
      '-i',
      concatFile.path,
      '-ss',
      offset.toStringAsFixed(3),
      '-t',
      expectedSeconds.toString(),
      '-an',
      '-c:v',
      'copy',
      '-avoid_negative_ts',
      'make_zero',
      '-movflags',
      '+faststart',
      output.path,
    ]);

    if (!ReturnCode.isSuccess(await remux.getReturnCode()) ||
        !await output.exists() ||
        await output.length() < 20000) {
      throw StateError('a11_mp4_remux_failed');
    }

    final duration = await _probeDuration(output.path);
    if (duration < 27.5 || duration > 32.5) {
      throw StateError('a11_quality_gate_duration_${duration.toStringAsFixed(2)}');
    }

    try {
      await concatFile.delete();
    } catch (_) {}

    return A11CapturedClip(
      file: output,
      transactionAt: transactionAt,
      clipStartAt: windowStart,
      clipEndAt: windowEnd,
      durationSeconds: duration,
    );
  }

  Future<A11UploadResult> captureUploadFinalize({
    required String jobId,
    required String attemptToken,
    required String marketId,
    required String sourceType,
    required String sourceId,
    required DateTime transactionAt,
    required int attemptGeneration,
  }) async {
    await PBService.ensureInitialized();
    if (!await isProviderActive(marketId)) {
      throw StateError('a11_provider_not_active');
    }

    final clip = await captureAroundTransaction(transactionAt);
    final bytes = await clip.file.readAsBytes();
    final utc = transactionAt.toUtc();
    String two(int value) => value.toString().padLeft(2, '0');
    final nonce = DateTime.now().microsecondsSinceEpoch;
    final objectPath = '$marketId/${utc.year}/${two(utc.month)}/${two(utc.day)}/'
        '$sourceType/$sourceId-a$attemptGeneration-$nonce.mp4';

    await Supabase.instance.client.storage
        .from('transaction-camera-clips')
        .uploadBinary(
          objectPath,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'video/mp4',
            upsert: false,
            cacheControl: '3600',
          ),
        );

    final completed = await Supabase.instance.client.rpc(
      'a11_video_complete_v2_service',
      params: {
        'p_job_id': jobId,
        'p_attempt_token': attemptToken,
        'p_object_path': objectPath,
        'p_byte_size': bytes.length,
        'p_duration_seconds': clip.durationSeconds.round(),
        'p_content_sha256': null,
        'p_playback_metadata': {
          'provider': 'a11_local_rtsp',
          'exact_trim': true,
          'requested_start': clip.clipStartAt.toUtc().toIso8601String(),
          'requested_end': clip.clipEndAt.toUtc().toIso8601String(),
          'segment_start': clip.clipStartAt.toUtc().toIso8601String(),
          'segment_end': clip.clipEndAt.toUtc().toIso8601String(),
          'on_device_capture': true,
          'attempt_generation': attemptGeneration,
        },
      },
    );

    if (completed != true) {
      throw StateError('a11_finalize_rejected');
    }

    try {
      await clip.file.delete();
    } catch (_) {}

    return A11UploadResult(
      objectPath: objectPath,
      byteSize: bytes.length,
      durationSeconds: clip.durationSeconds,
    );
  }

  Future<void> failJob({
    required String jobId,
    required String attemptToken,
    required Object error,
  }) async {
    await PBService.ensureInitialized();
    final text = error.toString();
    final retryable = !text.contains('a11_insufficient_prebuffer') &&
        !text.contains('a11_quality_gate_duration') &&
        !text.contains('a11_provider_not_active');
    try {
      await Supabase.instance.client.rpc(
        'a11_video_fail_v2_service',
        params: {
          'p_job_id': jobId,
          'p_attempt_token': attemptToken,
          'p_error': text.length > 900 ? text.substring(0, 900) : text,
          'p_retryable': retryable,
        },
      );
    } catch (_) {}
  }

  Future<double> _probeDuration(String filePath) async {
    final session = await FFprobeKit.getMediaInformation(filePath);
    final information = await session.getMediaInformation();
    final raw = information?.getDuration();
    return double.tryParse(raw ?? '') ?? 0;
  }
}
