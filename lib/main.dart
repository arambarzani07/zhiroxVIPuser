import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/providers/theme_provider.dart';
import 'package:zhirox/screens/auth/login_screen.dart';
import 'package:zhirox/screens/customer/customer_dashboard.dart';
import 'package:zhirox/services/connectivity_service.dart';
import 'package:zhirox/services/notification_service.dart';
import 'package:zhirox/utils/constants.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Notification permission must never block login if the OS/plugin is not
  // available. In-app notifications remain available through Supabase.
  try {
    await NotificationService.init();
    if (!await NotificationService.isPermissionGranted()) {
      await NotificationService.requestPermission();
    }
  } catch (_) {}

  await ConnectivityService.instance.init();
  runApp(const ZhiroxApp());
}

class ZhiroxApp extends StatelessWidget {
  const ZhiroxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) => MaterialApp(
          title: 'ژیرۆکس',
          debugShowCheckedModeBanner: false,
          themeMode: themeProvider.themeMode,
          locale: const Locale('ckb'),
          theme: _buildLightTheme(),
          darkTheme: _buildDarkTheme(),
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: _ConnectivityBanner(
              child: child ?? const SizedBox.shrink(),
            ),
          ),
          home: const AuthWrapper(),
        ),
      ),
    );
  }

  ThemeData _buildLightTheme() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
      ),
      fontFamily: 'NotoKufiArabic',
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: const TextStyle(fontFamily: 'NotoKufiArabic'),
        hintStyle: const TextStyle(fontFamily: 'NotoKufiArabic'),
      ),
      textTheme: Typography.material2021().black.apply(
        fontFamily: 'NotoKufiArabic',
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.dark,
        surface: AppDarkColors.surface,
      ),
      scaffoldBackgroundColor: AppDarkColors.background,
      fontFamily: 'NotoKufiArabic',
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: AppDarkColors.surface,
        foregroundColor: AppDarkColors.textPrimary,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppDarkColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: AppDarkColors.inputFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: TextStyle(
          fontFamily: 'NotoKufiArabic',
          color: AppDarkColors.textSecondary,
        ),
        hintStyle: TextStyle(
          fontFamily: 'NotoKufiArabic',
          color: AppDarkColors.textSecondary,
        ),
      ),
      textTheme: Typography.material2021().white.apply(
        fontFamily: 'NotoKufiArabic',
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppDarkColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppDarkColors.cardBorder),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppDarkColors.surface,
        titleTextStyle: TextStyle(
          color: AppDarkColors.textPrimary,
          fontFamily: 'NotoKufiArabic',
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        contentTextStyle: TextStyle(
          color: AppDarkColors.textSecondary,
          fontFamily: 'NotoKufiArabic',
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppDarkColors.surface,
      ),
      dividerColor: AppDarkColors.divider,
      iconTheme: IconThemeData(color: AppDarkColors.textSecondary),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        if (auth.isInitializing) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!auth.isLoggedIn) return const LoginScreen();

        // AuthProvider/PBService accept customer sessions only. This check is a
        // final fail-closed guard rather than an alternate role route.
        if (auth.userRole != 'customer') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (auth.isLoggedIn) auth.logout();
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return const CustomerDashboard();
      },
    );
  }
}

class _ConnectivityBanner extends StatefulWidget {
  const _ConnectivityBanner({required this.child});

  final Widget child;

  @override
  State<_ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<_ConnectivityBanner> {
  late final StreamSubscription<bool> _subscription;
  bool _isOnline = ConnectivityService.instance.isOnline;

  @override
  void initState() {
    super.initState();
    _subscription = ConnectivityService.instance.statusStream.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isOnline) return widget.child;

    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: Material(
            color: Colors.orange.shade900,
            child: InkWell(
              onTap: ConnectivityService.instance.checkNow,
              child: const SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                  child: Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      Icon(Icons.cloud_off, color: Colors.white, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'ئینتەرنێت بەردەست نییە — زانیاری نوێ ناکرێتەوە',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontFamily: 'NotoKufiArabic',
                          ),
                        ),
                      ),
                      Icon(Icons.refresh, color: Colors.white70, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}
