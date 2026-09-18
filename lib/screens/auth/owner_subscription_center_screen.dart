import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:zhirox/widgets/app_design.dart';

class OwnerSubscriptionCenterScreen extends StatefulWidget {
  const OwnerSubscriptionCenterScreen({super.key});

  @override
  State<OwnerSubscriptionCenterScreen> createState() =>
      _OwnerSubscriptionCenterScreenState();
}

class _OwnerSubscriptionCenterScreenState
    extends State<OwnerSubscriptionCenterScreen> {
  Map<String, dynamic> _overview = const {};
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;

  int _asInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('${value ?? 0}') ?? 0;

  double _asDouble(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('${value ?? 0}') ?? 0;

  String _money(dynamic value) =>
      "${NumberFormat('#,##0', 'en').format(_asDouble(value))} د.ع";

  String _date(dynamic value) {
    final parsed = DateTime.tryParse('${value ?? ''}');
    if (parsed == null) return 'بێ بەروار';
    return DateFormat('yyyy/MM/dd').format(parsed.toLocal());
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        PBService.getOwnerSubscriptionOverview(),
        PBService.getOwnerSubscriptionsPage(page: 1, perPage: 100),
      ]);
      final page = results[1];
      final items = <Map<String, dynamic>>[];
      final rawItems = page['items'];
      if (rawItems is List) {
        for (final item in rawItems) {
          if (item is Map) items.add(Map<String, dynamic>.from(item));
        }
      }
      if (!mounted) return;
      setState(() {
        _overview = results[0];
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppHelpers.backendErrorMessage(
          error,
          fallback: 'نەتوانرا زانیاری بەشداری بهێنرێت.',
        );
      });
    }
  }

  Future<void> _editSubscription(Map<String, dynamic> item) async {
    var plan = (item['subscription_plan'] ?? 'custom').toString();
    var extendDays = 0;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          scrollable: true,
          title: Text((item['market_name'] ?? 'مارکێت').toString()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: plan,
                decoration: const InputDecoration(
                  labelText: 'پلانی بەشداری',
                  prefixIcon: Icon(Icons.workspace_premium_outlined),
                ),
                items: const [
                  DropdownMenuItem(value: 'monthly', child: Text('مانگانە')),
                  DropdownMenuItem(value: 'quarterly', child: Text('٣ مانگ')),
                  DropdownMenuItem(value: 'semiannual', child: Text('٦ مانگ')),
                  DropdownMenuItem(value: 'annual', child: Text('ساڵانە')),
                  DropdownMenuItem(value: 'custom', child: Text('Custom')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => plan = value);
                  }
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: extendDays,
                decoration: const InputDecoration(
                  labelText: 'درێژکردنەوە',
                  prefixIcon: Icon(Icons.event_repeat_rounded),
                ),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('تەنها پلانی بگۆڕە')),
                  DropdownMenuItem(value: 30, child: Text('+ ٣٠ ڕۆژ')),
                  DropdownMenuItem(value: 90, child: Text('+ ٩٠ ڕۆژ')),
                  DropdownMenuItem(value: 180, child: Text('+ ١٨٠ ڕۆژ')),
                  DropdownMenuItem(value: 365, child: Text('+ ٣٦٥ ڕۆژ')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => extendDays = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              Text(
                'ئەم کردارە تەنها plan و بەرواری subscription دەگۆڕێت؛ '
                'هیچ داتای کاروباری مارکێت ناخوێنێتەوە.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('پاشگەزبوونەوە'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, {
                'plan': plan,
                'extend_days': extendDays,
              }),
              child: const Text('پاشەکەوت'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    try {
      await PBService.setOwnerSubscription(
        adminId: item['id'].toString(),
        plan: result['plan'].toString(),
        extendDays: _asInt(result['extend_days']),
      );
      if (!mounted) return;
      AppHelpers.showSnackBar(context, 'بەشداری نوێ کرایەوە.');
      await _load();
    } catch (error) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          error,
          fallback: 'نوێکردنەوەی بەشداری سەرکەوتوو نەبوو.',
        ),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ناوەندی بەشداری'),
        actions: [
          IconButton(
            tooltip: 'نوێکردنەوە',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off_rounded, size: 44),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('دووبارە هەوڵ بدە'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      AppSurface(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.privacy_tip_outlined,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Owner تەنها subscription، billing metadata و '
                                'دۆخی هەژمار بەڕێوەدەبات. ناوەڕۆکی مارکێت '
                                'و زانیاریی کاروباری لەم بەشەدا نییە.',
                                style: TextStyle(
                                  color: secondary,
                                  height: 1.55,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _metric(
                            context,
                            'هەموو مارکێتەکان',
                            _asInt(_overview['total_tenants']).toString(),
                            Icons.storefront_outlined,
                          ),
                          _metric(
                            context,
                            'بەشداری چالاک',
                            _asInt(_overview['active_subscriptions']).toString(),
                            Icons.verified_outlined,
                          ),
                          _metric(
                            context,
                            '≤ ٧ ڕۆژ',
                            _asInt(_overview['expiring_7_days']).toString(),
                            Icons.event_busy_outlined,
                          ),
                          _metric(
                            context,
                            'بەسەرچوو',
                            _asInt(_overview['expired_subscriptions']).toString(),
                            Icons.timer_off_outlined,
                          ),
                          _metric(
                            context,
                            'Pending ـی ٣٠ ڕۆژ',
                            _asInt(_overview['pending_payments_30d']).toString(),
                            Icons.hourglass_bottom_rounded,
                          ),
                          _metric(
                            context,
                            'Failed ـی ٣٠ ڕۆژ',
                            _asInt(_overview['failed_payments_30d']).toString(),
                            Icons.error_outline_rounded,
                          ),
                          _metric(
                            context,
                            'داهاتی پلاتفۆرم / ٣٠ ڕۆژ',
                            _money(_overview['platform_revenue_30d_iqd']),
                            Icons.payments_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const AppSectionHeader(
                        title: 'بەشدارییەکان',
                        subtitle:
                            'plan، expiry و status ـی billing؛ بێ business data',
                      ),
                      const SizedBox(height: 10),
                      if (_items.isEmpty)
                        const AppSurface(
                          child: Center(
                            child: Padding(
                              padding: EdgeInsets.all(18),
                              child: Text('هیچ هەژماری مارکێت نییە.'),
                            ),
                          ),
                        )
                      else
                        ..._items.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _subscriptionCard(context, item),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _metric(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return SizedBox(
      width: 160,
      child: AppSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.primary, size: 22),
            const SizedBox(height: 10),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
              textDirection: TextDirection.ltr,
            ),
            const SizedBox(height: 2),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _subscriptionCard(
    BuildContext context,
    Map<String, dynamic> item,
  ) {
    final market = (item['market_name'] ?? 'مارکێت').toString();
    final admin = (item['admin_name'] ?? '').toString();
    final phone = (item['phone'] ?? '').toString();
    final plan = (item['subscription_plan'] ?? 'custom').toString();
    final lifecycle = (item['lifecycle_status'] ?? 'active').toString();
    final paymentStatus = (item['latest_payment_status'] ?? '').toString();
    final paymentAmount = _asDouble(item['latest_payment_amount_iqd']);

    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                backgroundColor: AppColors.primarySoft,
                child: Icon(
                  Icons.workspace_premium_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      market,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      admin.isEmpty ? phone : '$admin • $phone',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              _statusChip(lifecycle),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _mini(Icons.sell_outlined, plan),
              _mini(
                Icons.event_outlined,
                _date(item['subscription_end']),
              ),
              if (paymentStatus.isNotEmpty)
                _mini(Icons.receipt_long_outlined, paymentStatus),
              if (paymentAmount > 0)
                _mini(
                  Icons.payments_outlined,
                  _money(paymentAmount),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _editSubscription(item),
              icon: const Icon(Icons.edit_calendar_outlined, size: 18),
              label: const Text('نوێکردنەوەی بەشداری'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mini(IconData icon, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      );

  Widget _statusChip(String status) {
    final (label, color) = switch (status) {
      'trial' => ('Trial', Colors.blue),
      'grace' => ('Grace', Colors.orange),
      'suspended' => ('Suspended', Colors.red),
      'archived' => ('Archived', Colors.grey),
      _ => ('Active', Colors.green),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
