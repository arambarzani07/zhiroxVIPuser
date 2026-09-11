from pathlib import Path

ROOT = Path('.')
LIB = ROOT / 'lib'
PROFILE = LIB / 'screens/shared/user_profile_screen.dart'
DETAIL = LIB / 'screens/shared/debt_detail_screen.dart'
SHARED = LIB / 'screens/shared/financial_document_actions.dart'
VERIFY = ROOT / 'scripts/verify_online_only.py'

shared_source = r'''import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/services/pdf_service.dart';
import 'package:zhirox/utils/helpers.dart';

/// Single source of truth for debt invoices and receipt viewing.
class FinancialDocumentActions {
  FinancialDocumentActions._();

  static String receiptUrl(
    RecordModel debt, {
    String? receiptPath,
  }) {
    final path = (receiptPath ?? debt.getStringValue('receipt_image')).trim();
    if (path.isEmpty) return '';
    return PBService.pb.getFileUrl(debt, path).toString();
  }

  static Future<void> generateDebtInvoice(
    BuildContext context,
    RecordModel debt,
  ) async {
    try {
      final auth = context.read<AuthProvider>();
      var marketName = auth.marketName.trim();
      var adminPhone = auth.user?.getStringValue('phone').trim() ?? '';
      var adminName = auth.userName.trim();

      final adminId = auth.userRole == 'admin' ? auth.userId : auth.adminId;
      if ((marketName.isEmpty || adminPhone.isEmpty || adminName.isEmpty) &&
          adminId.isNotEmpty) {
        try {
          final admin = await PBService.getUser(adminId);
          if (marketName.isEmpty) {
            marketName = admin.getStringValue('market_name').trim();
          }
          if (adminPhone.isEmpty) {
            adminPhone = admin.getStringValue('phone').trim();
          }
          if (adminName.isEmpty) {
            adminName = admin.getStringValue('name').trim();
          }
        } catch (_) {
          // Invoice can still be generated with the authenticated display data.
        }
      }

      if (marketName.isEmpty) marketName = 'Zhirox System';
      if (adminName.isEmpty) adminName = 'ZHIROX';

      await PdfService.generateInvoice(
        debt: debt,
        marketName: marketName,
        adminName: adminName,
        adminPhone: adminPhone,
      );
    } catch (e) {
      if (!context.mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          e,
          fallback: 'نەتوانرا وەصڵ دروست بکرێت. دووبارە هەوڵ بدە.',
        ),
        isError: true,
      );
    }
  }

  static Future<void> openReceiptViewer(
    BuildContext context,
    RecordModel debt, {
    String? receiptPath,
  }) async {
    final imageUrl = receiptUrl(debt, receiptPath: receiptPath);
    if (imageUrl.isEmpty || !context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (viewerContext) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text('وێنەی وەصڵ'),
          ),
          body: SafeArea(
            child: Center(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 5,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'نەتوانرا وێنەی وەصڵ بار بکرێت.',
                      style: TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
'''
SHARED.write_text(shared_source, encoding='utf-8')

# ---- Financial Chat -------------------------------------------------------
profile = PROFILE.read_text(encoding='utf-8')
import_anchor = "import 'package:zhirox/screens/shared/financial_payment_flow.dart';\n"
doc_import = "import 'package:zhirox/screens/shared/financial_document_actions.dart';\n"
if doc_import not in profile:
    if import_anchor not in profile:
        raise SystemExit('Financial Chat import anchor missing')
    profile = profile.replace(import_anchor, import_anchor + doc_import, 1)

profile = profile.replace(
    'final imageUrl = PBService.pb.getFileUrl(debt, receiptPath).toString();',
    'final imageUrl = FinancialDocumentActions.receiptUrl(\n        debt,\n        receiptPath: receiptPath,\n      );',
    1,
)
profile = profile.replace(
    'await _openFinancialReceiptViewer(debt, receiptPath);',
    'await FinancialDocumentActions.openReceiptViewer(\n            context,\n            debt,\n            receiptPath: receiptPath,\n          );',
    1,
)
profile = profile.replace(
    'if (debt != null) await _generateFinancialInvoice(debt);',
    'if (debt != null) {\n          await FinancialDocumentActions.generateDebtInvoice(context, debt);\n        }',
    1,
)
start = profile.find('  Future<void> _openFinancialReceiptViewer(')
end = profile.find('  Future<void> _generateCurrentFinancialStatement()', start)
if start < 0 or end < 0:
    raise SystemExit('Financial Chat document method block not found')
if '_generateFinancialInvoice' not in profile[start:end]:
    raise SystemExit('Financial Chat invoice method not inside expected block')
profile = profile[:start] + profile[end:]
PROFILE.write_text(profile, encoding='utf-8')

# ---- Debt Detail ----------------------------------------------------------
detail = DETAIL.read_text(encoding='utf-8')
detail_anchor = "import 'package:zhirox/screens/shared/financial_payment_flow.dart';\n"
if doc_import not in detail:
    if detail_anchor not in detail:
        raise SystemExit('Debt Detail import anchor missing')
    detail = detail.replace(detail_anchor, detail_anchor + doc_import, 1)
detail = detail.replace("import 'package:zhirox/services/pdf_service.dart';\n", '')

start = detail.find('  Future<void> _printDebtInvoice() async {')
end = detail.find('  Future<void> _editCurrentDebt() async {', start)
if start < 0 or end < 0:
    raise SystemExit('Debt Detail invoice method block not found')
detail = detail[:start] + '''  Future<void> _printDebtInvoice() async {
    final debt = _debt;
    if (debt == null) return;
    await FinancialDocumentActions.generateDebtInvoice(context, debt);
  }

''' + detail[end:]

old_url = '''    final imageUrl = PBService.pb
        .getFileUrl(_debt!, _debt!.getStringValue('receipt_image'))
        .toString();'''
new_url = '''    final imageUrl = FinancialDocumentActions.receiptUrl(_debt!);'''
if old_url not in detail:
    raise SystemExit('Debt Detail receipt URL block not found')
detail = detail.replace(old_url, new_url, 1)
detail = detail.replace(
    'onTap: () => _showReceiptPreview(imageUrl),',
    'onTap: () => FinancialDocumentActions.openReceiptViewer(context, _debt!),',
    1,
)
start = detail.find('  void _showReceiptPreview(String imageUrl) {')
end = detail.find('  Widget _buildPaymentCard(', start)
if start < 0 or end < 0:
    raise SystemExit('Debt Detail receipt viewer block not found')
detail = detail[:start] + detail[end:]
DETAIL.write_text(detail, encoding='utf-8')

# ---- CI guard -------------------------------------------------------------
verify = VERIFY.read_text(encoding='utf-8')
flow_decl = "payment_flow = (LIB / 'screens/shared/financial_payment_flow.dart').read_text(encoding='utf-8')\n"
doc_decl = "document_actions = (LIB / 'screens/shared/financial_document_actions.dart').read_text(encoding='utf-8')\n"
if doc_decl not in verify:
    if flow_decl not in verify:
        raise SystemExit('Verifier payment flow declaration missing')
    verify = verify.replace(flow_decl, flow_decl + doc_decl, 1)

old_phase6 = '''for marker in (
    '_showFinancialTransactionActions',
    '_openFinancialReceiptViewer',
    'InteractiveViewer(',
    'PdfService.generateInvoice(',
    'onTap: () => _showFinancialTransactionActions(item)',
):
    if marker not in profile:
        fail(f'Financial Chat Phase 6 marker missing: {marker}')
'''
new_phase6 = '''for marker in (
    '_showFinancialTransactionActions',
    'FinancialDocumentActions.openReceiptViewer(',
    'FinancialDocumentActions.generateDebtInvoice(',
    'onTap: () => _showFinancialTransactionActions(item)',
):
    if marker not in profile:
        fail(f'Financial Chat Phase 6 marker missing: {marker}')
for marker in (
    'generateDebtInvoice(',
    'receiptUrl(',
    'openReceiptViewer(',
    'PdfService.generateInvoice(',
    'InteractiveViewer(',
    'PBService.pb.getFileUrl(',
):
    if marker not in document_actions:
        fail(f'lib/screens/shared/financial_document_actions.dart: shared document marker missing: {marker}')
for source_name, source in (
    ('lib/screens/shared/user_profile_screen.dart', profile),
    ('lib/screens/shared/debt_detail_screen.dart', debt_detail_source),
):
    if 'PdfService.generateInvoice(' in source:
        fail(f'{source_name}: direct invoice generation duplicates shared document actions')
    if 'InteractiveViewer(' in source:
        fail(f'{source_name}: duplicate receipt viewer must not return')
    if 'PBService.pb.getFileUrl(' in source:
        fail(f'{source_name}: receipt URL resolution must stay centralized')
'''
if old_phase6 not in verify:
    raise SystemExit('Verifier Phase 6 block changed unexpectedly')
verify = verify.replace(old_phase6, new_phase6, 1)
VERIFY.write_text(verify, encoding='utf-8')

print('Financial invoice/receipt actions deduplicated.')
