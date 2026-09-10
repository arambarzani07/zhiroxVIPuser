from pathlib import Path

path = Path('lib/screens/shared/add_user_screen.dart')
text = path.read_text()
old = """  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
"""
new = """  Future<void> _save() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;
    if (name.isEmpty || phone.isEmpty || password.length < 8) {
      if (widget.role == 'employee' && _employeeSection != 0 && mounted) {
        setState(() => _employeeSection = 0);
      }
      if (mounted) {
        AppHelpers.showSnackBar(
          context,
          password.isNotEmpty && password.length < 8
              ? 'وشەی نهێنی نابێت لە ٨ پیت کەمتر بێت'
              : 'تکایە زانیاری بنەڕەتی تەواو بکە',
          isError: true,
        );
      }
      return;
    }
    if (!(_formKey.currentState?.validate() ?? true)) return;

    setState(() => _isLoading = true);
"""
if old not in text:
    raise SystemExit('save anchor not found')
text = text.replace(old, new, 1)
path.write_text(text)
