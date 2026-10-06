import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';
import 'package:zhirox/main.dart' as legacy;
import 'package:zhirox/screens/admin/camera_source_settings_screen.dart';
import 'package:zhirox/services/a11_camera_coordinator.dart';
import 'package:zhirox/services/connectivity_service.dart';
import 'package:zhirox/services/notification_service.dart';
import 'package:zhirox/services/pb_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await ConnectivityService.instance.init();
  } catch (_) {}
  try {
    await NotificationService.init();
    await NotificationService.requestPermission();
  } catch (_) {}
  try {
    await Workmanager().initialize(legacy.callbackDispatcher);
    await Workmanager().registerPeriodicTask(
      'overdueDebtsCheck',
      'checkOverdueDebts',
      frequency: const Duration(hours: 12),
      constraints: Constraints(networkType: NetworkType.connected),
    );
  } catch (_) {}
  try {
    await PBService.ensureInitialized();
  } catch (_) {}
  unawaited(A11CameraCoordinator.instance.start());
  runApp(const ZhiroxUserCameraBootstrap());
}

class ZhiroxUserCameraBootstrap extends StatefulWidget {
  const ZhiroxUserCameraBootstrap({super.key});

  @override
  State<ZhiroxUserCameraBootstrap> createState() => _ZhiroxUserCameraBootstrapState();
}

class _ZhiroxUserCameraBootstrapState extends State<ZhiroxUserCameraBootstrap>
    with WidgetsBindingObserver {
  StreamSubscription<AuthState>? _authSub;
  bool _admin = false;
  bool _showCameraSettings = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      unawaited(_refreshRole());
      unawaited(A11CameraCoordinator.instance.start());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_refreshRole()));
  }

  Future<void> _refreshRole() async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) {
        if (mounted && _admin) setState(() => _admin = false);
        return;
      }
      final row = await client.from('profiles').select('role').eq('id', user.id).single();
      final isAdmin = row['role'] == 'admin';
      if (mounted && isAdmin != _admin) setState(() => _admin = isAdmin);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(A11CameraCoordinator.instance.start());
      unawaited(_refreshRole());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showCameraSettings) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('ckb'),
        theme: ThemeData(useMaterial3: true, fontFamily: 'NotoKufiArabic'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: CameraSourceSettingsScreen(
            onClose: () => setState(() => _showCameraSettings = false),
          ),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          const Positioned.fill(child: legacy.ZhiroxApp()),
          if (_admin)
            Positioned(
              right: 12,
              top: 58,
              child: SafeArea(
                child: Material(
                  color: Colors.transparent,
                  child: FloatingActionButton.small(
                    heroTag: 'zhirox-camera-source',
                    tooltip: 'سەرچاوەی ڤیدیۆ',
                    onPressed: () => setState(() => _showCameraSettings = true),
                    child: const Icon(Icons.video_settings_outlined),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
