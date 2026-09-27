import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/features/expiry/expiry_monitor_screen.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/screens/employee/employee_home_screen.dart';
import 'package:zhirox/screens/employee/employee_settings_screen.dart';
import 'package:zhirox/screens/shared/user_list_screen.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/widgets/zhirox_shell.dart';

class EmployeeDashboard extends StatefulWidget {
  const EmployeeDashboard({super.key});

  @override
  State<EmployeeDashboard> createState() => _EmployeeDashboardState();
}

class _EmployeeDashboardState extends State<EmployeeDashboard> {
  int _currentIndex = 0;
  final Set<int> _visitedTabs = <int>{0};
  bool _canViewExpiry = false;
  bool _canManageExpiry = false;

  Future<void> _loadExpiryAccess() async {
    final auth = context.read<AuthProvider>();
    try {
      await PBService.ensureInitialized();
      final row = await PBService.client
          .from('employee_permissions')
          .select('can_view_expiry,can_manage_expiry')
          .eq('employee_id', auth.userId)
          .maybeSingle();
      if (!mounted) return;
      final manage = row?['can_manage_expiry'] == true;
      final allowed = row?['can_view_expiry'] == true || manage;
      setState(() {
        if (!_canViewExpiry && allowed && _currentIndex == 2) {
          _currentIndex = 3;
          _visitedTabs.add(3);
        } else if (_canViewExpiry && !allowed && _currentIndex == 3) {
          _currentIndex = 2;
          _visitedTabs.add(2);
        } else if (_canViewExpiry && !allowed && _currentIndex == 2) {
          _currentIndex = 0;
        }
        _canManageExpiry = manage;
        _canViewExpiry = allowed;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _canViewExpiry = false;
          _canManageExpiry = false;
          if (_currentIndex == 2) _currentIndex = 0;
        });
      }
    }
  }

  void _selectTab(int index) {
    if (_currentIndex == index) return;
    setState(() {
      _currentIndex = index;
      _visitedTabs.add(index);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadExpiryAccess();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AuthProvider>().refreshUser();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return ZhiroxAppShell(
      index: _currentIndex,
      pages: [
        EmployeeHomeScreen(
          key: const ValueKey('employee-dashboard'),
          onOpenCustomers: () => _selectTab(1),
        ),
        _visitedTabs.contains(1)
            ? UserListScreen(
                key: const ValueKey('employee-customers'),
                role: 'customer',
                adminId: auth.adminId,
              )
            : const SizedBox.shrink(),
        if (_canViewExpiry)
          _visitedTabs.contains(2)
              ? ExpiryMonitorScreen(
                  key: const ValueKey('employee-expiry'),
                  canManage: _canManageExpiry,
                )
              : const SizedBox.shrink(),
        _visitedTabs.contains(_canViewExpiry ? 3 : 2)
            ? const EmployeeSettingsScreen(key: ValueKey('employee-settings'))
            : const SizedBox.shrink(),
      ],
      destinations: [
        const ZhiroxDestination(
          label: 'سەرەکی',
          icon: Icons.space_dashboard_outlined,
          selectedIcon: Icons.space_dashboard_rounded,
        ),
        const ZhiroxDestination(
          label: 'کڕیار',
          icon: Icons.people_outline_rounded,
          selectedIcon: Icons.people_rounded,
        ),
        if (_canViewExpiry)
          const ZhiroxDestination(
            label: 'کاڵا',
            icon: Icons.inventory_2_outlined,
            selectedIcon: Icons.inventory_2_rounded,
          ),
        const ZhiroxDestination(
          label: 'زیاتر',
          icon: Icons.grid_view_outlined,
          selectedIcon: Icons.grid_view_rounded,
        ),
      ],
      onSelected: _selectTab,
    );
  }
}
