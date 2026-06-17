import 'package:flutter/widgets.dart';
import 'screen_breakpoints.dart';

typedef ResponsiveWidgetBuilder = Widget Function(
  BuildContext context,
  BoxConstraints constraints,
);

class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  final ResponsiveWidgetBuilder mobile;
  final ResponsiveWidgetBuilder? tablet;
  final ResponsiveWidgetBuilder? desktop;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (ScreenBreakpoints.isDesktopWidth(width)) {
          return (desktop ?? tablet ?? mobile)(context, constraints);
        }
        if (ScreenBreakpoints.isTabletWidth(width)) {
          return (tablet ?? mobile)(context, constraints);
        }
        return mobile(context, constraints);
      },
    );
  }
}
