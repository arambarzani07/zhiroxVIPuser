import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';
import 'package:zhirox/main.dart' as legacy;
import 'package:zhirox/screens/admin/a11_camera_setup_screen.dart';
import 'package:zhirox/services/a11_camera_coordinator.dart';
import 'package:zhirox/services/a11_camera_service.dart';
import 'package:zhirox/services/connectivity_service.dart';
import 'package:zhirox/services/notification_service.dart';
import 'package:zhirox/services/pb_service.dart';

/// A11-enabled production entrypoint.
///
/// The existing ZHIROX application remains unchanged underneath this bootstrap.
/// Admin/cashier devices get a one-time local-camera setup when credentials have
/// not been stored yet; customer accounts never see the camera setup screen.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await NotificationService.init();
    await NotificationService.requestPermission();
    await Workmanager().initialize(
      legacy.callbackDispatcher,
      isInDebugMode: false,
    );
    await Workmanager().registerPeriodicTask(
      'overdueDebtsCheck',
      'checkOverdueDebts',
      frequency: const Duration(hours: 12),
      constraints: Constraints(networkType: NetworkType.connected),
    );
  } catch (_) {
    // The app must remain usable even when an optional background plugin is
    // unavailable on a particular build target.
  }

  await ConnectivityService.instance.init();
  await PBService.ensureInitialized();
  unawaited(A11CameraCoordinator.instance.start());

  runApp(const A11Bootstrap());
}

class A11Bootstrap extends StatefulWidget {
  const A11Bootstrap({super.key});

  @override
  State<A11Bootstrap> createState() => _A11BootstrapState();
}

class _A11BootstrapState extends State<A11Bootstrap>
    with WidgetsBindingObserver {
  StreamSubscription<AuthState>? _authSub;
  bool _showSetup = false;
  bool _checking = false;
  bool _deferredForSession = false;
  String? _lastUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      final userId = state.session?.user.id;
      if (userId == null) {
        _lastUserId = null;
        _deferredForSession = false;
        if (mounted && _showSetup) setState(() => _showSetup = false);
        return;
      }
      if (_lastUserId != userId) {
        _lastUserId = userId;
        _deferredForSession = false;
      }
      unawaited(_evaluateSetup());
      unawaited(A11CameraCoordinator.instance.start());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_evaluateSetup());
    });
  }

  Future<void> _evaluateSetup() async {
    if (_checking || _deferredForSession) return;
    _checking = true;
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) {
        if (mounted && _showSetup) setState(() => _showSetup = false);
        return;
      }

      final profile = await client
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .single();
      if (profile['role'] != 'admin') {
        if (mounted && _showSetup) setState(() => _showSetup = false);
        return;
      }

      final config = await A11CameraService.instance.loadConfig();
      final needsSetup = !config.enabled || config.password.isEmpty;
      if (mounted && needsSetup != _showSetup) {
        setState(() => _showSetup = needsSetup);
      }
    } catch (_) {
      // Login and the rest of ZHIROX must never be blocked by camera setup.
    } finally {
      _checking = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(A11CameraCoordinator.instance.start());
      unawaited(A11CameraService.instance.ensureBufferRunning());
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
    if (!_showSetup) return const legacy.ZhiroxApp();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
        fontFamily: 'NotoKufiArabic',
      ),
      home: A11CameraSetupScreen(
        onCompleted: () {
          if (!mounted) return;
          setState(() => _showSetup = false);
          unawaited(A11CameraCoordinator.instance.start());
        },
        onLater: () {
          if (!mounted) return;
          _deferredForSession = true;
          setState(() => _showSetup = false);
        },
      ),
    );
  }
}
