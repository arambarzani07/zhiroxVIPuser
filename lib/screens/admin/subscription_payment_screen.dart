import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

class _PaymentPlan {
  const _PaymentPlan(this.code, this.title, this.period, this.price);

  final String code;
  final String title;
  final String period;
  final String price;
}

const _plans = <_PaymentPlan>[
  _PaymentPlan('monthly', 'مانگانە', '٣٠ ڕۆژ', '١٠,٠٠٠ د.ع'),
  _PaymentPlan('quarterly', 'سێ مانگ', '٩٠ ڕۆژ', '٢٥,٠٠٠ د.ع'),
  _PaymentPlan('semiannual', 'شەش مانگ', '١٨٠ ڕۆژ', '٤٥,٠٠٠ د.ع'),
  _PaymentPlan('annual', 'ساڵانە', '٣٦٥ ڕۆژ', '٨٠,٠٠٠ د.ع'),
];

class SubscriptionPaymentScreen extends StatefulWidget {
  const SubscriptionPaymentScreen({super.key, this.restricted = false});

  final bool restricted;

  @override
  State<SubscriptionPaymentScreen> createState() =>
      _SubscriptionPaymentScreenState();
}

class _SubscriptionPaymentScreenState extends State<SubscriptionPaymentScreen> {
  String _selectedPlan = 'annual';
  bool _loading = false;
  String? _localPaymentId;
  String? _readableCode;

  Future<void> _startPayment() async {
    setState(() => _loading = true);
    try {
      final payment = await PBService.createFibSubscriptionPayment(
        _selectedPlan,
      );
      _localPaymentId = payment['local_payment_id']?.toString();
      _readableCode = payment['readable_code']?.toString();
      final rawLink =
          payment['personal_app_link']?.toString().trim().isNotEmpty == true
          ? payment['personal_app_link'].toString()
          : payment['business_app_link']?.toString().trim().isNotEmpty == true
          ? payment['business_app_link'].toString()
          : payment['corporate_app_link']?.toString() ?? '';
      final uri = Uri.tryParse(rawLink);
      if (uri == null ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw 'نەتوانرا ئەپی FIB بکرێتەوە';
      }
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        AppHelpers.showSnackBar(
          context,
          error.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _checkPayment() async {
    final paymentId = _localPaymentId;
    if (paymentId == null) return;
    final auth = context.read<AuthProvider>();
    setState(() => _loading = true);
    try {
      final status = await PBService.checkFibSubscriptionPayment(paymentId);
      if (status == 'paid') {
        await auth.refreshCurrentProfile();
        if (!mounted) return;
        AppHelpers.showSnackBar(
          context,
          'پارەدان سەرکەوتوو بوو و بەشداری چالاک کرایەوە.',
        );
        if (Navigator.canPop(context)) Navigator.pop(context);
      } else {
        if (mounted) {
          AppHelpers.showSnackBar(
            context,
            status == 'pending'
                ? 'هێشتا پارەدان تەواو نەبووە.'
                : 'پارەدان سەرکەوتوو نەبوو؛ دووبارە هەوڵ بدە.',
            isError: status != 'pending',
          );
        }
      }
    } catch (error) {
      if (mounted) {
        AppHelpers.showSnackBar(context, error.toString(), isError: true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.restricted,
        title: const Text('نوێکردنەوەی بەشداری'),
        actions: widget.restricted
            ? [
                IconButton(
                  tooltip: AppStrings.logout,
                  onPressed: _loading
                      ? null
                      : context.read<AuthProvider>().logout,
                  icon: const Icon(Icons.logout_rounded),
                ),
              ]
            : null,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              widget.restricted
                  ? 'ماوەی بەشداریت تەواو بووە؛ پلانێک هەڵبژێرە و بە FIB پارە بدە.'
                  : 'پلانی گونجاو هەڵبژێرە و بە ئەپی FIB پارە بدە.',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'کڕیار بەخۆڕاییە • تا ٣ کارمەند لە نرخەکەدایە • هەر کارمەندی زیادە ٢,٠٠٠ د.ع مانگانە',
              style: TextStyle(fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 16),
            RadioGroup<String>(
              groupValue: _selectedPlan,
              onChanged: _loading
                  ? (_) {}
                  : (value) {
                      if (value != null) {
                        setState(() => _selectedPlan = value);
                      }
                    },
              child: Column(
                children: _plans.map((plan) {
                  final selected = _selectedPlan == plan.code;
                  return Card(
                    color: selected
                        ? AppColors.primary.withValues(
                            alpha: isDark ? 0.22 : 0.08,
                          )
                        : null,
                    child: RadioListTile<String>(
                      value: plan.code,
                      enabled: !_loading,
                      title: Text(
                        plan.title,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(plan.period),
                      secondary: Text(
                        plan.price,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: _loading ? null : _startPayment,
              icon: _loading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.account_balance_wallet_outlined),
              label: const Text('پارەدان بە FIB'),
            ),
            if (_localPaymentId != null) ...[
              const SizedBox(height: 14),
              if (_readableCode?.isNotEmpty == true)
                Text(
                  'کۆدی پارەدان: $_readableCode',
                  textAlign: TextAlign.center,
                ),
              OutlinedButton.icon(
                onPressed: _loading ? null : _checkPayment,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('پشکنینی دۆخی پارەدان'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
