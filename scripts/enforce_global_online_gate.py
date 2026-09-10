from pathlib import Path
import re
import sys


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('.')

auth = root / 'lib/providers/auth_provider.dart'
text = auth.read_text()
text = text.replace("import 'dart:convert';\n\n", '')
text = text.replace("import 'package:flutter_secure_storage/flutter_secure_storage.dart';\n", '')
text = text.replace("  static const _secureStorage = FlutterSecureStorage();\n\n", '')
text = re.sub(r"^\s*await _cacheUser\(\);\n", '', text, flags=re.M)
text, count = re.subn(
    r"\n  Future<void> _cacheUser\(\) async \{.*?\n  \}\n\n  Future<void> _clearLocalUser\(\) async \{\n    _user = null;\n    await _secureStorage\.delete\(key: 'user_id'\);\n    await _secureStorage\.delete\(key: 'user_data'\);\n  \}",
    "\n  Future<void> _clearLocalUser() async {\n    _user = null;\n  }",
    text,
    flags=re.S,
)
require(count == 1, f'auth cache block replacement count={count}')
text = text.replace(
    "      // ZHIROX is online-only: never restore an authenticated app session\n      // from cached profile data when the server profile cannot be verified.\n",
    "      // ZHIROX is online-only: a persisted Supabase session is accepted only\n      // after the current server profile and subscription are verified online.\n",
)
require('FlutterSecureStorage' not in text, 'FlutterSecureStorage remains')
require('_cacheUser' not in text, '_cacheUser remains')
require("key: 'user_data'" not in text, 'user_data secure cache remains')
auth.write_text(text)

main = root / 'lib/main.dart'
text = main.read_text()
require('_ConnectivityBanner(child: child!)' in text, 'old connectivity builder missing')
text = text.replace('_ConnectivityBanner(child: child!)', '_OnlineOnlyGate(child: child!)')
start = text.find('class _ConnectivityBanner extends StatefulWidget')
require(start >= 0, 'old connectivity banner class missing')
replacement = r'''class _OnlineOnlyGate extends StatefulWidget {
  final Widget child;
  const _OnlineOnlyGate({required this.child});

  @override
  State<_OnlineOnlyGate> createState() => _OnlineOnlyGateState();
}

class _OnlineOnlyGateState extends State<_OnlineOnlyGate> {
  late StreamSubscription<bool> _sub;
  bool _isOnline = ConnectivityService.instance.isOnline;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _sub = ConnectivityService.instance.statusStream.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  Future<void> _retry() async {
    if (_checking) return;
    setState(() => _checking = true);
    final online = await ConnectivityService.instance.checkNow();
    if (!mounted) return;
    setState(() {
      _isOnline = online;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isOnline) return widget.child;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background =
        isDark ? AppDarkColors.background : const Color(0xFFF7F8FA);
    final surface = isDark ? AppDarkColors.card : Colors.white;
    final border =
        isDark ? AppDarkColors.cardBorder : const Color(0xFFEAECF0);
    final primaryText =
        isDark ? AppDarkColors.textPrimary : const Color(0xFF1D2939);
    final secondaryText =
        isDark ? AppDarkColors.textSecondary : const Color(0xFF667085);

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            ignoring: true,
            child: widget.child,
          ),
        ),
        Positioned.fill(
          child: Material(
            color: background,
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: border),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 58,
                            height: 58,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(17),
                            ),
                            child: const Icon(
                              Icons.wifi_off_rounded,
                              color: Colors.orange,
                              size: 29,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'پەیوەندی ئینتەرنێت پێویستە',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: primaryText,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'ژیرۆکس تەنها بە شێوەی ئۆنلاین کار دەکات. پەیوەندی ئینتەرنێتەکەت بپشکنە و دووبارە هەوڵ بدە.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: secondaryText,
                              fontSize: 12.5,
                              height: 1.7,
                            ),
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _checking ? null : _retry,
                              icon: _checking
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.refresh_rounded, size: 19),
                              label: Text(
                                _checking
                                    ? 'دەچێتەوە...'
                                    : 'دووبارە هەوڵ بدە',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
'''
main.write_text(text[:start] + replacement)

pub = root / 'pubspec.yaml'
p = pub.read_text()
p = p.replace('  flutter_secure_storage: ^10.0.0\n', '')
require('flutter_secure_storage:' not in p, 'secure storage dependency remains')
pub.write_text(p)
