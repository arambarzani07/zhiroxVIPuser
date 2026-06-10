import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

class RegisterCustomerScreen extends StatefulWidget {
  const RegisterCustomerScreen({super.key});

  @override
  State<RegisterCustomerScreen> createState() => _RegisterCustomerScreenState();
}

class _RegisterCustomerScreenState extends State<RegisterCustomerScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  List<RecordModel> _admins = [];
  String? _selectedAdminId;
  bool _loadingAdmins = true;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _loadAdmins();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: const Interval(0.2, 0.8, curve: Curves.easeOutCubic),
          ),
        );

    _animationController.forward();
  }

  Future<void> _loadAdmins() async {
    try {
      final allAdmins = await PBService.getAdminList();

      // Deduplicate by market_name (keep first one per name)
      final seen = <String>{};
      final unique = <RecordModel>[];
      for (final admin in allAdmins) {
        final name = admin.getStringValue('market_name').trim();
        if (name.isNotEmpty && seen.add(name)) {
          unique.add(admin);
        }
      }

      // Sort alphabetically by market_name
      unique.sort(
        (a, b) => a
            .getStringValue('market_name')
            .compareTo(b.getStringValue('market_name')),
      );

      _admins = unique;
    } catch (_) {}
    setState(() => _loadingAdmins = false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAdminId == null) {
      AppHelpers.showSnackBar(
        context,
        'تکایە مارکێتێک هەڵبژێرە',
        isError: true,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await PBService.registerCustomer(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        password: _passwordController.text,
        adminId: _selectedAdminId!,
      );

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Column(
              children: [
                Icon(Icons.check_circle_outline, size: 60, color: Colors.green),
                SizedBox(height: 10),
                Text(
                  'داواکاریت نێردرا',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: const Text(
              AppStrings.requestSent,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                ),
                child: const Text('باشە'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        AppHelpers.showSnackBar(context, 'هەڵە: $e', isError: true);
      }
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppDarkColors.background : Colors.white,
      appBar: AppBar(
        title: const Text('خۆتۆمارکردن'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: isDark ? AppDarkColors.textPrimary : Colors.black87,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          fontFamily: 'Rabar',
        ),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new,
            color: isDark ? AppDarkColors.textPrimary : Colors.black87,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: SizedBox(
        height: size.height,
        child: Stack(
          children: [
            // Background Shapes
            Positioned(
              top: -80,
              left: -80,
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.orange.withOpacity(isDark ? 0.04 : 0.08),
                ),
              ),
            ),
            Positioned(
              bottom: 50,
              right: -50,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withOpacity(isDark ? 0.04 : 0.08),
                ),
              ),
            ),

            // Content
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 20),

                    // Header Animation
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isDark ? AppDarkColors.card : Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withOpacity(0.2),
                                  blurRadius: 20,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.person_add_rounded,
                              size: 40,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'هەژماری نوێ',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? AppDarkColors.textPrimary
                                  : AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'زانیارییەکانت پڕبکەرەوە بۆ دروستکردنی هەژمار',
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark
                                  ? AppDarkColors.textSecondary
                                  : Colors.grey[500],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Form Animation
                    SlideTransition(
                      position: _slideAnimation,
                      child: FadeTransition(
                        opacity: _fadeAnimation,
                        child: Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              // Market Select
                              _buildDropdown(),
                              const SizedBox(height: 16),

                              // Name
                              _buildTextField(
                                controller: _nameController,
                                label: AppStrings.name,
                                icon: Icons.person_outline_rounded,
                                hint: 'ناوی سیانی',
                                validator: (v) => v == null || v.isEmpty
                                    ? 'ناو بنووسە'
                                    : null,
                              ),
                              const SizedBox(height: 16),

                              // Phone
                              _buildTextField(
                                controller: _phoneController,
                                label: AppStrings.phone,
                                icon: Icons.phone_iphone_rounded,
                                hint: '07xxxxxxxxx',
                                keyboardType: TextInputType.phone,
                                validator: (v) => v == null || v.isEmpty
                                    ? 'ژمارە مۆبایل بنووسە'
                                    : null,
                              ),
                              const SizedBox(height: 16),

                              // Password
                              _buildTextField(
                                controller: _passwordController,
                                label: AppStrings.password,
                                icon: Icons.lock_outline_rounded,
                                obscureText: _obscurePassword,
                                isPassword: true,
                                onVisibilityChanged: () {
                                  setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  );
                                },
                                validator: (v) {
                                  if (v == null || v.isEmpty) {
                                    return 'وشەی نهێنی بنووسە';
                                  }
                                  if (v.length < 8) {
                                    return 'وشەی نهێنی لانیکەم ٨ پیت بێت';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 32),

                              // Register Button
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary.withOpacity(0.3),
                                      blurRadius: 12,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _register,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(
                                      double.infinity,
                                      56,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text(
                                          AppStrings.register,
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.inputFill : Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppDarkColors.cardBorder : Colors.grey[200]!,
        ),
      ),
      child: ButtonTheme(
        alignedDropdown: true,
        child: DropdownButtonFormField<String>(
          initialValue: _selectedAdminId,
          decoration: InputDecoration(
            labelText: AppStrings.selectMarket,
            labelStyle: TextStyle(
              color: isDark ? AppDarkColors.textSecondary : null,
            ),
            floatingLabelBehavior: FloatingLabelBehavior.auto,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 16,
            ),
            prefixIcon: Icon(
              Icons.store_rounded,
              color: AppColors.primary.withOpacity(0.7),
            ),
          ),
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: isDark ? AppDarkColors.textSecondary : null,
          ),
          dropdownColor: isDark ? AppDarkColors.card : Colors.white,
          borderRadius: BorderRadius.circular(16),
          style: TextStyle(
            color: isDark ? AppDarkColors.textPrimary : Colors.black87,
            fontFamily: 'NotoKufiArabic',
          ),
          items: _admins.isEmpty
              ? []
              : _admins
                    .asMap()
                    .entries
                    .map(
                      (entry) => DropdownMenuItem<String>(
                        value: entry.value.id,
                        child: Text(
                          '${entry.key + 1}. ${entry.value.getStringValue('market_name')}',
                          style: const TextStyle(
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    )
                    .toList(),
          onChanged: (value) => setState(() => _selectedAdminId = value),
          validator: (v) => v == null ? 'مارکێتێک هەڵبژێرە' : null,
          hint: _loadingAdmins
              ? Text(
                  'دەهێنرێت...',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppDarkColors.textSecondary : null,
                  ),
                )
              : Text(
                  'مارکێتێک هەڵبژێرە',
                  style: TextStyle(
                    color: isDark ? AppDarkColors.textSecondary : null,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    TextInputType? keyboardType,
    bool obscureText = false,
    bool isPassword = false,
    VoidCallback? onVisibilityChanged,
    String? Function(String?)? validator,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.inputFill : Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppDarkColors.cardBorder : Colors.grey[200]!,
        ),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isDark ? AppDarkColors.textPrimary : null,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: isDark ? AppDarkColors.textSecondary : null,
          ),
          hintText: hint,
          hintStyle: TextStyle(
            color: isDark ? AppDarkColors.textSecondary : null,
          ),
          floatingLabelBehavior: FloatingLabelBehavior.auto,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
          prefixIcon: Icon(icon, color: AppColors.primary.withOpacity(0.7)),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    obscureText ? Icons.visibility_off : Icons.visibility,
                    color: isDark
                        ? AppDarkColors.textSecondary
                        : Colors.grey[400],
                  ),
                  onPressed: onVisibilityChanged,
                )
              : null,
        ),
        validator: validator,
      ),
    );
  }
}
