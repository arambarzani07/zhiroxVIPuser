from pathlib import Path
import re


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old in text:
        return text.replace(old, new, 1)
    if new in text:
        return text
    raise SystemExit(f'{label}: marker not found')

# --- User profile: allow customer list to open Financial Chat directly ---
profile_path = Path('lib/screens/shared/user_profile_screen.dart')
profile = profile_path.read_text(encoding='utf-8')
profile = replace_once(
    profile,
    "class UserProfileScreen extends StatefulWidget {\n  final String userId;\n\n  const UserProfileScreen({super.key, required this.userId});",
    "class UserProfileScreen extends StatefulWidget {\n  final String userId;\n  final bool openFinancialChat;\n\n  const UserProfileScreen({\n    super.key,\n    required this.userId,\n    this.openFinancialChat = false,\n  });",
    'profile constructor',
)
profile = replace_once(
    profile,
    "  int _customerSection = 0;",
    "  late int _customerSection;",
    'customer section state',
)
profile = replace_once(
    profile,
    "  void initState() {\n    super.initState();\n    _loadData();",
    "  void initState() {\n    super.initState();\n    _customerSection = widget.openFinancialChat ? 1 : 0;\n    _loadData();",
    'profile init section',
)
profile = replace_once(
    profile,
    "        _isLoading = false;\n        _loadError = null;\n      });\n    } catch (_) {",
    "        _isLoading = false;\n        _loadError = null;\n      });\n      if (role == 'customer' && _customerSection == 1) {\n        WidgetsBinding.instance.addPostFrameCallback((_) {\n          if (mounted) _jumpToLatest(animated: false);\n        });\n      }\n    } catch (_) {",
    'initial chat jump',
)
profile_path.write_text(profile, encoding='utf-8')

# --- Customer list: tap opens Financial Chat; remove duplicate payment dialog ---
list_path = Path('lib/screens/shared/user_list_screen.dart')
text = list_path.read_text(encoding='utf-8')
text = text.replace("import 'package:flutter/services.dart';\n", '')
text = text.replace("import 'package:zhirox/providers/debt_provider.dart';\n", '')
text = replace_once(
    text,
    "                builder: (_) => UserProfileScreen(userId: user.id),",
    "                builder: (_) => UserProfileScreen(\n                  userId: user.id,\n                  openFinancialChat: widget.role == 'customer',\n                ),",
    'customer card direct chat',
)
text = replace_once(
    text,
    "                      } else if (value == 'payment') {\n                        _showPaymentDialog(user);\n                      }",
    "                      } else if (value == 'payment') {\n                        Navigator.push(\n                          context,\n                          MaterialPageRoute(\n                            builder: (_) => UserProfileScreen(\n                              userId: user.id,\n                              openFinancialChat: true,\n                            ),\n                          ),\n                        ).then((_) => _loadUsers());\n                      }",
    'payment routes to chat',
)

# Remove legacy list-level quick payment dialog and its formatter. Financial Chat owns payment now.
pattern = re.compile(
    r"\n  Future<void> _showPaymentDialog\(RecordModel user\) async \{.*?\n  \}\n\}\n\nclass _ThousandsInputFormatter extends TextInputFormatter \{.*?\n\}\n?\Z",
    re.S,
)
match = pattern.search(text)
if match:
    text = text[:match.start()] + "\n}\n"
elif '_showPaymentDialog(RecordModel user)' in text or '_ThousandsInputFormatter' in text:
    raise SystemExit('legacy payment cleanup shape changed')

list_path.write_text(text, encoding='utf-8')

# Durable verifier checks the consolidated information architecture.
verify_path = Path('scripts/verify_online_only.py')
verify = verify_path.read_text(encoding='utf-8')
marker = "print('Online-only policy verification passed.')"
checks = r'''# Financial Chat must remain the single customer debt/payment workspace.
profile_source = (ROOT / 'lib/screens/shared/user_profile_screen.dart').read_text(encoding='utf-8')
customer_list_source = (ROOT / 'lib/screens/shared/user_list_screen.dart').read_text(encoding='utf-8')
require('openFinancialChat' in profile_source, 'Customer profile must support direct Financial Chat entry')
require('openFinancialChat: widget.role == \'customer\'' in customer_list_source,
        'Customer list tap must open Financial Chat directly')
require('_showPaymentDialog(RecordModel user)' not in customer_list_source,
        'Customer list must not duplicate payment recording outside Financial Chat')
require('DebtProvider' not in customer_list_source,
        'Customer list must not own debt/payment mutation logic')

'''
if checks.strip() not in verify:
    if marker not in verify:
        raise SystemExit('verifier marker not found')
    verify = verify.replace(marker, checks + marker, 1)
verify_path.write_text(verify, encoding='utf-8')
