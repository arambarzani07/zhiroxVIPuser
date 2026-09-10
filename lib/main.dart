import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/providers/debt_provider.dart';
import 'package:zhirox/providers/theme_provider.dart';
import 'package:zhirox/screens/admin/admin_dashboard.dart';
import 'package:zhirox/screens/auth/login_screen.dart';
import 'package:zhirox/screens/customer/customer_dashboard.dart';
import 'package:zhirox/screens/employee/employee_dashboard.dart';
import 'package:zhirox/services/connectivity_service.dart';
import 'package:zhirox/services/notification_service.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      if (task == 'checkNotifications') {
        final userId = inputData?['userId'];
        if (userId != null) {
          final count = await PBService.checkNewNotifications(userId);
          if (count > 0) {
            await NotificationService.init();
            await NotificationService.show(
              title: 'ئاگادارکردنەوەی نوێ',
              body: 'تۆ $count ئاگادارکردنەوەی نەخوێندراوەت هەیە',
              id: 999,
            );
          }
        }
      } else if (task == 'checkOverdueDebts') {
        await NotificationService.init();

        final now = DateTime.now();
        final today =
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

        final overdueDebts = await PBService.pb
            .collection('debts')
            .getList(
              filter:
                  'due_date <= "$today" && status != "paid" && remaining > 0',
              perPage: 100,
              expand: 'customer',
            );

        if (overdueDebts.items.isNotEmpty) {
          int notifId = 1000;
          for (final debt in overdueDebts.items) {
            final remaining = debt.getDoubleValue('remaining');
            final dueDate = debt.getStringValue('due_date');
            final customerId = debt.getStringValue('customer');
            final formattedAmount =
                '${remaining.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} د.ع';

            await NotificationService.show(
              title: '⚠️ بەرواری دانەوەی قەرز',
              body:
                  'قەرزی $formattedAmount بەرواری دانەوەی ($dueDate) تێپەڕیوە. تکایە قەرزەکە بدەوە.',
              id: notifId++,
            );

            try {
              await PBService.createNotification(
                customerId: customerId,
                message:
                    '⚠️ قەرزی $formattedAmount دواکەوتووە!\n'
                    'بەرواری دانەوە: ${dueDate.replaceAll('-', '/')} بووە.\n'
                    'تکایە هەرچی زووتر بیگەڕێنەوە.',
                senderId: customerId,
                type: 'debt_overdue',
              );
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
    return true;
  });
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ZhiroxApp());

  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_initializeAfterLaunch());
  });
}

Future<void> _initializeAfterLaunch() async {
  try {
    await ConnectivityService.instance.init();
  } catch (_) {}

  try {
    await NotificationService.init();
    await NotificationService.requestPermission();
  } catch (_) {}

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      await Workmanager().initialize(callbackDispatcher);
      await Workmanager().registerPeriodicTask(
        'overdueDebtsCheck',
        'checkOverdueDebts',
        frequency: const Duration(hours: 12),
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } catch (_) {}
  }
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
        builder: (context, themeProvider, _) => MaterialApp(
          title: 'ژیرۆکس',
          debugShowCheckedModeBanner: false,
          themeMode: themeProvider.themeMode,
          theme: ThemeData(
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              labelStyle: const TextStyle(fontFamily: 'NotoKufiArabic'),
              hintStyle: const TextStyle(fontFamily: 'NotoKufiArabic'),
            ),
            textTheme: Typography.material2021().black.apply(
              fontFamily: 'NotoKufiArabic',
            ),
            cardTheme: CardThemeData(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          darkTheme: ThemeData(
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: AppDarkColors.inputFill,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
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
          ),
          locale: const Locale('ckb'),
          builder: (context, child) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: _OnlineOnlyGate(child: child!),
            );
          },
          home: const AuthWrapper(),
        ),
      ),
    );
  }
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
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (_wasLoggedIn && !auth.isLoggedIn) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.of(context).popUntil((route) => route.isFirst);

            if (auth.wasDeactivated) {
              auth.clearDeactivatedFlag();
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => Directionality(
                  textDirection: TextDirection.rtl,
                  child: Dialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.block,
                              color: Colors.red,
                              size: 40,
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'ناچالاک کرایت',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'ئەدمین ئەکاونتت ناچالاک کردووە.\nبۆ زانیاری زیاتر پەیوەندی بکە بە ئەدمینەکەت.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                              height: 1.6,
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () => Navigator.pop(context),
                              child: const Text(
                                'باشە',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }
          });
        }
        _wasLoggedIn = auth.isLoggedIn;

        if (auth.isLoggedIn && auth.subscriptionDaysLeft <= 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            await auth.logout();
            if (!context.mounted) return;
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
            return const AdminDashboard();
          case 'employee':
            return const EmployeeDashboard();
          case 'customer':
            return const CustomerDashboard();
          default:
            return const LoginScreen();
        }
      },
    );
  }
}

class _OnlineOnlyGate extends StatefulWidget {
  final Widget child;
  const _OnlineOnlyGate({required this.child});

  @override
  State<_OnlineOnlyGate> createState() => _OnlineOnlyGateState();
}

class _OnlineOnlyGateState extends State<_OnlineOnlyGate> {
  late StreamSubscription<bool> _sub;
  bool _isOnline = ConnectivityService.instance.isOnline;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _sub = ConnectivityService.instance.statusStream.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  Future<void> _retry() async {
    if (_checking) return;
    setState(() => _checking = true);
    final online = await ConnectivityService.instance.checkNow();
    if (!mounted) return;
    setState(() {
      _isOnline = online;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isOnline) return widget.child;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background =
        isDark ? AppDarkColors.background : const Color(0xFFF7F8FA);
    final surface = isDark ? AppDarkColors.card : Colors.white;
    final border =
        isDark ? AppDarkColors.cardBorder : const Color(0xFFEAECF0);
    final primaryText =
        isDark ? AppDarkColors.textPrimary : const Color(0xFF1D2939);
    final secondaryText =
        isDark ? AppDarkColors.textSecondary : const Color(0xFF667085);

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            ignoring: true,
            child: widget.child,
          ),
        ),
        Positioned.fill(
          child: Material(
            color: background,
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: border),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 58,
                            height: 58,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(17),
                            ),
                            child: const Icon(
                              Icons.wifi_off_rounded,
                              color: Colors.orange,
                              size: 29,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'پەیوەندی ئینتەرنێت پێویستە',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: primaryText,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'ژیرۆکس تەنها بە شێوەی ئۆنلاین کار دەکات. پەیوەندی ئینتەرنێتەکەت بپشکنە و دووبارە هەوڵ بدە.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: secondaryText,
                              fontSize: 12.5,
                              height: 1.7,
                            ),
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _checking ? null : _retry,
                              icon: _checking
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.refresh_rounded, size: 19),
                              label: Text(
                                _checking
                                    ? 'دەچێتەوە...'
                                    : 'دووبارە هەوڵ بدە',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
