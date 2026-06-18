import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/providers/debt_provider.dart';
import 'package:zhirox/providers/theme_provider.dart';
import 'package:zhirox/screens/admin/manager_dashboard_clean.dart';
import 'package:zhirox/screens/auth/login_screen.dart';
import 'package:zhirox/screens/customer/customer_dashboard_clean.dart';
import 'package:zhirox/screens/employee/employee_dashboard.dart';
import 'package:zhirox/services/connectivity_service.dart';
import 'package:zhirox/services/notification_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _startCoreServices();
  runApp(const ZhiroxApp());
}

Future<void> _startCoreServices() async {
  try {
    await NotificationService.init();
    await NotificationService.requestPermission();
  } catch (_) {}

  try {
    await ConnectivityService.instance.init();
  } catch (_) {}
}

class ZhiroxApp extends StatelessWidget {
  const ZhiroxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => DebtProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: AppStrings.appName,
            debugShowCheckedModeBanner: false,
            locale: const Locale('ckb'),
            themeMode: themeProvider.themeMode,
            theme: _buildLightTheme(),
            darkTheme: _buildDarkTheme(),
            builder: (context, child) => Directionality(
              textDirection: TextDirection.rtl,
              child: _ConnectivityBanner(child: child ?? const SizedBox()),
            ),
            home: const AuthWrapper(),
          );
        },
      ),
    );
  }
}

ThemeData _buildLightTheme() {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ),
    fontFamily: 'NotoKufiArabic',
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.scaffoldBackground,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
    textTheme: Typography.material2021().black.apply(fontFamily: 'NotoKufiArabic'),
    cardTheme: CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}

ThemeData _buildDarkTheme() {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppDarkColors.primary,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
    textTheme: Typography.material2021().white.apply(fontFamily: 'NotoKufiArabic'),
    cardTheme: CardThemeData(
      elevation: 0,
      color: AppDarkColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppDarkColors.cardBorder),
      ),
    ),
    dividerColor: AppDarkColors.divider,
    iconTheme: IconThemeData(color: AppDarkColors.textSecondary),
  );
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _wasLoggedIn = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        if (auth.isInitializing) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (_wasLoggedIn && !auth.isLoggedIn) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.of(context).popUntil((route) => route.isFirst);
            if (auth.wasDeactivated) {
              auth.clearDeactivatedFlag();
              AppHelpers.showSnackBar(
                context,
                'ئەکاونتەکەت ناچالاک کراوە. پەیوەندی بە بەڕێوەبەرەکەت بکە.',
                isError: true,
              );
            }
          });
        }
        _wasLoggedIn = auth.isLoggedIn;

        if (auth.isLoggedIn && auth.subscriptionDaysLeft <= 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            await auth.logout();
            if (!mounted) return;
            AppHelpers.showSnackBar(
              context,
              'ماوەی بەشداریت تەواو بووە. تکایە پەیوەندی بکە بۆ نوێکردنەوە.',
              isError: true,
            );
          });
        }

        if (!auth.isLoggedIn) return const LoginScreen();

        switch (auth.userRole) {
          case 'admin':
            return const ManagerDashboardClean();
          case 'employee':
            return const EmployeeDashboard();
          case 'customer':
            return const CustomerDashboardClean();
          default:
            return const LoginScreen();
        }
      },
    );
  }
}

class _ConnectivityBanner extends StatefulWidget {
  final Widget child;

  const _ConnectivityBanner({required this.child});

  @override
  State<_ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<_ConnectivityBanner> {
  bool _isOnline = ConnectivityService.instance.isOnline;

  @override
  void initState() {
    super.initState();
    ConnectivityService.instance.statusStream.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
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
              onTap: () => ConnectivityService.instance.checkNow(),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                child: const Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    Icon(Icons.cloud_off, color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'پارێزرا ✅ کاتێک ئینتەرنێت گەڕایەوە، خۆکارانە تەواو دەبێت',
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
        Expanded(child: widget.child),
      ],
    );
  }
}
