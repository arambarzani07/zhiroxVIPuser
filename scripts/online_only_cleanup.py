from pathlib import Path
import re


def require(condition: bool, message: str):
    if not condition:
        raise RuntimeError(message)

# --- Customer list: never turn a failed balance request into a fake zero balance.
path = Path('lib/screens/shared/user_list_screen.dart')
text = path.read_text()

if 'final Set<String> _balanceErrors' not in text:
    text = text.replace(
        '  final Map<String, double> _balances = {};\n',
        '  final Map<String, double> _balances = {};\n  final Set<String> _balanceErrors = <String>{};\n',
    )

text = text.replace(
    "          _balances[user.id] = balance;\n        } catch (_) {\n          _balances[user.id] = 0;\n",
    "          _balances[user.id] = balance;\n          _balanceErrors.remove(user.id);\n        } catch (_) {\n          _balances.remove(user.id);\n          _balanceErrors.add(user.id);\n",
)

text = text.replace(
    "    final balance = _balances[user.id] ?? 0;\n",
    "    final balance = _balances[user.id] ?? 0;\n    final balanceUnavailable = _balanceErrors.contains(user.id);\n",
)

text = text.replace(
    "                          _balances.containsKey(user.id)\n                              ? 'ماوە: ${AppHelpers.formatCurrency(balance)}'\n                              : 'ماوە: ...',\n",
    "                          balanceUnavailable\n                              ? 'ماوە: نەتوانرا باربکرێت'\n                              : _balances.containsKey(user.id)\n                                  ? 'ماوە: ${AppHelpers.formatCurrency(balance)}'\n                                  : 'ماوە: ...',\n",
)

text = text.replace(
    "                            color: !_balances.containsKey(user.id)\n                                ? Colors.grey[400]\n                                : balance > 0\n                                    ? Colors.red[500]\n                                    : Colors.green[500],\n",
    "                            color: balanceUnavailable\n                                ? Colors.orange[500]\n                                : !_balances.containsKey(user.id)\n                                    ? Colors.grey[400]\n                                    : balance > 0\n                                        ? Colors.red[500]\n                                        : Colors.green[500],\n",
)

require('_balanceErrors.add(user.id)' in text, 'customer balance error patch missing')
path.write_text(text)

# --- Customer/employee profile: online-only single-flight load, no partially stale profile on failure.
path = Path('lib/screens/shared/user_profile_screen.dart')
text = path.read_text()

if 'bool _loadInFlight = false;' not in text:
    text = text.replace(
        '  bool _isSaving = false;\n',
        '  bool _isSaving = false;\n  bool _loadInFlight = false;\n',
    )

pattern = re.compile(r"  Future<void> _loadData\(\) async \{.*?\n  \}\n\n  Future<void> _toggleActive", re.S)
replacement = '''  Future<void> _loadData() async {
    if (!mounted || _loadInFlight) return;
    _loadInFlight = true;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final user = await PBService.getUser(widget.userId);
      final role = user.getStringValue('role');

      List<RecordModel> debts = [];
      List<RecordModel> payments = [];
      Map<String, double> employeeStats = {};

      if (role == 'customer') {
        final customerData = await Future.wait<List<RecordModel>>([
          PBService.getDebts(customerId: widget.userId),
          PBService.getPayments(customerId: widget.userId),
        ]);
        debts = customerData[0];
        payments = customerData[1];
      } else if (role == 'employee') {
        employeeStats = await PBService.getEmployeeStats(widget.userId);
      }

      if (!mounted) return;
      setState(() {
        _user = user;
        _debts = debts;
        _payments = payments;
        _employeeStats = employeeStats;
        _nameController.text = user.getStringValue('name');
        _phoneController.text = user.getStringValue('phone');
        _passwordController.text = user.getStringValue('password_text');

        if (role == 'employee') {
          _canAddCustomers = user.getBoolValue('can_add_customers');
          _canSetDebtLimit = user.getBoolValue('can_set_debt_limit');
          _canSetDueDate = user.getBoolValue('can_set_due_date');
          _canEditDebts = user.getBoolValue('can_edit_debts');
          _canSendNotifications = user.getBoolValue('can_send_notifications');
        }

        _isLoading = false;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _user = null;
        _debts = [];
        _payments = [];
        _employeeStats = {};
        _isLoading = false;
        _loadError =
            'نەتوانرا زانیارییەکانی پروفایل باربکرێن. پەیوەندی ئینتەرنێت بپشکنە.';
      });
    } finally {
      _loadInFlight = false;
    }
  }

  Future<void> _toggleActive'''
text, count = pattern.subn(replacement, text, count=1)
require(count == 1, f'profile load patch count={count}')
path.write_text(text)

# --- Debt list: remove persistent offline cache and surface connection failure explicitly.
path = Path('lib/screens/shared/debt_list_screen.dart')
text = path.read_text()
text = text.replace("import 'dart:convert';\n", '')
text = text.replace("import 'package:shared_preferences/shared_preferences.dart';\n", '')

if 'String? _loadError;' not in text:
    text = text.replace(
        '  bool _isPaying = false;\n',
        '  bool _isPaying = false;\n  bool _loadInFlight = false;\n  String? _loadError;\n',
    )

text = text.replace(
    "  void dispose() {\n    _connectivitySub?.cancel();\n",
    "  void dispose() {\n    _connectivitySub?.cancel();\n    try {\n      PBService.pb.collection('debts').unsubscribe();\n      PBService.pb.collection('payments').unsubscribe();\n    } catch (_) {}\n",
)

pattern = re.compile(r"  Future<void> _loadAllDebts\(\{bool showLoading = true\}\) async \{.*?\n  \}\n\n  /// Instantly updates local state", re.S)
replacement = '''  Future<void> _loadAllDebts({bool showLoading = true}) async {
    if (!mounted || _loadInFlight) return;
    _loadInFlight = true;

    if (showLoading || _allDebts.isEmpty) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      final auth = context.read<AuthProvider>();
      final debts = await PBService.getDebts(
        adminId: auth.adminId,
        perPage: 500,
      );
      if (!mounted) return;
      setState(() {
        _allDebts = debts;
        _loadError = null;
        _extractCustomers();
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _allDebts = [];
        _customers = [];
        _isLoading = false;
        _loadError =
            'نەتوانرا لیستی قەرزەکان باربکرێت. پەیوەندی ئینتەرنێت بپشکنە.';
      });
    } finally {
      _loadInFlight = false;
    }
  }

  /// Instantly updates local state'''
text, count = pattern.subn(replacement, text, count=1)
require(count == 1, f'debt load patch count={count}')

text = text.replace(
    "              else if (visibleDebts.isEmpty)\n",
    "              else if (_loadError != null)\n                SliverFillRemaining(\n                  hasScrollBody: false,\n                  child: _buildLoadErrorState(),\n                )\n              else if (visibleDebts.isEmpty)\n",
    1,
)

marker = "  // ═══════════════════════════════════════════\n  // ── Sort Chip ──"
if 'Widget _buildLoadErrorState()' not in text:
    helper = '''  Widget _buildLoadErrorState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded, size: 42, color: Colors.orange[400]),
            const SizedBox(height: 12),
            Text(
              _loadError ?? 'نەتوانرا لیستی قەرزەکان باربکرێت.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: isDark
                    ? AppDarkColors.textSecondary
                    : const Color(0xFF667085),
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _loadAllDebts,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('دووبارە هەوڵ بدە'),
            ),
          ],
        ),
      ),
    );
  }

'''
    require(marker in text, 'debt helper insertion marker missing')
    text = text.replace(marker, helper + marker, 1)

require('SharedPreferences' not in text, 'persistent debt cache still present')
require('jsonDecode' not in text and 'jsonEncode' not in text, 'debt JSON cache still present')
require('Widget _buildLoadErrorState()' in text, 'debt error state missing')
path.write_text(text)

print('online-only cleanup applied')
