import 'package:flutter/material.dart';

/// The same visual rules are used by the market and platform applications.
abstract final class ZhiroxVisual {
  static ThemeData theme(ThemeData base) {
    final scheme = base.colorScheme;
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          height: 1.5,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          height: 1.5,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(
          fontSize: 15,
          height: 1.6,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          fontSize: 14,
          height: 1.6,
        ),
        bodySmall: base.textTheme.bodySmall?.copyWith(
          fontSize: 12,
          height: 1.6,
        ),
      ),
      listTileTheme: base.listTileTheme.copyWith(
        minTileHeight: 72,
        minVerticalPadding: 12,
        iconColor: scheme.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        border: border(scheme.outline),
        enabledBorder: border(scheme.outline),
        focusedBorder: border(scheme.primary, 2),
        errorBorder: border(scheme.error),
        focusedErrorBorder: border(scheme.error, 2),
        errorMaxLines: 3,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(
            fontFamily: 'NotoKufiArabic',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size.square(48)),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        indicatorColor: scheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.primary),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      navigationBarTheme: base.navigationBarTheme.copyWith(
        backgroundColor: scheme.surfaceContainerLowest,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: scheme.surfaceContainerLowest,
      ),
    );
  }
}

/// Constrains reading width without constraining the height of a scroll view.
class ZhiroxPageFrame extends StatelessWidget {
  const ZhiroxPageFrame({super.key, required this.child, this.maxWidth = 960});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: SizedBox(width: double.infinity, child: child),
    ),
  );
}

/// Large text gets two actions per row rather than four squeezed labels.
class ZhiroxActionGrid extends StatelessWidget {
  const ZhiroxActionGrid({
    super.key,
    required this.children,
    this.maxColumns = 4,
  }) : assert(maxColumns == 2 || maxColumns == 4);
  final List<Widget> children;
  final int maxColumns;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final largeText = MediaQuery.textScalerOf(context).scale(12) > 16;
      final columns = box.maxWidth < 360 || largeText
          ? maxColumns ~/ 2
          : maxColumns;
      final width = (box.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class ZhiroxNavigationScaffold extends StatelessWidget {
  const ZhiroxNavigationScaffold({
    super.key,
    required this.index,
    required this.pages,
    required this.destinations,
    required this.onSelected,
  }) : assert(pages.length == destinations.length);
  final int index;
  final List<Widget> pages;
  final List<NavigationDestination> destinations;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final content = IndexedStack(index: index, children: pages);
      final scheme = Theme.of(context).colorScheme;
      if (box.maxWidth >= 720) {
        return Scaffold(
          body: Row(
            children: [
              SafeArea(
                child: NavigationRail(
                  selectedIndex: index,
                  onDestinationSelected: onSelected,
                  extended: box.maxWidth >= 1100,
                  labelType: box.maxWidth >= 1100
                      ? NavigationRailLabelType.none
                      : NavigationRailLabelType.all,
                  destinations: [
                    for (final item in destinations)
                      NavigationRailDestination(
                        icon: item.icon,
                        selectedIcon: item.selectedIcon,
                        label: Text(item.label),
                      ),
                  ],
                ),
              ),
              VerticalDivider(width: 1, color: scheme.outlineVariant),
              Expanded(child: content),
            ],
          ),
        );
      }
      final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
      return Scaffold(
        body: content,
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
          ),
          child: NavigationBar(
            height: 76 + (scale - 1).clamp(0, 2) * 24,
            selectedIndex: index,
            onDestinationSelected: onSelected,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: destinations,
          ),
        ),
      );
    },
  );
}
