from pathlib import Path
import re


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f'{label}: marker not found')
    return text.replace(old, new, 1)


def regex_once(text: str, pattern: str, repl: str, label: str) -> str:
    updated, count = re.subn(pattern, repl, text, count=1, flags=re.S)
    if count == 1:
        return updated
    if repl.strip() in text:
        return text
    raise SystemExit(f'{label}: regex marker not found')


# ---------- PBService ----------
pb_path = Path('lib/services/pb_service.dart')
pb = pb_path.read_text()

if 'String? referenceKind,' not in pb[pb.find('static Future<RecordModel> createDebt'):pb.find('// ==================== Payments')]:
    pb = re.sub(
        r'(static Future<RecordModel> createDebt\(\{.*?String\? receiptImagePath,\n)(\s*\}\) async \{)',
        r'\1    String? referenceKind,\n    String? referenceId,\n\2',
        pb,
        count=1,
        flags=re.S,
    )

pb = replace_once(
    pb,
    "      if (receiptPath.isNotEmpty) 'receipt_image': receiptPath,\n    };",
    "      if (receiptPath.isNotEmpty) 'receipt_image': receiptPath,\n      if (referenceKind != null &&\n          referenceKind.isNotEmpty &&\n          referenceId != null &&\n          referenceId.isNotEmpty)\n        'reference_kind': referenceKind,\n      if (referenceKind != null &&\n          referenceKind.isNotEmpty &&\n          referenceId != null &&\n          referenceId.isNotEmpty)\n        'reference_id': referenceId,\n    };",
    'createDebt reference body',
)

payment_start = pb.find('static Future<RecordModel> createPayment')
if payment_start < 0:
    raise SystemExit('createPayment not found')
payment_end = pb.find('// ====================', payment_start + 10)
if payment_end < 0:
    payment_end = len(pb)
payment_block = pb[payment_start:payment_end]
if 'String? referenceKind,' not in payment_block:
    payment_block = payment_block.replace(
        '    String? createdByName,\n  }) async {',
        '    String? createdByName,\n    String? referenceKind,\n    String? referenceId,\n  }) async {',
        1,
    )
    if 'String? referenceKind,' not in payment_block:
        raise SystemExit('createPayment signature marker not found')

payment_block = replace_once(
    payment_block,
    "      'p_note': note ?? '',\n    },",
    "      'p_note': note ?? '',\n      'p_reference_kind': referenceKind,\n      'p_reference_id': referenceId,\n    },",
    'createPayment RPC params',
)
pb = pb[:payment_start] + payment_block + pb[payment_end:]
pb_path.write_text(pb)


# ---------- AddDebtScreen ----------
add_path = Path('lib/screens/shared/add_debt_screen.dart')
add = add_path.read_text()
add = replace_once(
    add,
    "  final String? customerId;\n  final RecordModel? debt;\n\n  const AddDebtScreen({super.key, this.customerId, this.debt});",
    "  final String? customerId;\n  final RecordModel? debt;\n  final String? referenceKind;\n  final String? referenceId;\n\n  const AddDebtScreen({\n    super.key,\n    this.customerId,\n    this.debt,\n    this.referenceKind,\n    this.referenceId,\n  });",
    'AddDebt reference constructor',
)
add = replace_once(
    add,
    "          receiptImagePath: _receiptImage?.path,\n        );",
    "          receiptImagePath: _receiptImage?.path,\n          referenceKind: widget.referenceKind,\n          referenceId: widget.referenceId,\n        );",
    'AddDebt create reference args',
)
add_path.write_text(add)


# ---------- UserProfile Financial Chat ----------
profile_path = Path('lib/screens/shared/user_profile_screen.dart')
profile = profile_path.read_text()
profile = replace_once(
    profile,
    "  String _financialTypeFilter = 'all';\n\n  final _nameController",
    "  String _financialTypeFilter = 'all';\n  _ProfileTimelineItem? _financialReplyTarget;\n\n  final _nameController",
    'reply target state',
)

profile = replace_once(
    profile,
    "                    if (isPayment && relatedDebt != null) ...[\n                      const SizedBox(height: 7),\n                      _buildPaymentDebtReference(relatedDebt, color, isDark),\n                    ],",
    "                    if (_financialReferenceSnapshot(record) != null) ...[\n                      const SizedBox(height: 7),\n                      _buildPersistentFinancialReference(record, color, isDark),\n                    ],\n                    if (isPayment && relatedDebt != null) ...[\n                      const SizedBox(height: 7),\n                      _buildPaymentDebtReference(relatedDebt, color, isDark),\n                    ],",
    'bubble persisted reference',
)

reference_helpers = r'''  Map<String, dynamic>? _financialReferenceSnapshot(RecordModel record) {
    final raw = record.toJson()['reference_snapshot'];
    if (raw is Map && raw.isNotEmpty) {
      return Map<String, dynamic>.from(raw);
    }
    return null;
  }

  String _financialReplyLabel(_ProfileTimelineItem item) {
    final isPayment = item.isPayment;
    final record = item.record;
    final amount = record.getDoubleValue('amount');
    final relatedCurrency = item.relatedDebt?.getStringValue('currency') ?? '';
    final ownCurrency = record.getStringValue('currency');
    final currency = (isPayment ? relatedCurrency : ownCurrency).trim().isEmpty
        ? 'IQD'
        : (isPayment ? relatedCurrency : ownCurrency);
    final text = (isPayment
            ? record.getStringValue('note')
            : record.getStringValue('description'))
        .trim();
    final amountText = AppHelpers.formatCurrencyWithType(amount, currency);
    final prefix = isPayment ? 'پارەدانەوە' : 'قەرز';
    return text.isEmpty ? '$prefix • $amountText' : '$prefix • $amountText • $text';
  }

  Widget _buildPersistentFinancialReference(
    RecordModel record,
    Color accent,
    bool isDark,
  ) {
    final snapshot = _financialReferenceSnapshot(record);
    if (snapshot == null) return const SizedBox.shrink();

    final kind = snapshot['kind']?.toString() ?? '';
    final amount = double.tryParse('${snapshot['amount'] ?? 0}') ?? 0;
    final currency = (snapshot['currency']?.toString() ?? '').trim().isEmpty
        ? 'IQD'
        : snapshot['currency'].toString();
    final text = snapshot['text']?.toString().trim() ?? '';
    final label = kind == 'payment' ? 'وەڵام بۆ پارەدانەوە' : 'وەڵام بۆ قەرز';
    final amountText = AppHelpers.formatCurrencyWithType(amount, currency);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.055)
            : Colors.white.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          right: BorderSide(color: accent.withValues(alpha: 0.72), width: 3),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.reply_rounded, size: 14, color: accent),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  text.isEmpty ? amountText : '$amountText • $text',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppDarkColors.textSecondary
                        : const Color(0xFF475467),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

'''
if '_financialReferenceSnapshot(RecordModel record)' not in profile:
    marker = '  Widget _buildReceiptPreview(\n'
    if marker not in profile:
        raise SystemExit('receipt preview insertion marker not found')
    profile = profile.replace(marker, reference_helpers + marker, 1)

# Transaction action sheet: add auth context and Reply item.
profile = replace_once(
    profile,
    "    final debt = item.isPayment ? item.relatedDebt : item.record;\n    final receiptPath = debt?.getStringValue('receipt_image').trim() ?? '';\n    final action = await showModalBottomSheet<String>(",
    "    final debt = item.isPayment ? item.relatedDebt : item.record;\n    final receiptPath = debt?.getStringValue('receipt_image').trim() ?? '';\n    final auth = context.read<AuthProvider>();\n    final action = await showModalBottomSheet<String>(",
    'transaction actions auth',
)
profile = replace_once(
    profile,
    "              if (receiptPath.isNotEmpty)\n                ListTile(\n                  leading: const Icon(Icons.image_outlined),",
    "              if (auth.userRole != 'customer')\n                ListTile(\n                  leading: const Icon(Icons.reply_rounded),\n                  title: const Text('وەک وەڵام / پەیوەستکردن'),\n                  subtitle: const Text('مامەڵەی نوێ بە ئەم مامەڵەیەوە ببەستە'),\n                  onTap: () => Navigator.pop(sheetContext, 'reference'),\n                ),\n              if (receiptPath.isNotEmpty)\n                ListTile(\n                  leading: const Icon(Icons.image_outlined),",
    'transaction reference action',
)
profile = replace_once(
    profile,
    "    switch (action) {\n      case 'details':",
    "    switch (action) {\n      case 'reference':\n        if (mounted) {\n          setState(() => _financialReplyTarget = item);\n          _jumpToLatest();\n        }\n        break;\n      case 'details':",
    'transaction reference switch',
)

# Replace composer with a reply-aware composer.
composer_pattern = r"  Widget _buildFinancialChatComposer\(AuthProvider auth, bool isDark\) \{.*?\n  Future<void> _openAddDebtFromChat\(\) async \{"
composer_replacement = r'''  Widget _buildFinancialChatComposer(AuthProvider auth, bool isDark) {
    final totalRemaining = _debts.fold<double>(
      0,
      (sum, debt) => sum + debt.getDoubleValue('remaining'),
    );
    final replyTarget = _financialReplyTarget;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
        decoration: BoxDecoration(
          color: isDark ? AppDarkColors.card : Colors.white,
          border: Border(
            top: BorderSide(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : const Color(0xFFE4E7EC),
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.05),
              blurRadius: 18,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (replyTarget != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: isDark ? 0.12 : 0.07),
                  borderRadius: BorderRadius.circular(11),
                  border: Border(
                    right: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.65),
                      width: 3,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.reply_rounded, size: 17, color: AppColors.primary),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'پەیوەست بە مامەڵەی پێشوو',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                          Text(
                            _financialReplyLabel(replyTarget),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? AppDarkColors.textSecondary
                                  : const Color(0xFF475467),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'لابردنی پەیوەندی',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _financialReplyTarget = null),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _openAddDebtFromChat,
                    icon: const Icon(Icons.add_rounded, size: 19),
                    label: const Text('قەرز زیاد بکە'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: totalRemaining > 0
                        ? () => _showFinancialPaymentSheet(auth)
                        : null,
                    icon: const Icon(Icons.payments_outlined, size: 18),
                    label: const Text('پارەدانەوە'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      foregroundColor: Colors.green.shade700,
                      side: BorderSide(
                        color: totalRemaining > 0
                            ? Colors.green.withValues(alpha: 0.32)
                            : const Color(0xFFD0D5DD),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAddDebtFromChat() async {'''
if 'پەیوەست بە مامەڵەی پێشوو' not in profile:
    profile, count = re.subn(composer_pattern, composer_replacement, profile, count=1, flags=re.S)
    if count != 1:
        raise SystemExit('composer replacement marker not found')

profile = replace_once(
    profile,
    "        builder: (_) => AddDebtScreen(customerId: widget.userId),",
    "        builder: (_) => AddDebtScreen(\n          customerId: widget.userId,\n          referenceKind: _financialReplyTarget == null\n              ? null\n              : (_financialReplyTarget!.isPayment ? 'payment' : 'debt'),\n          referenceId: _financialReplyTarget?.record.id,\n        ),",
    'AddDebt reply pass-through',
)

profile = replace_once(
    profile,
    "                                    createdByName: auth.userName,\n                                  );",
    "                                    createdByName: auth.userName,\n                                    referenceKind: _financialReplyTarget == null\n                                        ? null\n                                        : (_financialReplyTarget!.isPayment\n                                            ? 'payment'\n                                            : 'debt'),\n                                    referenceId: _financialReplyTarget?.record.id,\n                                  );",
    'payment reply pass-through',
)

# Clear reply only after a successful mutation refresh. This covers both debt and payment flows.
if 'setState(() => _financialReplyTarget = null);\n      await _refreshFinancialData(autoJump: true);' not in profile:
    profile = profile.replace(
        '      await _refreshFinancialData(autoJump: true);',
        '      if (mounted && _financialReplyTarget != null) {\n        setState(() => _financialReplyTarget = null);\n      }\n      await _refreshFinancialData(autoJump: true);',
    )

profile_path.write_text(profile)


# ---------- Permanent source verifier ----------
verify_path = Path('scripts/verify_online_only.py')
verify = verify_path.read_text()
phase7_guard = r'''

# Financial Chat reply/reference must be persisted server-side, not kept as
# ephemeral UI-only state.
profile_source = (LIB / 'screens/shared/user_profile_screen.dart').read_text(encoding='utf-8')
for marker in ('_financialReplyTarget', 'referenceKind:', 'referenceId:', 'reference_snapshot', 'وەک وەڵام / پەیوەستکردن'):
    if marker not in profile_source:
        fail(f'lib/screens/shared/user_profile_screen.dart: persistent Financial Chat reference marker missing: {marker}')
for marker in ('referenceKind', 'referenceId', "'p_reference_kind'", "'p_reference_id'"):
    if marker not in pb:
        fail(f'lib/services/pb_service.dart: persistent financial reference marker missing: {marker}')
for marker in ('referenceKind', 'referenceId'):
    if marker not in add_debt:
        fail(f'lib/screens/shared/add_debt_screen.dart: debt reference pass-through missing: {marker}')
'''
if 'Financial Chat reply/reference must be persisted server-side' not in verify:
    verify = verify.replace('\n\nif violations:\n', phase7_guard + '\n\nif violations:\n', 1)
verify_path.write_text(verify)
