from pathlib import Path
import re

path = Path('lib/screens/admin/admin_dashboard.dart')
text = path.read_text()

# Put pending request count where it belongs: on the navigation destination.
old = "    final isDark = Theme.of(context).brightness == Brightness.dark;\n\n    final screens = ["
new = "    final isDark = Theme.of(context).brightness == Brightness.dark;\n    final pendingNavCount = (_stats['pendingRequests'] as num?)?.toInt() ?? 0;\n\n    final screens = ["
if old not in text:
    raise SystemExit('build anchor not found')
text = text.replace(old, new, 1)

old_call = """                _buildNavItem(
                  4,
                  Icons.pending_actions_outlined,
                  Icons.pending_actions,
                  'داواکان',
                ),"""
new_call = """                _buildNavItem(
                  4,
                  Icons.pending_actions_outlined,
                  Icons.pending_actions,
                  'داواکان',
                  badgeCount: pendingNavCount,
                ),"""
if old_call not in text:
    raise SystemExit('pending nav call not found')
text = text.replace(old_call, new_call, 1)

old_sig = """  Widget _buildNavItem(
    int index,
    IconData icon,
    IconData activeIcon,
    String label,
  ) {"""
new_sig = """  Widget _buildNavItem(
    int index,
    IconData icon,
    IconData activeIcon,
    String label, {
    int badgeCount = 0,
  }) {"""
if old_sig not in text:
    raise SystemExit('nav signature not found')
text = text.replace(old_sig, new_sig, 1)

old_icon = """                  Icon(
                    isSelected ? activeIcon : icon,
                    size: 22,
                    color: isSelected ? AppColors.primary : inactiveColor,
                  ),"""
new_icon = """                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        isSelected ? activeIcon : icon,
                        size: 22,
                        color: isSelected ? AppColors.primary : inactiveColor,
                      ),
                      if (badgeCount > 0)
                        Positioned(
                          top: -6,
                          right: -9,
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 17),
                            height: 17,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.red.shade600,
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                color: isDark ? AppDarkColors.card : Colors.white,
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              badgeCount > 99 ? '99+' : '$badgeCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8.5,
                                fontWeight: FontWeight.w800,
                                height: 1,
                              ),
                              textDirection: TextDirection.ltr,
                            ),
                          ),
                        ),
                    ],
                  ),"""
if old_icon not in text:
    raise SystemExit('nav icon block not found')
text = text.replace(old_icon, new_icon, 1)

# Dashboard should not repeat the same pending-request destination as a large card.
text = text.replace(
    "    final pendingCount = _stats['pendingRequests'] as int? ?? 0;\n",
    "",
    1,
)
pattern = re.compile(
    r"\n          // ───── Pending Requests Alert ─────.*?\n          // ───── Recent Activity Header ─────",
    re.S,
)
text, count = pattern.subn(
    "\n\n          // ───── Recent Activity Header ─────",
    text,
    count=1,
)
if count != 1:
    raise SystemExit('pending alert block not found')

# Make the subscription warning a compact status strip instead of a second hero card.
replacements = {
    "padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),": "padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),",
    "padding: const EdgeInsets.symmetric(\n                            horizontal: 14,\n                            vertical: 12,\n                          ),": "padding: const EdgeInsets.symmetric(\n                            horizontal: 12,\n                            vertical: 9,\n                          ),",
    "color: const Color(0xCCE53935),": "color: Colors.white.withValues(alpha: 0.10),",
    "color: Colors.red[300]!.withOpacity(0.6),": "color: Colors.white.withValues(alpha: 0.16),",
    """                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
""": "",
    "color: Colors.white.withOpacity(0.2),\n                                  borderRadius: BorderRadius.circular(10),": "color: Colors.white.withOpacity(0.10),\n                                  borderRadius: BorderRadius.circular(9),",
    "color: Colors.white,\n                                  size: 22,": "color: Colors.amberAccent,\n                                  size: 20,",
}
for old, new in replacements.items():
    if old in text:
        text = text.replace(old, new, 1)

# Compact section header / empty state.
text = text.replace(
    "padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),",
    "padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),",
    1,
)
text = text.replace("size: 20,\n                    color: isDark", "size: 18,\n                    color: isDark", 1)
text = text.replace("fontSize: 18,\n                      fontWeight: FontWeight.bold,", "fontSize: 15,\n                      fontWeight: FontWeight.w800,", 1)
text = text.replace(
    "padding: const EdgeInsets.all(40),\n                child: Column(\n                  children: [\n                    Icon(Icons.history, size: 48, color: Colors.grey[300]),",
    "padding: const EdgeInsets.symmetric(vertical: 30),\n                child: Column(\n                  children: [\n                    Icon(Icons.history_rounded, size: 32, color: Colors.grey[300]),",
    1,
)

# Replace animated/shadow-heavy activity cards with compact financial rows.
pattern = re.compile(r"  Widget _buildActivityCard\(RecordModel debt, int index\) \{.*?\n  \}\n\}", re.S)
new_activity = r'''  Widget _buildActivityCard(RecordModel debt, int index) {
    final customers = debt.expand['customer'];
    final customer = (customers != null && customers.isNotEmpty)
        ? customers.first
        : null;
    final creators = debt.expand['created_by'];
    final createdBy = (creators != null && creators.isNotEmpty)
        ? creators.first
        : null;

    final amount = debt.getDoubleValue('amount');
    final date = debt.getStringValue('created');
    final isByEmployee = createdBy?.getStringValue('role') == 'employee';
    final creatorName = createdBy?.getStringValue('name') ?? '';
    final customerName =
        customer?.getStringValue('name') ?? 'کڕیار سڕدراوەتەوە';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isByEmployee ? Colors.orange : AppColors.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFE9EDF3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isByEmployee ? Icons.badge_outlined : Icons.receipt_long_outlined,
              color: accent,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppDarkColors.textPrimary
                        : const Color(0xFF344054),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (isByEmployee && creatorName.isNotEmpty) creatorName,
                    AppHelpers.formatDate(date),
                  ].join('  •  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark
                        ? AppDarkColors.textSecondary
                        : const Color(0xFF98A2B3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            AppHelpers.formatCurrency(amount),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: isDark
                  ? AppDarkColors.textPrimary
                  : const Color(0xFF101828),
            ),
            textDirection: TextDirection.ltr,
          ),
        ],
      ),
    );
  }
}'''
text, count = pattern.subn(new_activity, text, count=1)
if count != 1:
    raise SystemExit('activity card function not found')

path.write_text(text)
