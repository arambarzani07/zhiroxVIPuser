import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.edition,
    required this.version,
    required this.latestBuild,
    required this.downloadUrl,
    required this.notes,
    required this.mandatory,
    required this.sha256,
    this.publishedAt,
    this.commit,
  });

  final String edition;
  final String version;
  final int latestBuild;
  final String downloadUrl;
  final String notes;
  final bool mandatory;
  final String sha256;
  final DateTime? publishedAt;
  final String? commit;

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    return AppUpdateInfo(
      edition: json['edition']?.toString().trim().toLowerCase() ?? '',
      version: json['version']?.toString().trim() ?? '',
      latestBuild: int.tryParse(json['build_number']?.toString() ?? '') ?? 0,
      downloadUrl: json['download_url']?.toString().trim() ?? '',
      notes: json['notes']?.toString().trim() ?? '',
      mandatory: json['mandatory'] == true,
      sha256: json['sha256']?.toString().trim().toLowerCase() ?? '',
      publishedAt: DateTime.tryParse(json['published_at']?.toString() ?? ''),
      commit: json['commit']?.toString().trim(),
    );
  }
}

class AppUpdateService {
  AppUpdateService._();

  static const String _repository = 'arambarzani07/zhiroxVIPuser';
  static const String _compiledEdition = String.fromEnvironment(
    'ZHIROX_APP_EDITION',
    defaultValue: 'user',
  );
  static const String _compiledBuild = String.fromEnvironment(
    'ZHIROX_BUILD_NUMBER',
    defaultValue: '0',
  );

  static int get currentBuild => int.tryParse(_compiledBuild) ?? 0;

  static String get edition {
    final value = _compiledEdition.trim().toLowerCase();
    if (value == 'owner' || value == 'owner-source') return 'owner';
    return 'user';
  }

  static String get releaseTag => '$edition-latest';
  static String get manifestFileName => '$edition-update.json';

  static Uri get manifestUri {
    final base = Uri.parse(
      'https://github.com/$_repository/releases/download/$releaseTag/$manifestFileName',
    );
    return base.replace(
      queryParameters: {
        'cache_bust': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );
  }

  static Future<AppUpdateInfo?> checkForUpdate() async {
    // Only CI-built applications have a trusted monotonically increasing build
    // number. Local/debug builds intentionally do not show update prompts.
    if (currentBuild <= 0) return null;

    final response = await http
        .get(
          manifestUri,
          headers: const {
            'Accept': 'application/json',
            'Cache-Control': 'no-cache',
          },
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) {
      throw StateError('update_manifest_http_${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('invalid_update_manifest');
    }

    final info = AppUpdateInfo.fromJson(Map<String, dynamic>.from(decoded));
    if (info.edition != edition || info.latestBuild <= 0) {
      throw const FormatException('invalid_update_manifest_identity');
    }

    final downloadUri = Uri.tryParse(info.downloadUrl);
    if (downloadUri == null ||
        downloadUri.scheme != 'https' ||
        downloadUri.host != 'github.com') {
      throw const FormatException('invalid_update_download_url');
    }

    if (info.latestBuild <= currentBuild) return null;
    return info;
  }

  static Future<bool> openDownload(AppUpdateInfo info) async {
    final uri = Uri.parse(info.downloadUrl);
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
