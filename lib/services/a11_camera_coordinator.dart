import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zhirox/services/a11_camera_service.dart';
import 'package:zhirox/services/pb_service.dart';

class A11CameraCoordinator {
  A11CameraCoordinator._();
  static final A11CameraCoordinator instance = A11CameraCoordinator._();

  Timer? _timer;
  bool _busy = false;
  String? _marketId;
  String? _lastUserId;

  Future<void> start() async {
    await PBService.ensureInitialized();
    _timer ??= Timer.periodic(const Duration(seconds: 2), (_) => unawaited(_tick()));
    await _tick();
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _marketId = null;
    _lastUserId = null;
    await A11CameraService.instance.stopBuffer();
  }

  Future<void> _tick() async {
    if (_busy) return;
    _busy = true;
    try {
      final camera = A11CameraService.instance;
      final config = await camera.loadConfig();
      if (!config.enabled || config.password.isEmpty) return;
      await camera.ensureBufferRunning();

      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return;
      if (_lastUserId != user.id || _marketId == null) {
        final profile = await client
            .from('profiles')
            .select('id,role,admin_id')
            .eq('id', user.id)
            .single();
        _lastUserId = user.id;
        _marketId = profile['role'] == 'admin'
            ? profile['id']?.toString()
            : profile['admin_id']?.toString();
      }
      if (_marketId == null || _marketId!.isEmpty) return;

      final raw = await client.rpc('a11_video_claim_service');
      if (raw is! List || raw.isEmpty || raw.first is! Map) return;
      final row = Map<String, dynamic>.from(raw.first as Map);
      if (row['market_id']?.toString() != _marketId) return;

      final jobId = row['job_id']?.toString() ?? '';
      final token = row['attempt_token']?.toString() ?? '';
      if (jobId.isEmpty || token.isEmpty) return;
      try {
        await camera.captureUploadFinalize(
          jobId: jobId,
          attemptToken: token,
          marketId: row['market_id'].toString(),
          sourceType: row['source_type']?.toString() ?? 'debt',
          sourceId: row['source_id']?.toString() ?? '',
          transactionAt: DateTime.parse(row['transaction_at'].toString()),
          attemptGeneration: (row['attempt_generation'] as num?)?.toInt() ?? 0,
        );
      } catch (error) {
        await camera.failJob(jobId: jobId, attemptToken: token, error: error);
      }
    } catch (_) {
      // Self-healing timer retries without blocking normal ZHIROX operations.
    } finally {
      _busy = false;
    }
  }
}
