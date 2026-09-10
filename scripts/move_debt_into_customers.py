from pathlib import Path


def patch_admin():
    path = Path('lib/screens/admin/admin_dashboard.dart')
    text = path.read_text()
    text = text.replace("import 'package:zhirox/screens/shared/debt_list_screen.dart';\n", '')

    screen = """      DebtListScreen(key: const ValueKey('debts')),
"""
    if screen not in text and "ValueKey('debts')" in text:
        raise SystemExit('unexpected admin debt screen format')
    text = text.replace(screen, '', 1)

    debt_nav = """                _buildNavItem(
                  3,
                  Icons.receipt_long_outlined,
                  Icons.receipt_long,
                  'قەرز',
                ),
"""
    if debt_nav not in text and "'قەرز'," in text:
        raise SystemExit('unexpected admin debt nav format')
    text = text.replace(debt_nav, '', 1)

    pending_old = """                _buildNavItem(
                  4,
                  Icons.pending_actions_outlined,
"""
    pending_new = """                _buildNavItem(
                  3,
                  Icons.pending_actions_outlined,
"""
    if pending_old in text:
        text = text.replace(pending_old, pending_new, 1)
    elif pending_new not in text:
        raise SystemExit('admin pending nav not found')

    path.write_text(text)


def patch_employee():
    path = Path('lib/screens/employee/employee_dashboard.dart')
    text = path.read_text()
    text = text.replace("import 'package:zhirox/screens/shared/debt_list_screen.dart';\n", '')

    debt_screen = """          _visitedTabs.contains(1)
              ? const DebtListScreen(key: ValueKey('employee-debts'))
              : const SizedBox.shrink(),
"""
    text = text.replace(debt_screen, '', 1)

    profile_screen_old = """          _visitedTabs.contains(2)
              ? UserProfileScreen(
"""
    profile_screen_new = """          _visitedTabs.contains(1)
              ? UserProfileScreen(
"""
    if profile_screen_old in text:
        text = text.replace(profile_screen_old, profile_screen_new, 1)
    elif profile_screen_new not in text:
        raise SystemExit('employee profile screen index not found')

    debt_nav = """                _buildNavItem(
                  index: 1,
                  icon: Icons.receipt_long_outlined,
                  activeIcon: Icons.receipt_long_rounded,
                  label: 'قەرز',
                ),
"""
    text = text.replace(debt_nav, '', 1)

    profile_nav_old = """                _buildNavItem(
                  index: 2,
                  icon: Icons.person_outline_rounded,
"""
    profile_nav_new = """                _buildNavItem(
                  index: 1,
                  icon: Icons.person_outline_rounded,
"""
    if profile_nav_old in text:
        text = text.replace(profile_nav_old, profile_nav_new, 1)
    elif profile_nav_new not in text:
        raise SystemExit('employee profile nav index not found')

    path.write_text(text)


patch_admin()
patch_employee()
