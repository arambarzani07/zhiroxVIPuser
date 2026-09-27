import 'package:flutter/material.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/widgets/app_design.dart';

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
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: IndexedStack(index: index, children: pages),
          ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          border: Border(
            top: BorderSide(color: scheme.outline.withValues(alpha: 0.65)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.20
                    : 0.055,
              ),
              blurRadius: 24,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.sm,
              AppSpacing.xs,
            ),
            child: Row(
              children: List.generate(destinations.length, (itemIndex) {
                return Expanded(
                  child: _ZhiroxNavButton(
                    destination: destinations[itemIndex],
                    selected: itemIndex == index,
                    onTap: () => onSelected(itemIndex),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _ZhiroxNavButton extends StatelessWidget {
  const _ZhiroxNavButton({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final ZhiroxDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inactive = scheme.onSurfaceVariant;
    final primary = scheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppDesign.radiusSmall),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDesign.radiusSmall),
          child: AnimatedContainer(
            duration: AppMotion.fast,
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? primary.withValues(
                      alpha: Theme.of(context).brightness == Brightness.dark
                          ? 0.16
                          : 0.085,
                    )
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppDesign.radiusSmall),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      selected
                          ? destination.selectedIcon
                          : destination.icon,
                      size: 22,
                      color: selected ? primary : inactive,
                    ),
                    if (destination.badgeCount > 0)
                      PositionedDirectional(
                        top: -7,
                        start: -10,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 18),
                          height: 18,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.danger,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: scheme.surfaceContainerLowest,
                              width: 1.5,
                            ),
                          ),
                          child: Text(
                            destination.badgeCount > 99
                                ? '99+'
                                : '${destination.badgeCount}',
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? primary : inactive,
                    fontSize: 10.5,
                    fontWeight:
                        selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
