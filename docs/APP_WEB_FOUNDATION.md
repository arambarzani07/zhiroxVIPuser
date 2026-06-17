# Zhirox AI Debt — App + Web Foundation

This branch starts the safe app + web foundation for the existing Flutter + PocketBase project.

## Safety rules

- Keep the current mobile app working.
- Do not rewrite the app from zero.
- Do not delete existing screens, services, providers, assets, fonts, authentication, debts, payments, notifications, PDF logic, or PocketBase connection.
- Add responsive structure gradually.
- Keep real PocketBase data. No fake dashboard values.
- Keep Kurdish Sorani RTL.

## Added foundation files

```text
lib/core/responsive/screen_breakpoints.dart
lib/core/responsive/responsive_builder.dart
lib/core/widgets/responsive_dashboard_grid.dart
lib/core/widgets/zhirox_page_container.dart
```

## Breakpoints

```text
mobile: width <= 599
tablet: 600 <= width <= 1023
desktop/web: width >= 1024
```

## How to use the new responsive helpers

Use `ResponsiveBuilder` when a screen needs separate mobile/tablet/web layouts.

Use `ResponsiveDashboardGrid` for dashboard cards so cards become:

```text
mobile: 1 column
tablet: 2 columns
desktop/web: 4 columns
```

Use `ZhiroxPageContainer` to stop web pages from stretching too wide on large screens.

## Next safe step

Update `admin_dashboard.dart` to use:

```dart
ZhiroxPageContainer(
  child: ResponsiveDashboardGrid(
    children: [...dashboardCards],
  ),
)
```

Then test:

```bash
flutter analyze
flutter run -d chrome
flutter build web --release
```

Netlify publish directory:

```text
build/web
```
