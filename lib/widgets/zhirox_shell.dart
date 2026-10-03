import 'package:flutter/material.dart';
import 'package:zhirox/widgets/design_refresh.dart';

class ZhiroxDestination {
  const ZhiroxDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.badgeCount = 0,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final int badgeCount;
}

class ZhiroxAppShell extends StatelessWidget {
  const ZhiroxAppShell({
    super.key,
    required this.index,
    required this.pages,
    required this.destinations,
    required this.onSelected,
  }) : assert(pages.length == destinations.length);

  final int index;
  final List<Widget> pages;
  final List<ZhiroxDestination> destinations;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return ZhiroxNavigationScaffold(
      index: index,
      pages: pages,
      onSelected: onSelected,
      destinations: [
        for (final item in destinations)
          NavigationDestination(
            label: item.label,
            icon: Badge(
              isLabelVisible: item.badgeCount > 0,
              label: Text(item.badgeCount > 99 ? '99+' : '${item.badgeCount}'),
              child: Icon(item.icon),
            ),
            selectedIcon: Badge(
              isLabelVisible: item.badgeCount > 0,
              label: Text(item.badgeCount > 99 ? '99+' : '${item.badgeCount}'),
              child: Icon(item.selectedIcon),
            ),
          ),
      ],
    );
  }
}
