from pathlib import Path
import sys

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('.')
lib = root / 'lib'


def replace_required(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'missing expected source block: {label}')
    return text.replace(old, new)

# Centralize PocketBase single-relation expansion access through the modern get() API.
helpers_path = lib / 'utils/helpers.dart'
helpers = helpers_path.read_text(encoding='utf-8')
if "package:pocketbase/pocketbase.dart" not in helpers:
    helpers = helpers.replace(
        "import 'package:intl/intl.dart' hide TextDirection;\n",
        "import 'package:intl/intl.dart' hide TextDirection;\nimport 'package:pocketbase/pocketbase.dart';\n",
        1,
    )
marker = """  // هەڵەی backend/network بە پەیامێکی ڕوون و بێ وردەکاریی ناوخۆیی دەگۆڕێت.\n"""
if 'static RecordModel? expandedRecord' not in helpers:
    helper_method = """  // Modern PocketBase relation accessor. A missing or forbidden expansion stays null.\n  static RecordModel? expandedRecord(RecordModel record, String relation) {\n    return record.get<RecordModel>('expand.$relation', null);\n  }\n\n"""
    if marker not in helpers:
        raise SystemExit('helpers insertion marker missing')
    helpers = helpers.replace(marker, helper_method + marker, 1)
helpers_path.write_text(helpers, encoding='utf-8')

# Supabase compatibility records should mirror PocketBase single-relation JSON shape.
compat_path = lib / 'services/supabase_compat.dart'
compat = compat_path.read_text(encoding='utf-8')
for old, new in (
    ("expand['customer'] = [_recordJson('users', customer, ctx)];", "expand['customer'] = _recordJson('users', customer, ctx);"),
    ("expand['created_by'] = [_recordJson('users', creator, ctx)];", "expand['created_by'] = _recordJson('users', creator, ctx);"),
    ("expand['debt'] = [_recordJson('debts', debt, ctx)];", "expand['debt'] = _recordJson('debts', debt, ctx);"),
    ("expand['sender'] = [_recordJson('users', sender, ctx)];", "expand['sender'] = _recordJson('users', sender, ctx);"),
):
    compat = compat.replace(old, new)
compat_path.write_text(compat, encoding='utf-8')

# Admin recent activity: modern expansion accessor.
admin_path = lib / 'screens/admin/admin_dashboard.dart'
admin = admin_path.read_text(encoding='utf-8')
old = """    final customers = debt.expand['customer'];\n    final customer = (customers != null && customers.isNotEmpty)\n        ? customers.first\n        : null;\n    final creators = debt.expand['created_by'];\n    final createdBy = (creators != null && creators.isNotEmpty)\n        ? creators.first\n        : null;\n"""
new = """    final customer = AppHelpers.expandedRecord(debt, 'customer');\n    final createdBy = AppHelpers.expandedRecord(debt, 'created_by');\n"""
admin = replace_required(admin, old, new, 'admin activity expansions')
admin_path.write_text(admin, encoding='utf-8')

# Pending requests: Dart wildcard parameters.
pending_path = lib / 'screens/admin/pending_requests_screen.dart'
pending = pending_path.read_text(encoding='utf-8').replace(
    'separatorBuilder: (_, __) => const SizedBox(height: 8),',
    'separatorBuilder: (_, _) => const SizedBox(height: 8),',
)
pending_path.write_text(pending, encoding='utf-8')

# Debt detail: modern expansion/date access + wildcard parameters.
detail_path = lib / 'screens/shared/debt_detail_screen.dart'
detail = detail_path.read_text(encoding='utf-8')
old = """    String customerName = '';\n    final expanded = _debt!.expand;\n    if (expanded.containsKey('customer') && expanded['customer']!.isNotEmpty) {\n      customerName = expanded['customer']!.first.getStringValue('name');\n    }\n"""
new = """    final customer = AppHelpers.expandedRecord(_debt!, 'customer');\n    final customerName = customer?.getStringValue('name') ?? '';\n"""
detail = replace_required(detail, old, new, 'debt detail customer expansion')
detail = detail.replace("_debt!.created", "_debt!.getStringValue('created')")
detail = detail.replace('errorBuilder: (_, __, ___) =>', 'errorBuilder: (_, _, _) =>')
detail_path.write_text(detail, encoding='utf-8')

# Debt list is now direct-debt only. Remove the obsolete grouped-customer/bulk-payment path.
debt_list_path = lib / 'screens/shared/debt_list_screen.dart'
debt_list = debt_list_path.read_text(encoding='utf-8')
debt_list = debt_list.replace('  List<_CustomerInfo> _customers = [];\n', '')
debt_list = debt_list.replace('  bool _isPaying = false;\n', '')
debt_list = debt_list.replace(
    """  void _debouncedReload() {\n    if (_isPaying || !mounted) return;\n    _debounceTimer?.cancel();\n    _debounceTimer = Timer(const Duration(milliseconds: 800), () {\n      if (mounted && !_isPaying) _loadAllDebts();\n    });\n  }\n""",
    """  void _debouncedReload() {\n    if (!mounted) return;\n    _debounceTimer?.cancel();\n    _debounceTimer = Timer(const Duration(milliseconds: 800), () {\n      if (mounted) _loadAllDebts();\n    });\n  }\n""",
)
debt_list = debt_list.replace('        _extractCustomers();\n', '')
debt_list = debt_list.replace('        _customers = [];\n', '')

legacy_start = debt_list.find('  /// Instantly updates local state, then syncs with server in background')
visible_start = debt_list.find('  List<RecordModel> _visibleDebts() {', legacy_start)
if legacy_start == -1 or visible_start == -1:
    raise SystemExit('legacy grouped customer block not found')
debt_list = debt_list[:legacy_start] + debt_list[visible_start:]

# Modern expansion/date access in the direct debt list.
debt_list = debt_list.replace(
    "final customer = debt.expand['customer']?.first;",
    "final customer = AppHelpers.expandedRecord(debt, 'customer');",
)
debt_list = debt_list.replace(
    "final aName = a.expand['customer']?.first.getStringValue('name') ?? '';",
    "final aName = AppHelpers.expandedRecord(a, 'customer')?.getStringValue('name') ?? '';",
)
debt_list = debt_list.replace(
    "final bName = b.expand['customer']?.first.getStringValue('name') ?? '';",
    "final bName = AppHelpers.expandedRecord(b, 'customer')?.getStringValue('name') ?? '';",
)
debt_list = debt_list.replace('b.created.compareTo(a.created)', "b.getStringValue('created').compareTo(a.getStringValue('created'))")
debt_list = debt_list.replace('debt.created', "debt.getStringValue('created')")

# Remove obsolete bulk pay dialog.
pay_dialog_start = debt_list.find('  // ── Pay Dialog (centered) ──')
single_dialog_marker = debt_list.find('  // ── Single Payment Dialog (centered) ──', pay_dialog_start)
if pay_dialog_start == -1 or single_dialog_marker == -1:
    raise SystemExit('bulk pay dialog markers missing')
# Include the surrounding separator comment before the bulk block, but keep the single-dialog separator.
section_start = debt_list.rfind('  // ═══════════════════════════════════════════', 0, pay_dialog_start)
debt_list = debt_list[:section_start] + '  // ═══════════════════════════════════════════\n' + debt_list[single_dialog_marker:]

# Single-payment success should refresh the actual direct debt rows from the server.
old_success = """                          // Instantly update UI\n                          if (mounted) {\n                            Navigator.pop(ctx);\n                            AppHelpers.showSnackBar(\n                              context,\n                              'پارەدانەوە تۆمارکرا',\n                            );\n                            _applyOptimisticUpdate(\n                              customerId,\n                              storageAmount,\n                              fullyPaidCount: storageAmount >= remaining\n                                  ? 1\n                                  : 0,\n                            );\n                          }\n"""
new_success = """                          if (!mounted) return;\n                          if (ctx.mounted) Navigator.pop(ctx);\n                          AppHelpers.showSnackBar(\n                            context,\n                            'پارەدانەوە تۆمارکرا',\n                          );\n                          await _loadAllDebts(showLoading: false);\n"""
debt_list = replace_required(debt_list, old_success, new_success, 'single debt payment refresh')
debt_list = debt_list.replace(
    """                          if (mounted) {\n                            AppHelpers.showSnackBar(\n                              context,\n                              'هەڵە: $e',\n                              isError: true,\n                            );\n                          }\n""",
    """                          if (!mounted) return;\n                          AppHelpers.showSnackBar(\n                            context,\n                            AppHelpers.backendErrorMessage(\n                              e,\n                              fallback: 'نەتوانرا پارەدانەوە تۆمار بکرێت. دووبارە هەوڵ بدە.',\n                            ),\n                            isError: true,\n                          );\n""",
)

# customerId was needed only by the removed optimistic customer-summary state.
debt_list = debt_list.replace("    String customerId = debt.getStringValue('customer');\n\n", '')

# Remove bulk distribution methods; quick-pay input helpers remain for single debt payments.
smart_start = debt_list.find('  // ── Smart Distribution Logic ──')
helpers_marker = debt_list.find('  // ── Helpers ──', smart_start)
if smart_start == -1 or helpers_marker == -1:
    raise SystemExit('smart distribution markers missing')
smart_section_start = debt_list.rfind('  // ═══════════════════════════════════════════', 0, smart_start)
debt_list = debt_list[:smart_section_start] + '  // ═══════════════════════════════════════════\n' + debt_list[helpers_marker:]

# Remove obsolete grouped-customer models while retaining the number formatter.
model_start = debt_list.find('class _CustomerInfo')
formatter_marker = debt_list.find('/// Formats number input with thousand separators (commas)', model_start)
if model_start == -1 or formatter_marker == -1:
    raise SystemExit('legacy debt-list model markers missing')
debt_list = debt_list[:model_start] + debt_list[formatter_marker:]

debt_list_path.write_text(debt_list, encoding='utf-8')

# User profile: modern created accessor and async-context safety.
profile_path = lib / 'screens/shared/user_profile_screen.dart'
profile = profile_path.read_text(encoding='utf-8')
profile = profile.replace(
    """    final created = record.getStringValue('created').isNotEmpty\n        ? record.getStringValue('created')\n        : record.created;\n""",
    """    final created = record.getStringValue('created');\n""",
)

# Dialog-context guards for debt-limit mutations.
profile = profile.replace(
    """                  await PBService.updateUser(widget.userId, {'debt_limit': 0});\n                  if (mounted) {\n                    Navigator.pop(dialogContext);\n                    AppHelpers.showSnackBar(context, 'سنوری قەرز لابرا');\n                    _loadData();\n                  }\n""",
    """                  await PBService.updateUser(widget.userId, {'debt_limit': 0});\n                  if (!mounted || !dialogContext.mounted) return;\n                  Navigator.pop(dialogContext);\n                  AppHelpers.showSnackBar(context, 'سنوری قەرز لابرا');\n                  _loadData();\n""",
)
profile = profile.replace(
    """                if (mounted) {\n                  Navigator.pop(dialogContext);\n                  AppHelpers.showSnackBar(\n                    context,\n                    newLimit > 0\n                        ? 'سنوری قەرز دانرا: ${AppHelpers.formatCurrency(newLimit)}'\n                        : 'سنوری قەرز لابرا',\n                  );\n                  _loadData();\n                }\n""",
    """                if (!mounted || !dialogContext.mounted) return;\n                Navigator.pop(dialogContext);\n                AppHelpers.showSnackBar(\n                  context,\n                  newLimit > 0\n                      ? 'سنوری قەرز دانرا: ${AppHelpers.formatCurrency(newLimit)}'\n                      : 'سنوری قەرز لابرا',\n                );\n                _loadData();\n""",
)

# After a live balance await, guard State.context before opening the confirm dialog.
profile = profile.replace(
    """    final confirm = await AppHelpers.showConfirmDialog(\n      context,\n      title: _isCustomer ? 'سڕینەوەی کڕیار' : 'سڕینەوەی کارمەند',\n""",
    """    if (!mounted) return;\n    final confirm = await AppHelpers.showConfirmDialog(\n      context,\n      title: _isCustomer ? 'سڕینەوەی کڕیار' : 'سڕینەوەی کارمەند',\n""",
)

# Notification dialog: distinguish dialog BuildContext from State.context and guard both.
profile = profile.replace('builder: (context) => AlertDialog(\n        title: const Text(\'ناردنی ئاگادارکردنەوە\'),', "builder: (dialogContext) => AlertDialog(\n        title: const Text('ناردنی ئاگادارکردنەوە'),")
# Scope only the notification dialog tail by replacing its distinctive operations.
profile = profile.replace(
    """            onPressed: () => Navigator.pop(context),\n            child: const Text('پاشگەزبوونەوە'),\n          ),\n          ElevatedButton(\n            onPressed: () async {\n              if (controller.text.trim().isEmpty) return;\n              try {\n                // Remove await to not block UI, or keep it if we want to show snackbar after success\n                // Using await for better UX feedback\n                await PBService.createNotification(\n                  customerId: widget.userId,\n                  message: controller.text.trim(),\n                  senderId: context.read<AuthProvider>().userId,\n                );\n                if (mounted) {\n                  Navigator.pop(context);\n                  AppHelpers.showSnackBar(context, 'ئاگادارکردنەوە نێردرا');\n                }\n              } catch (e) {\n                if (mounted) {\n                  AppHelpers.showSnackBar(context, AppHelpers.backendErrorMessage(e), isError: true);\n                }\n              }\n            },\n""",
    """            onPressed: () => Navigator.pop(dialogContext),\n            child: const Text('پاشگەزبوونەوە'),\n          ),\n          ElevatedButton(\n            onPressed: () async {\n              if (controller.text.trim().isEmpty) return;\n              final senderId = context.read<AuthProvider>().userId;\n              try {\n                await PBService.createNotification(\n                  customerId: widget.userId,\n                  message: controller.text.trim(),\n                  senderId: senderId,\n                );\n                if (!mounted || !dialogContext.mounted) return;\n                Navigator.pop(dialogContext);\n                AppHelpers.showSnackBar(context, 'ئاگادارکردنەوە نێردرا');\n              } catch (e) {\n                if (!mounted) return;\n                AppHelpers.showSnackBar(\n                  context,\n                  AppHelpers.backendErrorMessage(e),\n                  isError: true,\n                );\n              }\n            },\n""",
)
profile_path.write_text(profile, encoding='utf-8')

# PDF service: deprecated RecordModel created/updated/expand accessors.
pdf_path = lib / 'services/pdf_service.dart'
pdf = pdf_path.read_text(encoding='utf-8')
pdf = pdf.replace('activity.created', "activity.getStringValue('created')")
pdf = pdf.replace('activity.updated', "activity.getStringValue('updated')")
pdf = pdf.replace('debt.created', "debt.getStringValue('created')")
pdf = pdf.replace('debt.updated', "debt.getStringValue('updated')")
pdf = pdf.replace(
    "activity.expand['customer']?.first",
    "AppHelpers.expandedRecord(activity, 'customer')",
)
pdf = pdf.replace(
    "debt.expand['customer']?.first",
    "AppHelpers.expandedRecord(debt, 'customer')",
)
pdf_path.write_text(pdf, encoding='utf-8')

# Sanity checks for the warning families targeted in this stage.
checks = {
    'admin_dashboard.dart': admin_path.read_text(encoding='utf-8'),
    'debt_detail_screen.dart': detail_path.read_text(encoding='utf-8'),
    'debt_list_screen.dart': debt_list_path.read_text(encoding='utf-8'),
    'user_profile_screen.dart': profile_path.read_text(encoding='utf-8'),
    'pdf_service.dart': pdf_path.read_text(encoding='utf-8'),
}
for name, source in checks.items():
    if '.expand[' in source:
        raise SystemExit(f'{name}: deprecated .expand access remains')

for forbidden in ('_showPayDialog(', '_calculateDistribution(', '_payAllDebts(', 'class _PayDistribution', 'class _CustomerInfo'):
    if forbidden in checks['debt_list_screen.dart']:
        raise SystemExit(f'debt_list_screen.dart: obsolete grouped flow remains: {forbidden}')

print('Modern RecordModel and async-context cleanup applied.')
