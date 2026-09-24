import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/screens/employee/employee_home_screen.dart';
import 'package:zhirox/screens/employee/employee_settings_screen.dart';
import 'package:zhirox/screens/shared/user_list_screen.dart';
import 'package:zhirox/widgets/zhirox_shell.dart';

class EmployeeDashboard extends StatefulWidget {
  const EmployeeDashboard({super.key});

  @override
  State<EmployeeDashboard> createState() => _EmployeeDashboardState();
}

class _EmployeeDashboardState extends State<EmployeeDashboard> {
  int _currentIndex = 0;
  final Set<int> _visitedTabs = <int>{0};

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
        _visitedTabs.contains(2)
            ? const EmployeeSettingsScreen(
                key: ValueKey('employee-settings'),
              )
            : const SizedBox.shrink(),
      ],
      destinations: const [
        ZhiroxDestination(
          label: 'سەرەکی',
          icon: Icons.space_dashboard_outlined,
          selectedIcon: Icons.space_dashboard_rounded,
        ),
        ZhiroxDestination(
          label: 'کڕیار',
          icon: Icons.people_outline_rounded,
          selectedIcon: Icons.people_rounded,
        ),
        ZhiroxDestination(
          label: 'زیاتر',
          icon: Icons.grid_view_outlined,
          selectedIcon: Icons.grid_view_rounded,
        ),
      ],
      onSelected: _selectTab,
    );
  }

}
