import 'package:flutter/material.dart';
import 'package:zhirox/utils/constants.dart';

abstract final class AppDesign {
  static const double radiusSmall = 12;
  static const double radiusMedium = 18;
  static const double radiusLarge = 28;
  static const double pagePadding = 16;

  static ThemeData get lightTheme {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      surface: AppColors.surface,
    ).copyWith(
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      error: AppColors.danger,
      outline: AppColors.border,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: AppColors.surfaceMuted,
    );
    return _base(scheme).copyWith(
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontFamily: 'NotoKufiArabic',
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      dividerColor: AppColors.border,
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: Colors.white,
        indicatorColor: AppColors.primarySoft,
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
          fontFamily: 'NotoKufiArabic',
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.textSecondary,
        )),
      ),
    );
  }

  static ThemeData get darkTheme {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppDarkColors.primary,
      brightness: Brightness.dark,
      surface: AppDarkColors.surface,
    ).copyWith(
      primary: AppDarkColors.primary,
      secondary: AppColors.secondary,
      error: const Color(0xFFFF6B7A),
      outline: AppDarkColors.cardBorder,
      surfaceContainerLowest: AppDarkColors.card,
      surfaceContainerLow: AppDarkColors.surface,
    );
    return _base(scheme).copyWith(
      scaffoldBackgroundColor: AppDarkColors.background,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: AppDarkColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontFamily: 'NotoKufiArabic',
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppDarkColors.textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppDarkColors.card,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          side: const BorderSide(color: AppDarkColors.cardBorder),
        ),
      ),
      dividerColor: AppDarkColors.divider,
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppDarkColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: AppDarkColors.card,
        indicatorColor: AppDarkColors.primaryMuted,
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
          fontFamily: 'NotoKufiArabic',
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? AppDarkColors.primary
              : AppDarkColors.textSecondary,
        )),
      ),
    );
  }

  static ThemeData _base(ColorScheme scheme) => ThemeData(
    colorScheme: scheme,
    fontFamily: 'NotoKufiArabic',
    useMaterial3: true,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
    textTheme: Typography.material2021().black.apply(
      fontFamily: 'NotoKufiArabic',
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 50),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        minimumSize: const Size(48, 50),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        side: BorderSide(color: scheme.outline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSmall),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSmall),
        borderSide: BorderSide(color: scheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSmall),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
    ),
    dialogTheme: DialogThemeData(
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLarge),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusSmall),
      ),
    ),
  );
}

class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
        )),
        if (subtitle != null)
          Text(subtitle!, style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          )),
      ],
    )),
    if (trailing != null) trailing!,
  ]);
}

class AppSurface extends StatelessWidget {
  const AppSurface({super.key, required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
      border: Border.all(color: Theme.of(context).colorScheme.outline),
    ),
    child: Padding(padding: padding, child: child),
  );
}
