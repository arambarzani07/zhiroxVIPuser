import 'dart:io';

void main() {
  final repoRoot = Directory.current;

  final changes = <_Replacement>[
    _Replacement(
      'lib/services/pb_service.dart',
      "            'password_text': password,\n",
      '',
      description: 'Stop storing plaintext password_text during user creation',
      replaceAll: true,
    ),
    _Replacement(
      'lib/services/pb_service.dart',
      "        // If PB update fails, fallback to password_text\n"
      "        await pb.collection('users').update(userId, body: {\n"
      "          'password_text': newPassword,\n"
      "        });",
      "        throw Exception(\n"
      "          'ناتوانرێت وشەی نهێنی نوێ بکرێتەوە. تکایە دووبارە داخڵ ببەوە و هەوڵبدەرەوە.',\n"
      "        );",
      description: 'Block fallback plaintext password update after PB auth update failure',
    ),
    _Replacement(
      'lib/services/pb_service.dart',
      "        // PB password sync failed → keep password_text as fallback for login\n"
      "        await pb.collection('users').update(userId, body: {\n"
      "          'password_text': newPassword,\n"
      "        });",
      "        throw Exception(\n"
      "          'ناتوانرێت وشەی نهێنی لە ڕێگای سەلامەتەوە نوێ بکرێتەوە.',\n"
      "        );",
      description: 'Block legacy plaintext password fallback when PB password sync fails',
    ),
    _Replacement(
      'lib/screens/shared/user_profile_screen.dart',
      "      _passwordController.text = _user!.getStringValue('password_text');",
      '      _passwordController.clear();',
      description: 'Stop loading plaintext password into profile controller',
      replaceAll: true,
    ),
    _Replacement(
      'lib/screens/shared/user_profile_screen.dart',
      "    if (_passwordController.text.length < 8) {\n"
      "      AppHelpers.showSnackBar(\n"
      "        context,\n"
      "        'وشەی نهێنی لانیکەم ٨ پیت بێت',\n"
      "        isError: true,\n"
      "      );\n"
      "      return;\n"
      "    }",
      "    if (_passwordController.text.trim().isNotEmpty) {\n"
      "      AppHelpers.showSnackBar(\n"
      "        context,\n"
      "        'گۆڕینی وشەی نهێنی بە شێوەی سەلامەت لە قۆناغی داهاتوودا زیاد دەکرێت.',\n"
      "        isError: true,\n"
      "      );\n"
      "      return;\n"
      "    }",
      description: 'Prevent profile form from accepting password edits through password_text',
    ),
    _Replacement(
      'lib/screens/shared/user_profile_screen.dart',
      "\n      // Update password_text if password field is not empty\n"
      "      if (_passwordController.text.isNotEmpty) {\n"
      "        data['password_text'] = _passwordController.text;\n"
      "      }\n",
      "\n      // Password changes must use a dedicated secure auth flow.\n",
      description: 'Stop writing password_text from profile save',
    ),
  ];

  var applied = 0;
  for (final change in changes) {
    final file = File('${repoRoot.path}/${change.path}');
    if (!file.existsSync()) {
      stderr.writeln('Missing file: ${change.path}');
      exitCode = 1;
      return;
    }

    final before = file.readAsStringSync();
    if (!before.contains(change.from)) {
      stderr.writeln('Pattern not found in ${change.path}: ${change.description}');
      exitCode = 1;
      return;
    }

    final after = change.replaceAll
        ? before.replaceAll(change.from, change.to)
        : before.replaceFirst(change.from, change.to);

    file.writeAsStringSync(after);
    applied++;
    stdout.writeln('Applied: ${change.description}');
  }

  stdout.writeln('Password cleanup phase 1 applied: $applied replacements.');
  stdout.writeln('Next checks: dart format lib/services/pb_service.dart lib/screens/shared/user_profile_screen.dart && flutter analyze');
}

class _Replacement {
  final String path;
  final String from;
  final String to;
  final String description;
  final bool replaceAll;

  const _Replacement(
    this.path,
    this.from,
    this.to, {
    required this.description,
    this.replaceAll = false,
  });
}
