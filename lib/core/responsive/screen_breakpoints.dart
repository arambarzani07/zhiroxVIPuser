import 'package:flutter/widgets.dart';

/// Central responsive breakpoints for Zhirox.
///
/// These values keep one Flutter codebase suitable for:
/// - mobile app
/// - tablet
/// - desktop/web
class ScreenBreakpoints {
  const ScreenBreakpoints._();

  static const double mobileMax = 599;
  static const double tabletMin = 600;
  static const double tabletMax = 1023;
  static const double desktopMin = 1024;

  static bool isMobileWidth(double width) => width <= mobileMax;
  static bool isTabletWidth(double width) =>
      width >= tabletMin && width <= tabletMax;
  static bool isDesktopWidth(double width) => width >= desktopMin;

  static bool isMobile(BuildContext context) =>
      isMobileWidth(MediaQuery.sizeOf(context).width);

  static bool isTablet(BuildContext context) =>
      isTabletWidth(MediaQuery.sizeOf(context).width);

  static bool isDesktop(BuildContext context) =>
      isDesktopWidth(MediaQuery.sizeOf(context).width);

  static T value<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    if (isDesktopWidth(width)) return desktop ?? tablet ?? mobile;
    if (isTabletWidth(width)) return tablet ?? mobile;
    return mobile;
  }
}
