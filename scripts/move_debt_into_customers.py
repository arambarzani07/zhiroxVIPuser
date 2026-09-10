from pathlib import Path


def patch_admin():
    path = Path('lib/screens/admin/admin_dashboard.dart')
    text = path.read_text()
    text = text.replace("import 'package:zhirox/screens/shared/debt_list_screen.dart';\n", '')
    text = text.replace("      DebtListScreen(key: const ValueKey('debts')),\n", '', 1)
    debt_nav = """                _buildNavItem(
                  3,
                  Icons.receipt_long_outlined,
                  Icons.receipt_long,
                  'قەرز',
                ),
"""
    text = text.replace(debt_nav, '', 1)
    text = text.replace("""                _buildNavItem(
                  4,
                  Icons.pending_actions_outlined,
""", """                _buildNavItem(
                  3,
                  Icons.pending_actions_outlined,
""", 1)
    if "ValueKey('debts')" in text or "'قەرز'," in text:
        raise SystemExit('admin debt navigation still present')
    path.write_text(text)


def patch_employee():
    path = Path('lib/screens/employee/employee_dashboard.dart')
    text = path.read_text()
    text = text.replace("import 'package:zhirox/screens/shared/debt_list_screen.dart';\n", '')
    text = text.replace("""          _visitedTabs.contains(1)
              ? const DebtListScreen(key: ValueKey('employee-debts'))
              : const SizedBox.shrink(),
""", '', 1)
    text = text.replace("""          _visitedTabs.contains(2)
              ? UserProfileScreen(
""", """          _visitedTabs.contains(1)
              ? UserProfileScreen(
""", 1)
    text = text.replace("""                _buildNavItem(
                  index: 1,
                  icon: Icons.receipt_long_outlined,
                  activeIcon: Icons.receipt_long_rounded,
                  label: 'قەرز',
                ),
""", '', 1)
    text = text.replace("""                _buildNavItem(
                  index: 2,
                  icon: Icons.person_outline_rounded,
""", """                _buildNavItem(
                  index: 1,
                  icon: Icons.person_outline_rounded,
""", 1)
    if "employee-debts" in text or "label: 'قەرز'" in text:
        raise SystemExit('employee debt navigation still present')
    path.write_text(text)


patch_admin()
patch_employee()
