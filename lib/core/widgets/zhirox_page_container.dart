import 'package:flutter/material.dart';
import '../responsive/screen_breakpoints.dart';

class ZhiroxPageContainer extends StatelessWidget {
  const ZhiroxPageContainer({
    super.key,
    required this.child,
    this.maxWidth = 1280,
    this.mobilePadding = const EdgeInsets.all(16),
    this.tabletPadding = const EdgeInsets.all(20),
    this.desktopPadding = const EdgeInsets.all(24),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsets mobilePadding;
  final EdgeInsets tabletPadding;
  final EdgeInsets desktopPadding;

  @override
  Widget build(BuildContext context) {
    final padding = ScreenBreakpoints.value<EdgeInsets>(
      context,
      mobile: mobilePadding,
      tablet: tabletPadding,
      desktop: desktopPadding,
    );

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}
