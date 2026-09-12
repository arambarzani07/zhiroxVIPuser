import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/screens/employee/employee_home_screen.dart';
import 'package:zhirox/screens/employee/employee_settings_screen.dart';
import 'package:zhirox/screens/shared/user_list_screen.dart';

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
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
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
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'داشبۆرد',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline_rounded),
            selectedIcon: Icon(Icons.people_rounded),
            label: 'کڕیارەکان',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'ڕێکخستن',
          ),
        ],
      ),
    );
  }
}
