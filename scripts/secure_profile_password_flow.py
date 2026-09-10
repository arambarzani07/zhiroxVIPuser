from pathlib import Path
import re
import sys


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('.')

# --- PBService: add an authorized tenant-admin password reset helper.
pb = root / 'lib/services/pb_service.dart'
text = pb.read_text()
needle = """  static Future<void> deleteUser(String id) async {
"""
require(needle in text, 'PBService deleteUser insertion point missing')
method = """  static Future<void> resetUserPassword({
    required String userId,
    required String newPassword,
  }) async {
    await ensureInitialized();
    if (newPassword.length < 8) {
      throw Exception('وشەی نهێنی لانیکەم ٨ پیت بێت');
    }
    try {
      final response = await client.functions.invoke(
        'account-admin',
        body: {
          'action': 'reset_password',
          'user_id': userId,
          'new_password': newPassword,
        },
      );
      if (response.data is Map && response.data['error'] != null) {
        throw _functionError(response.data);
      }
    } on FunctionsException catch (e) {
      throw _functionError(e.details ?? e.reasonPhrase ?? e.status);
    }
  }

"""
require('static Future<void> resetUserPassword' not in text, 'resetUserPassword already exists')
text = text.replace(needle, method + needle)
pb.write_text(text)

# --- Profile UI: remove fake password_text editing and use secure auth flows.
profile = root / 'lib/screens/shared/user_profile_screen.dart'
text = profile.read_text()
for old in [
    "  final _passwordController = TextEditingController();\n",
    "  bool _obscurePassword = true;\n",
    "    _passwordController.dispose();\n",
    "        _passwordController.text = user.getStringValue('password_text');\n",
]:
    require(old in text, f'missing profile snippet: {old.strip()}')
    text = text.replace(old, '')

validation = """    if (_passwordController.text.length < 8) {
      AppHelpers.showSnackBar(
        context,
        'وشەی نهێنی لانیکەم ٨ پیت بێت',
        isError: true,
      );
      return;
    }

"""
require(validation in text, 'password validation block missing')
text = text.replace(validation, '')

password_write = """      // Update password_text if password field is not empty
      if (_passwordController.text.isNotEmpty) {
        data['password_text'] = _passwordController.text;
      }


"""
require(password_write in text, 'password_text write block missing')
text = text.replace(password_write, '')

insert_point = """  // ═══════════════════════════════════════════
  // ── Shared Profile Editor ──
  // ═══════════════════════════════════════════

  Widget _buildProfileEditor() {
"""
require(insert_point in text, 'profile editor insertion point missing')
helpers = r'''  // ═══════════════════════════════════════════
  // ── Secure Password Management ──
  // ═══════════════════════════════════════════

  String _friendlyPasswordError(Object error) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('network') ||
        raw.contains('socketexception') ||
        raw.contains('clientexception') ||
        raw.contains('connection')) {
      return 'پەیوەندی بە سێرڤەر نەکرا. ئینتەرنێتەکەت بپشکنە.';
    }
    if (raw.contains('old') || raw.contains('کۆن')) {
      return 'وشەی نهێنیی کۆن هەڵەیە.';
    }
    if (raw.contains('forbidden') ||
        raw.contains('permission') ||
        raw.contains('دەسەڵات')) {
      return 'دەسەڵاتی گۆڕینی ئەم وشەی نهێنییەت نییە.';
    }
    return 'نەتوانرا وشەی نهێنی بگۆڕدرێت. دووبارە هەوڵ بدە.';
  }

  Future<void> _showChangeOwnPasswordDialog() async {
    final oldController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var loading = false;
    var obscureOld = true;
    var obscureNew = true;

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('گۆڕینی وشەی نهێنی'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: oldController,
                      obscureText: obscureOld,
                      decoration: InputDecoration(
                        labelText: 'وشەی نهێنیی کۆن',
                        prefixIcon: const Icon(Icons.lock_clock_outlined),
                        suffixIcon: IconButton(
                          onPressed: () => setDialogState(
                            () => obscureOld = !obscureOld,
                          ),
                          icon: Icon(
                            obscureOld ? Icons.visibility_off : Icons.visibility,
                          ),
                        ),
                      ),
                      validator: (value) => value == null || value.isEmpty
                          ? 'وشەی نهێنیی کۆن بنووسە'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: newController,
                      obscureText: obscureNew,
                      decoration: InputDecoration(
                        labelText: 'وشەی نهێنیی نوێ',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          onPressed: () => setDialogState(
                            () => obscureNew = !obscureNew,
                          ),
                          icon: Icon(
                            obscureNew ? Icons.visibility_off : Icons.visibility,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'وشەی نهێنیی نوێ بنووسە';
                        }
                        if (value.length < 8) {
                          return 'وشەی نهێنی لانیکەم ٨ پیت بێت';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: confirmController,
                      obscureText: obscureNew,
                      decoration: const InputDecoration(
                        labelText: 'دووبارەکردنەوەی وشەی نهێنی',
                        prefixIcon: Icon(Icons.lock_reset_rounded),
                      ),
                      validator: (value) => value != newController.text
                          ? 'وشەی نهێنی یەکناگرنەوە'
                          : null,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: loading ? null : () => Navigator.pop(dialogContext),
                  child: const Text('پاشگەزبوونەوە'),
                ),
                ElevatedButton(
                  onPressed: loading
                      ? null
                      : () async {
                          final form = formKey.currentState;
                          if (form == null || !form.validate()) return;
                          setDialogState(() => loading = true);
                          try {
                            await PBService.changePassword(
                              userId: widget.userId,
                              oldPassword: oldController.text,
                              newPassword: newController.text,
                            );
                            if (!dialogContext.mounted) return;
                            Navigator.pop(dialogContext);
                            if (mounted) {
                              AppHelpers.showSnackBar(
                                context,
                                'وشەی نهێنی بە سەرکەوتوویی گۆڕدرا',
                              );
                            }
                          } catch (e) {
                            if (!dialogContext.mounted) return;
                            setDialogState(() => loading = false);
                            if (mounted) {
                              AppHelpers.showSnackBar(
                                context,
                                _friendlyPasswordError(e),
                                isError: true,
                              );
                            }
                          }
                        },
                  child: loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('گۆڕین'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      oldController.dispose();
      newController.dispose();
      confirmController.dispose();
    }
  }

  Future<void> _showAdminResetPasswordDialog() async {
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var loading = false;
    var obscure = true;

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('ڕێکخستنەوەی وشەی نهێنی'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: newController,
                      obscureText: obscure,
                      decoration: InputDecoration(
                        labelText: 'وشەی نهێنیی نوێ',
                        prefixIcon: const Icon(Icons.lock_reset_rounded),
                        suffixIcon: IconButton(
                          onPressed: () => setDialogState(() => obscure = !obscure),
                          icon: Icon(
                            obscure ? Icons.visibility_off : Icons.visibility,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'وشەی نهێنیی نوێ بنووسە';
                        }
                        if (value.length < 8) {
                          return 'وشەی نهێنی لانیکەم ٨ پیت بێت';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: confirmController,
                      obscureText: obscure,
                      decoration: const InputDecoration(
                        labelText: 'دووبارەکردنەوەی وشەی نهێنی',
                        prefixIcon: Icon(Icons.lock_outline_rounded),
                      ),
                      validator: (value) => value != newController.text
                          ? 'وشەی نهێنی یەکناگرنەوە'
                          : null,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: loading ? null : () => Navigator.pop(dialogContext),
                  child: const Text('پاشگەزبوونەوە'),
                ),
                ElevatedButton(
                  onPressed: loading
                      ? null
                      : () async {
                          final form = formKey.currentState;
                          if (form == null || !form.validate()) return;
                          setDialogState(() => loading = true);
                          try {
                            await PBService.resetUserPassword(
                              userId: widget.userId,
                              newPassword: newController.text,
                            );
                            if (!dialogContext.mounted) return;
                            Navigator.pop(dialogContext);
                            if (mounted) {
                              AppHelpers.showSnackBar(
                                context,
                                'وشەی نهێنیی هەژمارەکە ڕێکخرایەوە',
                              );
                            }
                          } catch (e) {
                            if (!dialogContext.mounted) return;
                            setDialogState(() => loading = false);
                            if (mounted) {
                              AppHelpers.showSnackBar(
                                context,
                                _friendlyPasswordError(e),
                                isError: true,
                              );
                            }
                          }
                        },
                  child: loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('ڕێکخستنەوە'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      newController.dispose();
      confirmController.dispose();
    }
  }

  // ═══════════════════════════════════════════
  // ── Shared Profile Editor ──
  // ═══════════════════════════════════════════

  Widget _buildProfileEditor() {
'''
text = text.replace(insert_point, helpers)

old_intro = """    // Employee can only edit Password.
    // Customer can only edit Password (Task 21 - Updated).
    // Admin can edit everything.
    final bool isEmployeeView = auth.userRole == 'employee';
    final bool isCustomerView = auth.userRole == 'customer';
    // Only admins can edit name/phone
    final bool canEditInfo = !isEmployeeView && !isCustomerView;
"""
new_intro = """    final bool canEditInfo = auth.userRole == 'admin';
    final bool isSelf = auth.userId == widget.userId;
    final bool canAdminResetPassword =
        auth.userRole == 'admin' && !isSelf && (_isCustomer || _isEmployee);
    final bool canManagePassword = isSelf || canAdminResetPassword;
"""
require(old_intro in text, 'old profile editor permission intro missing')
text = text.replace(old_intro, new_intro)

old_password_ui = """                // Password field: hide from employees viewing other users' profiles
                if (!isEmployeeView || auth.userId == widget.userId) ...[
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _passwordController,
                    label: AppStrings.password,
                    icon: Icons.lock_outline,
                    obscureText: _obscurePassword,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                        size: 20,
                        color: isDark ? AppDarkColors.textSecondary : Colors.grey,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                ],
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveProfileChanges,
"""
new_password_ui = """                if (canManagePassword) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: isSelf
                          ? _showChangeOwnPasswordDialog
                          : _showAdminResetPasswordDialog,
                      icon: const Icon(Icons.lock_reset_rounded, size: 19),
                      label: Text(
                        isSelf
                            ? 'گۆڕینی وشەی نهێنی'
                            : 'ڕێکخستنەوەی وشەی نهێنی',
                      ),
                    ),
                  ),
                ],
                if (canEditInfo) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveProfileChanges,
"""
require(old_password_ui in text, 'old password UI block missing')
text = text.replace(old_password_ui, new_password_ui)

old_button_close = """                  ),
                ),
              ],
            ),
"""
# Replace only the first closing sequence after the editor's save button by locating editor region.
editor_start = text.index('  Widget _buildProfileEditor() {')
limit_start = text.index('  Widget _buildDebtLimitCard()', editor_start)
editor = text[editor_start:limit_start]
require(old_button_close in editor, 'editor save close sequence missing')
editor = editor.replace(old_button_close, """                    ),
                  ),
                ],
              ],
            ),
""", 1)
text = text[:editor_start] + editor + text[limit_start:]

require('_passwordController' not in text, '_passwordController remains in profile')
require('_obscurePassword' not in text, '_obscurePassword remains in profile')
require('password_text' not in text, 'password_text remains in profile')
profile.write_text(text)
