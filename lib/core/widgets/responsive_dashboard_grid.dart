import 'package:flutter/material.dart';
import '../responsive/screen_breakpoints.dart';

class ResponsiveDashboardGrid extends StatelessWidget {
  const ResponsiveDashboardGrid({
    super.key,
    required this.children,
    this.mobileSpacing = 12,
    this.tabletSpacing = 14,
    this.desktopSpacing = 16,
    this.mobileChildAspectRatio = 1.65,
    this.tabletChildAspectRatio = 1.85,
    this.desktopChildAspectRatio = 2.15,
  });

  final List<Widget> children;
  final double mobileSpacing;
  final double tabletSpacing;
  final double desktopSpacing;
  final double mobileChildAspectRatio;
  final double tabletChildAspectRatio;
  final double desktopChildAspectRatio;

  @override
  Widget build(BuildContext context) {
    final crossAxisCount = ScreenBreakpoints.value<int>(
      context,
      mobile: 1,
      tablet: 2,
      desktop: 4,
    );

    final spacing = ScreenBreakpoints.value<double>(
      context,
      mobile: mobileSpacing,
      tablet: tabletSpacing,
      desktop: desktopSpacing,
    );

    final childAspectRatio = ScreenBreakpoints.value<double>(
      context,
      mobile: mobileChildAspectRatio,
      tablet: tabletChildAspectRatio,
      desktop: desktopChildAspectRatio,
    );

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: children.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
        childAspectRatio: childAspectRatio,
      ),
      itemBuilder: (context, index) => children[index],
    );
  }
}
