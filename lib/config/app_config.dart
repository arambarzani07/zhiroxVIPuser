class AppConfig {
  const AppConfig._();

  /// PocketBase API base URL.
  ///
  /// Default value keeps the current Railway backend working during the
  /// frontend cleanup phase. Builds can override it with:
  ///
  /// flutter build web --dart-define=PB_BASE_URL=https://your-pocketbase-url
  /// flutter build apk --dart-define=PB_BASE_URL=https://your-pocketbase-url
  static const String pbBaseUrl = String.fromEnvironment(
    'PB_BASE_URL',
    defaultValue: 'https://pocketbase-production-18bc.up.railway.app',
  );
}
