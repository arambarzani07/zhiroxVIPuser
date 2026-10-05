import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zhirox/services/a11_camera_service.dart';
import 'package:zhirox/services/pb_service.dart';

class A11VideoJob {
  const A11VideoJob({
    required this.jobId,
    required this.marketId,
    required this.sourceType,
    required this.sourceId,
    required this.transactionAt,
    required this.attemptGeneration,
    required this.attemptToken,
  });

  final String jobId;
  final String marketId;
  final String sourceType;
  final String sourceId;
  final DateTime transactionAt;
  final int attemptGeneration;
  final String attemptToken;

  factory A11VideoJob.fromJson(Map<String, dynamic> json) {
    return A11VideoJob(
      jobId: json['job_id']?.toString() ?? '',
      marketId: json['market_id']?.toString() ?? '',
      sourceType: json['source_type']?.toString() ?? '',
      sourceId: json['source_id']?.toString() ?? '',
      transactionAt: DateTime.parse(json['transaction_at'].toString()),
      attemptGeneration: (json['attempt_generation'] as num?)?.toInt() ?? 0,
      attemptToken: json['attempt_token']?.toString() ?? '',
    );
  }

  bool get valid =>
      jobId.isNotEmpty &&
      marketId.isNotEmpty &&
      sourceType.isNotEmpty &&
      sourceId.isNotEmpty &&
      attemptToken.isNotEmpty;
}

/// Keeps the A11 buffer warm and consumes only `a11_local_rtsp` video jobs.
///
/// Authentication and tenant authorization are enforced again in the database
/// RPCs. The timer is only an on-device scheduler; it is not trusted as an
/// authorization boundary.
class A11CameraCoordinator {
  A11CameraCoordinator._();

  static final A11CameraCoordinator instance = A11CameraCoordinator._();

  Timer? _timer;
  bool _busy = false;
  String? _lastUserId;
  String? _marketId;
  String? _role;
  bool _activationChecked = false;
  DateTime _lastBufferCheck = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> start() async {
    await PBService.ensureInitialized();
    _timer ??= Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_tick()),
    );
    await _tick();
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _lastUserId = null;
    _marketId = null;
    _role = null;
    _activationChecked = false;
    await A11CameraService.instance.stopBuffer();
  }

  Future<void> onCameraConfigChanged() async {
    _activationChecked = false;
    await A11CameraService.instance.restartBuffer();
    await _tick();
  }

  Future<void> _tick() async {
    if (_busy) return;
    _busy = true;
    try {
      final camera = A11CameraService.instance;
      final localConfig = await camera.loadConfig();
      if (!localConfig.enabled || localConfig.password.isEmpty) return;

      if (DateTime.now().difference(_lastBufferCheck) >
          const Duration(seconds: 10)) {
        _lastBufferCheck = DateTime.now();
        await camera.ensureBufferRunning();
      }

      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) {
        _lastUserId = null;
        _marketId = null;
        _role = null;
        _activationChecked = false;
        return;
      }

      if (_lastUserId != user.id || _marketId == null) {
        final profile = await client
            .from('profiles')
            .select('id,role,admin_id')
            .eq('id', user.id)
            .single();
        _lastUserId = user.id;
        _role = profile['role']?.toString() ?? '';
        _marketId = _role == 'admin'
            ? profile['id']?.toString()
            : profile['admin_id']?.toString();
        _activationChecked = false;
      }

      final marketId = _marketId;
      if (marketId == null || marketId.isEmpty) return;

      var providerActive = await camera.isProviderActive(marketId);
      if (!providerActive && _role == 'admin' && !_activationChecked) {
        _activationChecked = true;
        // Never switch production away from the old provider unless this
        // exact phone proves that it can decode the configured RTSP stream.
        final reachable = await camera.testConnection();
        if (reachable) {
          await camera.activateProvider(marketId);
          providerActive = await camera.isProviderActive(marketId);
        }
      }
      if (!providerActive) return;

      final raw = await client.rpc('a11_video_claim_service');
      if (raw is! List || raw.isEmpty) return;
      final first = raw.first;
      if (first is! Map) return;
      final job = A11VideoJob.fromJson(Map<String, dynamic>.from(first));
      if (!job.valid || job.marketId != marketId) return;

      try {
        await camera.captureUploadFinalize(
          jobId: job.jobId,
          attemptToken: job.attemptToken,
          marketId: job.marketId,
          sourceType: job.sourceType,
          sourceId: job.sourceId,
          transactionAt: job.transactionAt,
          attemptGeneration: job.attemptGeneration,
        );
      } catch (error) {
        await camera.failJob(
          jobId: job.jobId,
          attemptToken: job.attemptToken,
          error: error,
        );
      }
    } catch (_) {
      // The coordinator is self-healing. The next timer pass retries local
      // reachability/auth lookup without affecting transaction creation.
    } finally {
      _busy = false;
    }
  }
}
