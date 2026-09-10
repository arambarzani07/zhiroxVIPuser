from pathlib import Path
import re
import sys

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('.')

# --- Add Debt: explicit loading/error/retry state ---
add_path = root / 'lib/screens/shared/add_debt_screen.dart'
text = add_path.read_text(encoding='utf-8')

old = "  bool _loadingCustomers = true;\n"
new = "  bool _loadingCustomers = true;\n  String? _customerLoadError;\n"
if old not in text:
    raise RuntimeError('AddDebt customer loading field marker not found')
text = text.replace(old, new, 1)

start = text.index('  Future<void> _loadCustomers() async {')
end = text.index('\n  @override\n  void dispose()', start)
replacement = '''  Future<void> _loadCustomers() async {
    if (mounted) {
      setState(() {
        _loadingCustomers = true;
        _customerLoadError = null;
      });
    }

    try {
      final auth = context.read<AuthProvider>();
      final customers = await PBService.getUsers(
        role: 'customer',
        adminId: auth.adminId,
        approved: true,
      );
      if (!mounted) return;

      setState(() {
        _customers = customers;
        _loadingCustomers = false;
        _customerLoadError = null;

        // If creating new debt and user can't set due date, ensure it's off.
        if (widget.debt == null && !auth.canSetDueDate) {
          _dueDate = null;
          _hasDueDate = false;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _customers = [];
        _loadingCustomers = false;
        _customerLoadError =
            'نەتوانرا لیستی کڕیاران لە سێرڤەر وەربگیرێت. ئینتەرنێت بپشکنە و دووبارە هەوڵ بدە.';
      });
    }
  }
'''
text = text[:start] + replacement + text[end:]

old_save = "  Future<void> _save() async {\n    if (!_formKey.currentState!.validate()) return;"
new_save = """  Future<void> _save() async {
    if (_loadingCustomers || _customerLoadError != null) {
      AppHelpers.showSnackBar(
        context,
        'سەرەتا زانیاریی کڕیاران بە سەرکەوتوویی بار بکە.',
        isError: true,
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;"""
if old_save not in text:
    raise RuntimeError('AddDebt save marker not found')
text = text.replace(old_save, new_save, 1)

picker_start = text.index('          _loadingCustomers\n', text.index('  Widget _buildCustomerSelector()'))
picker_end = text.index('          // Show limit warning if selected', picker_start)
text = text[:picker_start] + '          _buildCustomerPicker(isDark),\n' + text[picker_end:]

helper_marker = '  // Helper to check if customer is already over limit (just for UI indication in dropdown)\n'
if helper_marker not in text:
    raise RuntimeError('AddDebt helper insertion marker not found')
helper = '''  Widget _buildCustomerPicker(bool isDark) {
    if (_loadingCustomers) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
    }

    if (_customerLoadError != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.cloud_off_rounded, color: Colors.orange, size: 20),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    _customerLoadError!,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: isDark
                          ? AppDarkColors.textPrimary
                          : const Color(0xFF344054),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _loadCustomers,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('دووبارە هەوڵ بدە'),
              ),
            ),
          ],
        ),
      );
    }

    if (_customers.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? AppDarkColors.surface : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? AppDarkColors.cardBorder : const Color(0xFFE4E7EC),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.person_off_outlined,
              size: 20,
              color: isDark ? AppDarkColors.textSecondary : Colors.grey.shade600,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'هیچ کڕیارێکی پەسەندکراو بەردەست نییە.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: isDark
                      ? AppDarkColors.textSecondary
                      : const Color(0xFF667085),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final selectedValue = _customers.any((c) => c.id == _selectedCustomerId)
        ? _selectedCustomerId
        : null;

    return DropdownButtonFormField<String>(
      initialValue: selectedValue,
      decoration: InputDecoration(
        filled: true,
        fillColor: isDark ? AppDarkColors.inputFill : Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: isDark
              ? BorderSide(color: AppDarkColors.cardBorder)
              : BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      icon: const Icon(Icons.keyboard_arrow_down_rounded),
      dropdownColor: isDark ? AppDarkColors.card : Colors.white,
      hint: Text(
        'کڕیارێک دیاری بکە',
        style: TextStyle(
          color: isDark ? AppDarkColors.textSecondary : Colors.black54,
        ),
      ),
      items: _customers.map((c) {
        final isOverLimit = _isOverLimit(c);
        return DropdownMenuItem<String>(
          value: c.id,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${c.getStringValue('name')} ${c.getStringValue('father_name')}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: isOverLimit
                        ? Colors.red
                        : (isDark ? AppDarkColors.textPrimary : Colors.black87),
                  ),
                ),
              ),
              if (isOverLimit) ...[
                const SizedBox(width: 8),
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: Colors.red,
                ),
              ],
            ],
          ),
        );
      }).toList(),
      onChanged: widget.debt == null
          ? (v) => setState(() => _selectedCustomerId = v)
          : null,
      validator: (v) => v == null ? 'کڕیارێک هەڵبژێرە' : null,
    );
  }

'''
text = text.replace(helper_marker, helper + helper_marker, 1)

# Add Retry to live balance verification error without ever substituting zero.
old_balance_error = '''            child: const Row(
              children: [
                Icon(Icons.cloud_off_rounded, size: 18, color: Colors.orange),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'نەتوانرا باڵانسی کڕیار پشتڕاست بکرێتەوە. پاشەکەوتکردن تا گەڕانەوەی پەیوەندی ڕادەوەستێت.',
                    style: TextStyle(fontSize: 11.5, height: 1.5),
                  ),
                ),
              ],
            ),'''
new_balance_error = '''            child: Row(
              children: [
                const Icon(Icons.cloud_off_rounded, size: 18, color: Colors.orange),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'نەتوانرا باڵانسی کڕیار پشتڕاست بکرێتەوە. پاشەکەوتکردن تا پشتڕاستکردنەوە ڕادەوەستێت.',
                    style: TextStyle(fontSize: 11.5, height: 1.5),
                  ),
                ),
                IconButton(
                  tooltip: 'دووبارە هەوڵ بدە',
                  onPressed: () => setState(() {}),
                  icon: const Icon(Icons.refresh_rounded, size: 19),
                ),
              ],
            ),'''
if old_balance_error not in text:
    raise RuntimeError('AddDebt balance error marker not found')
text = text.replace(old_balance_error, new_balance_error, 1)

add_path.write_text(text, encoding='utf-8')

# --- Supabase compat: relation context must propagate live-load failures ---
compat_path = root / 'lib/services/supabase_compat.dart'
compat = compat_path.read_text(encoding='utf-8')
ctx_start = compat.index('  Future<_RelationContext> _contextFor(String logicalName) async {')
ctx_end = compat.index('\n  Map<String, dynamic> _writeMap(', ctx_start)
ctx_replacement = '''  Future<_RelationContext> _contextFor(String logicalName) async {
    if (logicalName == 'users') return const _RelationContext();

    // Relation data is part of the live record contract. Never downgrade a
    // failed profiles/debts request to an empty relation context, because that
    // makes a network/database failure look like legitimately missing data.
    final profileData = await _client.from('profiles').select();
    final profiles = (profileData as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    List<Map<String, dynamic>> debts = const [];
    if (logicalName == 'payments') {
      final debtData = await _client.from('debts').select();
      debts = (debtData as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }

    return _RelationContext(
      profiles: {for (final row in profiles) row['id'].toString(): row},
      debts: {for (final row in debts) row['id'].toString(): row},
    );
  }
'''
compat = compat[:ctx_start] + ctx_replacement + compat[ctx_end:]
compat_path.write_text(compat, encoding='utf-8')

# --- Permanent verifier: preserve this behavior in future builds ---
verify_path = root / 'scripts/verify_online_only.py'
verify = verify_path.read_text(encoding='utf-8')
insert_marker = "\n\npb = (LIB / 'services/pb_service.dart').read_text(encoding='utf-8')\n"
if insert_marker not in verify:
    raise RuntimeError('Verifier insertion marker not found')
checks = '''

add_debt = (LIB / 'screens/shared/add_debt_screen.dart').read_text(encoding='utf-8')
for marker in ('_customerLoadError', '_buildCustomerPicker', 'دووبارە هەوڵ بدە'):
    if marker not in add_debt:
        fail(f'lib/screens/shared/add_debt_screen.dart: fail-closed customer loading marker missing: {marker}')
load_match = re.search(
    r'Future<void>\s+_loadCustomers\(\)\s+async\s*\{(.*?)(?=\n\s*@override\n\s*void dispose)',
    add_debt,
    re.S,
)
if not load_match or '_customerLoadError =' not in load_match.group(1):
    fail('lib/screens/shared/add_debt_screen.dart: customer load failures must become an explicit error state')

compat = (LIB / 'services/supabase_compat.dart').read_text(encoding='utf-8')
ctx_match = re.search(
    r'Future<_RelationContext>\s+_contextFor\([^)]*\)\s+async\s*\{(.*?)(?=\n\s*Map<String, dynamic>\s+_writeMap)',
    compat,
    re.S,
)
if not ctx_match:
    fail('lib/services/supabase_compat.dart: relation context loader not found')
elif 'catch' in ctx_match.group(1):
    fail('lib/services/supabase_compat.dart: relation context must not swallow live backend failures')
'''
verify = verify.replace(insert_marker, checks + insert_marker, 1)
verify_path.write_text(verify, encoding='utf-8')

print('Applied fail-closed loading + retry policy')
