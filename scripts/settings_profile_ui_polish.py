from pathlib import Path
import re

profile_path = Path('lib/screens/shared/user_profile_screen.dart')
dash_path = Path('lib/screens/admin/admin_dashboard.dart')

# ── Shared profile header: one visual language + one overflow action menu ──
text = profile_path.read_text()

# Unify customer/employee profile header colors.
text = re.sub(
    r"colors: _isEmployee\n\s*\? \[const Color\(0xFF4A6CF7\), const Color\(0xFF6B8CFF\)\]\n\s*: \[\n\s*AppColors\.primary,\n\s*AppColors\.primary\.withOpacity\(0\.85\),\n\s*\],",
    "colors: [AppColors.primary, AppColors.primary.withOpacity(0.88)],",
    text,
    count=1,
)
text = text.replace(
    "bottomLeft: Radius.circular(32),\n                  bottomRight: Radius.circular(32),",
    "bottomLeft: Radius.circular(24),\n                  bottomRight: Radius.circular(24),",
    1,
)

# Consolidate notification/theme/logout/delete actions into one menu.
actions_pattern = re.compile(
    r"\n\s*if \(_isCustomer &&\n\s*auth\.userId != widget\.userId &&\n\s*auth\.canSendNotifications\) \.\.\.\[.*?\n\s*else if \(auth\.userRole == 'admin'\) \.\.\.\[.*?\n\s*\],",
    re.S,
)
actions_replacement = r'''
                          if ((_isCustomer &&
                                  auth.userId != widget.userId &&
                                  auth.canSendNotifications) ||
                              (auth.userId == widget.userId && _isEmployee) ||
                              auth.userId == widget.userId ||
                              (auth.userRole == 'admin' &&
                                  auth.userId != widget.userId)) ...[
                            const SizedBox(width: 6),
                            PopupMenuButton<String>(
                              tooltip: 'کردارەکان',
                              color: isDark ? AppDarkColors.card : Colors.white,
                              surfaceTintColor: Colors.transparent,
                              elevation: 6,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              icon: Container(
                                width: 36,
                                height: 36,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(11),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.14),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.more_horiz_rounded,
                                  color: Colors.white,
                                  size: 21,
                                ),
                              ),
                              onSelected: (value) async {
                                if (value == 'notify') {
                                  _showNotificationDialog();
                                  return;
                                }
                                if (value == 'theme') {
                                  context.read<ThemeProvider>().toggleTheme();
                                  return;
                                }
                                if (value == 'logout') {
                                  final confirm = await AppHelpers.showConfirmDialog(
                                    context,
                                    title: AppStrings.logout,
                                    message: 'دڵنیایت لە چوونەدەرەوە؟',
                                  );
                                  if (confirm && mounted) await auth.logout();
                                  return;
                                }
                                if (value == 'delete') {
                                  _confirmDelete();
                                }
                              },
                              itemBuilder: (_) => [
                                if (_isCustomer &&
                                    auth.userId != widget.userId &&
                                    auth.canSendNotifications)
                                  const PopupMenuItem<String>(
                                    value: 'notify',
                                    child: Row(
                                      children: [
                                        Icon(Icons.notifications_none_rounded, size: 19),
                                        SizedBox(width: 10),
                                        Text('ناردنی ئاگادارکردنەوە'),
                                      ],
                                    ),
                                  ),
                                if (auth.userId == widget.userId && _isEmployee)
                                  PopupMenuItem<String>(
                                    value: 'theme',
                                    child: Row(
                                      children: [
                                        Icon(
                                          isDark
                                              ? Icons.light_mode_outlined
                                              : Icons.dark_mode_outlined,
                                          size: 19,
                                        ),
                                        const SizedBox(width: 10),
                                        Text(isDark ? 'ڕووناکی' : 'دۆخی تاریک'),
                                      ],
                                    ),
                                  ),
                                if (auth.userId == widget.userId)
                                  const PopupMenuItem<String>(
                                    value: 'logout',
                                    child: Row(
                                      children: [
                                        Icon(Icons.logout_rounded, size: 19),
                                        SizedBox(width: 10),
                                        Text('چوونەدەرەوە'),
                                      ],
                                    ),
                                  ),
                                if (auth.userRole == 'admin' &&
                                    auth.userId != widget.userId)
                                  const PopupMenuItem<String>(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete_outline_rounded,
                                            size: 19, color: Colors.red),
                                        SizedBox(width: 10),
                                        Text('سڕینەوە',
                                            style: TextStyle(color: Colors.red)),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],'''
text, count = actions_pattern.subn(actions_replacement, text, count=1)
if count != 1:
    raise SystemExit('profile action block not found')

# Compact profile identity area.
text = text.replace(
    "padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),",
    "padding: const EdgeInsets.fromLTRB(20, 2, 20, 20),",
    1,
)
text = text.replace("width: 80,\n                            height: 80,", "width: 68,\n                            height: 68,", 1)
text = text.replace("borderRadius: BorderRadius.circular(24),", "borderRadius: BorderRadius.circular(20),", 1)
text = text.replace("fontSize: 34,", "fontSize: 28,", 1)
text = text.replace("const SizedBox(height: 14),\n                          Text(\n                            name,", "const SizedBox(height: 10),\n                          Text(\n                            name,", 1)
text = text.replace("fontSize: 24,\n                              fontWeight: FontWeight.bold,", "fontSize: 21,\n                              fontWeight: FontWeight.w800,", 1)
profile_path.write_text(text)

# ── Admin Settings bottom sheet and dialogs ──────────────────────────────────
text = dash_path.read_text()
text = text.replace("maxHeight: MediaQuery.of(ctx).size.height * 0.82,", "maxHeight: MediaQuery.of(ctx).size.height * 0.74,", 1)
text = text.replace(
    "padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),",
    "padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),",
    1,
)
text = text.replace("width: 46,\n                      height: 46,", "width: 40,\n                      height: 40,", 1)
text = text.replace("size: 23,", "size: 20,", 1)
text = text.replace("const SizedBox(height: 18),\n                _settingsTile(", "const SizedBox(height: 12),\n                _settingsTile(", 1)

# Compact every settings row using the shared helper only.
text = text.replace("padding: const EdgeInsets.only(bottom: 6),", "padding: const EdgeInsets.only(bottom: 2),", 1)
text = text.replace(
    "padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),",
    "padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),",
    1,
)
text = text.replace("width: 42,\n                  height: 42,", "width: 38,\n                  height: 38,", 1)
text = text.replace("child: Icon(icon, color: iconColor, size: 21),", "child: Icon(icon, color: iconColor, size: 19),", 1)
text = text.replace("const SizedBox(width: 12),", "const SizedBox(width: 10),", 1)

# Standardize dialog geometry; keep behavior unchanged.
text = text.replace(
    "shape: RoundedRectangleBorder(\n              borderRadius: BorderRadius.circular(20),\n            ),",
    "insetPadding: const EdgeInsets.symmetric(horizontal: 20),\n            shape: RoundedRectangleBorder(\n              borderRadius: BorderRadius.circular(16),\n            ),",
    2,
)
# Remove raw backend errors from the two profile-change dialogs.
text = text.replace(
    "'هەڵە: $e',\n                              isError: true,",
    "'نەتوانرا گۆڕانکاری پاشەکەوت بکرێت',\n                              isError: true,",
    2,
)

dash_path.write_text(text)
