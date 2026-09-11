import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
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

class _SubscriptionPaymentScreenState extends State<SubscriptionPaymentScreen>
    with WidgetsBindingObserver {
  String _selectedPlan = 'annual';
  bool _loading = false;
  String? _localPaymentId;
  String? _readableCode;
  String? _paymentStatus;
  int? _amountIqd;
  DateTime? _validUntil;
  Uint8List? _qrBytes;
  Timer? _pollTimer;
  int _pollAttempts = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _localPaymentId != null &&
        !_loading) {
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        if (mounted && !_loading) _checkPayment(silent: true);
      });
    }
  }

  Uint8List? _decodeQr(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    final comma = raw.indexOf(',');
    final payload = comma >= 0 ? raw.substring(comma + 1) : raw;
    try {
      return base64Decode(payload.replaceAll(RegExp(r'\s+'), ''));
    } catch (_) {
      return null;
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollAttempts = 0;
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (timer) {
      if (!mounted || _localPaymentId == null) {
        timer.cancel();
        return;
      }
      _pollAttempts += 1;
      if (_pollAttempts > 15) {
        timer.cancel();
        return;
      }
      if (!_loading) _checkPayment(silent: true);
    });
  }

  String _statusText(String? status) {
    switch (status) {
      case 'paid':
        return 'پارەدراوە';
      case 'declined':
        return 'ڕەتکرایەوە';
      case 'expired':
        return 'بەسەرچووە';
      case 'cancelled':
        return 'هەڵوەشاوەتەوە';
      default:
        return 'چاوەڕوانی پارەدان';
    }
  }

  Future<void> _copyReadableCode() async {
    final code = _readableCode;
    if (code == null || code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    AppHelpers.showSnackBar(context, 'کۆدی پارەدان کۆپی کرا.');
  }

  Future<void> _startPayment() async {
    setState(() => _loading = true);
    try {
      final payment = await PBService.createFibSubscriptionPayment(
        _selectedPlan,
      );
      final localPaymentId = payment['local_payment_id']?.toString() ?? '';
      if (localPaymentId.isEmpty) throw 'پارەدان دروست نەکرا';

      final amount = payment['amount_iqd'];
      final amountIqd = amount is int
          ? amount
          : int.tryParse(amount?.toString() ?? '');
      final validUntil = DateTime.tryParse(
        payment['valid_until']?.toString() ?? '',
      );

      if (!mounted) return;
      setState(() {
        _localPaymentId = localPaymentId;
        _readableCode = payment['readable_code']?.toString();
        _amountIqd = amountIqd;
        _validUntil = validUntil;
        _qrBytes = _decodeQr(payment['qr_code']);
        _paymentStatus = 'pending';
      });
      _startPolling();

      final links = <String>[
        payment['personal_app_link']?.toString() ?? '',
        payment['business_app_link']?.toString() ?? '',
        payment['corporate_app_link']?.toString() ?? '',
      ].where((value) => value.trim().isNotEmpty);

      var opened = false;
      for (final rawLink in links) {
        final uri = Uri.tryParse(rawLink);
        if (uri == null) continue;
        try {
          if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
            opened = true;
            break;
          }
        } catch (_) {}
      }

      if (!opened && mounted) {
        if (_qrBytes != null || _readableCode?.isNotEmpty == true) {
          AppHelpers.showSnackBar(
            context,
            'ئەپی FIB خۆکار نەکرایەوە؛ QR یان کۆدی پارەدان بەکاربهێنە.',
          );
        } else {
          throw 'نەتوانرا ئەپی FIB بکرێتەوە';
        }
      }
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

  Future<void> _checkPayment({bool silent = false}) async {
    final paymentId = _localPaymentId;
    if (paymentId == null || _loading) return;
    final auth = context.read<AuthProvider>();
    setState(() => _loading = true);
    try {
      final status = await PBService.checkFibSubscriptionPayment(paymentId);
      if (!mounted) return;
      setState(() => _paymentStatus = status);

      if (status == 'paid') {
        _pollTimer?.cancel();
        await auth.refreshCurrentProfile();
        if (!mounted) return;
        AppHelpers.showSnackBar(
          context,
          'پارەدان سەرکەوتوو بوو و بەشداری چالاک کرایەوە.',
        );
        if (Navigator.canPop(context)) Navigator.pop(context);
        return;
      }

      if (status == 'pending') {
        if (!silent && mounted) {
          AppHelpers.showSnackBar(context, 'هێشتا پارەدان تەواو نەبووە.');
        }
        return;
      }

      _pollTimer?.cancel();
      if (mounted) {
        AppHelpers.showSnackBar(
          context,
          status == 'expired'
              ? 'کاتی ئەم پارەدانە بەسەرچووە؛ پارەدانێکی نوێ دروست بکە.'
              : status == 'cancelled'
              ? 'پارەدانەکە هەڵوەشاوەتەوە؛ دەتوانیت دووبارە هەوڵ بدەیت.'
              : 'پارەدان ڕەتکرایەوە؛ دووبارە هەوڵ بدە.',
          isError: true,
        );
      }
    } catch (error) {
      if (!silent && mounted) {
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final amountText = _amountIqd == null
        ? null
        : '${NumberFormat('#,##0', 'en_US').format(_amountIqd)} د.ع';
    final validUntilText = _validUntil == null
        ? null
        : DateFormat('yyyy/MM/dd – HH:mm').format(_validUntil!.toLocal());

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
              label: Text(
                _localPaymentId == null
                    ? 'پارەدان بە FIB'
                    : 'دروستکردنی پارەدانێکی نوێ',
              ),
            ),
            if (_localPaymentId != null) ...[
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.verified_user_outlined, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            _statusText(_paymentStatus),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      if (amountText != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'کۆی پارەدان: $amountText',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                      if (_qrBytes != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          color: Colors.white,
                          padding: const EdgeInsets.all(10),
                          child: Image.memory(
                            _qrBytes!,
                            width: 210,
                            height: 210,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'QR ـەکە بە ئەپی FIB بسکەنە.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                      if (_readableCode?.isNotEmpty == true) ...[
                        const SizedBox(height: 12),
                        SelectableText(
                          'کۆدی پارەدان: $_readableCode',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextButton.icon(
                          onPressed: _copyReadableCode,
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          label: const Text('کۆپیکردنی کۆد'),
                        ),
                      ],
                      if (validUntilText != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'کاتی بەسەرچوون: $validUntilText',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _loading ? null : () => _checkPayment(),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('پشکنینی دۆخی پارەدان'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
