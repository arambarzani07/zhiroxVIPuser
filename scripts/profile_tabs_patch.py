from pathlib import Path

path = Path('lib/screens/shared/user_profile_screen.dart')
text = path.read_text()

state_anchor = "  bool _isSaving = false;\n"
if "int _customerSection = 0;" not in text:
    text = text.replace(state_anchor, state_anchor + "  int _customerSection = 0;\n", 1)

start = text.index("  List<Widget> _buildCustomerBody() {")
end = text.index("  // ═══════════════════════════════════════════\n  // ── Customer Chat Timeline ──", start)
replacement = r'''  List<Widget> _buildCustomerBody() {
    final totalDebt = _debts.fold(
      0.0,
      (sum, d) => sum + d.getDoubleValue('amount'),
    );
    final totalRemaining = _debts.fold(
      0.0,
      (sum, d) => sum + d.getDoubleValue('remaining'),
    );
    final totalPaid = totalDebt - totalRemaining;
    final auth = context.read<AuthProvider>();

    final overview = <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: Row(
            children: [
              _buildStatChip(
                Icons.monetization_on_outlined,
                'کۆی قەرز',
                AppHelpers.formatCurrency(totalDebt),
                Colors.orange,
              ),
              const SizedBox(width: 10),
              _buildStatChip(
                Icons.pending_outlined,
                'ماوە',
                AppHelpers.formatCurrency(totalRemaining),
                Colors.red,
              ),
            ],
          ),
        ),
      ),
      if (auth.userRole == 'admin')
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
            child: OutlinedButton.icon(
              onPressed: () => _generateAccountStatement(
                totalDebt: totalDebt,
                totalRemaining: totalRemaining,
                totalPaid: totalPaid,
              ),
              icon: const Icon(Icons.receipt_long_rounded, size: 19),
              label: const Text('کەشف حیساب'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: _accentColor,
                side: BorderSide(color: _accentColor.withOpacity(0.25)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ),
      _buildDebtLimitCard(),
    ];

    final transactions = <Widget>[
      _buildCustomerChatTimelineCard(
        totalDebt: totalDebt,
        totalRemaining: totalRemaining,
        totalPaid: totalPaid,
      ),
    ];

    final edit = <Widget>[
      _buildProfileEditor(),
    ];

    return [
      _buildCustomerSectionTabs(),
      ...switch (_customerSection) {
        1 => transactions,
        2 => edit,
        _ => overview,
      },
    ];
  }

  Widget _buildCustomerSectionTabs() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const labels = ['پوختە', 'مامەڵەکان', 'دەستکاری'];
    const icons = [
      Icons.space_dashboard_outlined,
      Icons.swap_horiz_rounded,
      Icons.edit_outlined,
    ];

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 2),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isDark ? AppDarkColors.card : const Color(0xFFEFF3F8),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: List.generate(labels.length, (index) {
              final selected = _customerSection == index;
              return Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      if (_customerSection == index) return;
                      setState(() => _customerSection = index);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: selected
                            ? (isDark ? AppDarkColors.surface : Colors.white)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: selected && !isDark
                            ? [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            icons[index],
                            size: 17,
                            color: selected
                                ? _accentColor
                                : (isDark
                                    ? AppDarkColors.textSecondary
                                    : Colors.grey[600]),
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              labels[index],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: selected
                                    ? _accentColor
                                    : (isDark
                                        ? AppDarkColors.textSecondary
                                        : Colors.grey[700]),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

'''
text = text[:start] + replacement + text[end:]
path.write_text(text)
