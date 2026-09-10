from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old in text:
        return text.replace(old, new, 1)
    if new in text:
        return text
    raise SystemExit(f'{label}: marker not found')

path = Path('lib/screens/shared/user_profile_screen.dart')
text = path.read_text(encoding='utf-8')

# A chat message tap now opens its contextual action sheet. Detail remains one tap
# away inside the sheet and mutations stay in the dedicated transaction screens.
text = replace_once(
    text,
    "              onTap: () => _openTimelineItem(item),\n              borderRadius:",
    "              onTap: () => _showFinancialTransactionActions(item),\n              onLongPress: () => _showFinancialTransactionActions(item),\n              borderRadius:",
    'bubble action entry',
)

if 'Future<void> _showFinancialTransactionActions(' not in text:
    marker = "  Future<void> _generateAccountStatement({\n"
    addition = r'''  Future<void> _showFinancialTransactionActions(
    _ProfileTimelineItem item,
  ) async {
    if (item.isSystem || !mounted) return;

    final debt = item.isPayment ? item.relatedDebt : item.record;
    final receiptPath = debt?.getStringValue('receipt_image').trim() ?? '';
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
        final amount = item.record.getDoubleValue('amount');
        final currency = debt?.getStringValue('currency').isNotEmpty == true
            ? debt!.getStringValue('currency')
            : 'IQD';
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppDarkColors.card : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD0D5DD),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                leading: CircleAvatar(
                  backgroundColor: (item.isPayment ? Colors.green : Colors.orange)
                      .withValues(alpha: 0.10),
                  child: Icon(
                    item.isPayment
                        ? Icons.south_west_rounded
                        : Icons.north_east_rounded,
                    color: item.isPayment ? Colors.green.shade700 : Colors.orange.shade800,
                    size: 19,
                  ),
                ),
                title: Text(
                  item.isPayment ? 'پارەدانەوە' : 'قەرز',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  AppHelpers.formatCurrencyWithType(amount, currency),
                  textDirection: TextDirection.ltr,
                ),
              ),
              const Divider(height: 12),
              ListTile(
                leading: const Icon(Icons.open_in_new_rounded),
                title: const Text('وردەکاری مامەڵە'),
                onTap: () => Navigator.pop(sheetContext, 'details'),
              ),
              if (receiptPath.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.image_outlined),
                  title: const Text('بینینی وەصڵ'),
                  subtitle: const Text('گەورەکردن و جوڵاندنی وێنە'),
                  onTap: () => Navigator.pop(sheetContext, 'receipt'),
                ),
              if (debt != null)
                ListTile(
                  leading: const Icon(Icons.print_outlined),
                  title: const Text('چاپکردنی وەصڵ / Invoice'),
                  onTap: () => Navigator.pop(sheetContext, 'invoice'),
                ),
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('کەشف حیساب'),
                onTap: () => Navigator.pop(sheetContext, 'statement'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;
    switch (action) {
      case 'details':
        await _openTimelineItem(item);
        break;
      case 'receipt':
        if (debt != null && receiptPath.isNotEmpty) {
          await _openFinancialReceiptViewer(debt, receiptPath);
        }
        break;
      case 'invoice':
        if (debt != null) await _generateFinancialInvoice(debt);
        break;
      case 'statement':
        await _generateCurrentFinancialStatement();
        break;
    }
  }

  Future<void> _openFinancialReceiptViewer(
    RecordModel debt,
    String receiptPath,
  ) async {
    if (!mounted || receiptPath.isEmpty) return;
    final imageUrl = PBService.pb.getFileUrl(debt, receiptPath).toString();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (viewerContext) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
            title: const Text('وەصڵ'),
          ),
          body: SafeArea(
            child: Center(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 5,
                boundaryMargin: const EdgeInsets.all(48),
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const SizedBox(
                      width: 42,
                      height: 42,
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'وێنەی وەصڵ بار نەبوو. پەیوەندی ئینتەرنێت بپشکنە.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70),
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

  Future<void> _generateFinancialInvoice(RecordModel debt) async {
    final auth = context.read<AuthProvider>();
    try {
      await PdfService.generateInvoice(
        debt: debt,
        marketName: auth.marketName,
        adminName: auth.userName,
        adminPhone: auth.user?.getStringValue('phone') ?? '',
      );
    } catch (e) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          e,
          fallback: 'وەصڵ دروست نەکرا. دووبارە هەوڵ بدە.',
        ),
        isError: true,
      );
    }
  }

  Future<void> _generateCurrentFinancialStatement() async {
    final totalDebt = _debts.fold<double>(
      0,
      (sum, debt) => sum + debt.getDoubleValue('amount'),
    );
    final totalRemaining = _debts.fold<double>(
      0,
      (sum, debt) => sum + debt.getDoubleValue('remaining'),
    );
    await _generateAccountStatement(
      totalDebt: totalDebt,
      totalRemaining: totalRemaining,
      totalPaid: totalDebt - totalRemaining,
    );
  }

'''
    if marker not in text:
        raise SystemExit('statement marker not found')
    text = text.replace(marker, addition + marker, 1)

path.write_text(text, encoding='utf-8')

verify_path = Path('scripts/verify_online_only.py')
verify = verify_path.read_text(encoding='utf-8')
needle = "if 'DebtProvider' in customer_list_source:\n    fail('Customer list must not own debt/payment mutation logic')\n"
addition = """
for marker in (
    '_showFinancialTransactionActions',
    '_openFinancialReceiptViewer',
    'InteractiveViewer(',
    'PdfService.generateInvoice(',
    'onTap: () => _showFinancialTransactionActions(item)',
):
    if marker not in profile:
        fail(f'Financial Chat Phase 6 marker missing: {marker}')
"""
if addition.strip() not in verify:
    if needle not in verify:
        raise SystemExit('phase 6 verifier marker not found')
    verify = verify.replace(needle, needle + addition, 1)
verify_path.write_text(verify, encoding='utf-8')
