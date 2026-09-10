import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/models/record_model.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

/// Read-only debt details for the customer application.
///
/// Creating, editing, deleting debts and collecting payments are C-Panel
/// responsibilities and are intentionally absent from this screen/binary.
class DebtDetailScreen extends StatefulWidget {
  const DebtDetailScreen({super.key, required this.debtId});

  final String debtId;

  @override
  State<DebtDetailScreen> createState() => _DebtDetailScreenState();
}

class _DebtDetailScreenState extends State<DebtDetailScreen> {
  RecordModel? _debt;
  List<RecordModel> _payments = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    if (auth.userRole != 'customer' || auth.userId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'ئەم بەشە تەنها بۆ کڕیار بەردەستە';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final debt = await PBService.getDebt(widget.debtId);
      final customerId = debt.getStringValue('customer');
      if (customerId.isEmpty || customerId != auth.userId) {
        throw Exception('DEBT_SCOPE_MISMATCH');
      }
      final payments = await PBService.getPayments(debtId: widget.debtId);
      if (!mounted) return;
      setState(() {
        _debt = debt;
        _payments = payments;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'وردەکاریی قەرز بار نەبوو یان دەسەڵاتی بینینیت نییە.';
      });
    }
  }

  List<Map<String, dynamic>> _items(RecordModel debt) {
    final raw = debt.data['items'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } catch (_) {}
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppDarkColors.background : AppColors.background,
      appBar: AppBar(title: const Text('وردەکاریی قەرز')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _DebtError(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _DebtBody(debt: _debt!, payments: _payments, items: _items(_debt!)),
                ),
    );
  }
}

class _DebtBody extends StatelessWidget {
  const _DebtBody({
    required this.debt,
    required this.payments,
    required this.items,
  });

  final RecordModel debt;
  final List<RecordModel> payments;
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    final amount = debt.getDoubleValue('amount');
    final remaining = debt.getDoubleValue('remaining');
    final paid = (amount - remaining).clamp(0, double.infinity).toDouble();
    final currency = debt.getStringValue('currency').isEmpty
        ? 'IQD'
        : debt.getStringValue('currency');
    final dollarRate = debt.getDoubleValue('dollar_rate');
    final status = debt.getStringValue('status');
    final statusColor = AppHelpers.statusColor(status);
    final description = debt.getStringValue('description');
    final dueDate = debt.getStringValue('due_date');
    final created = debt.getStringValue('custom_date').isNotEmpty
        ? debt.getStringValue('custom_date')
        : debt.created;

    String money(double value) => AppHelpers.formatCurrencyWithType(
          value,
          currency,
          dollarRate: dollarRate,
          showConversion: false,
        );

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, Color(0xFF673AB7)],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      description.isEmpty ? 'قەرز' : description,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.45)),
                    ),
                    child: Text(
                      AppHelpers.statusName(status),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _HeroAmount(
                      label: 'کۆی قەرز',
                      value: money(amount),
                      icon: Icons.receipt_long_rounded,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _HeroAmount(
                      label: 'ماوە',
                      value: money(remaining),
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _HeroAmount(
                label: 'پارەی دراو',
                value: money(paid),
                icon: Icons.check_circle_outline_rounded,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _InfoRow(
                  icon: Icons.calendar_today_outlined,
                  label: 'بەرواری تۆمارکردن',
                  value: created.isEmpty ? '—' : AppHelpers.formatDate(created),
                ),
                const Divider(height: 22),
                _InfoRow(
                  icon: Icons.event_available_outlined,
                  label: 'بەرواری دوایین',
                  value: dueDate.isEmpty ? '—' : AppHelpers.formatDate(dueDate),
                ),
                const Divider(height: 22),
                _InfoRow(
                  icon: Icons.currency_exchange_rounded,
                  label: 'دراو',
                  value: currency == 'USD' ? 'دۆلار' : 'دینار',
                ),
                if (currency == 'USD' && dollarRate > 0) ...[
                  const Divider(height: 22),
                  _InfoRow(
                    icon: Icons.price_change_outlined,
                    label: 'نرخی دۆلار',
                    value: AppHelpers.formatCurrency(dollarRate),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (items.isNotEmpty) ...[
          const SizedBox(height: 14),
          _SectionTitle(title: 'کاڵاکان', count: items.length),
          const SizedBox(height: 8),
          Card(
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = items[index];
                final name = (item['name'] ?? item['title'] ?? 'کاڵا').toString();
                final quantity = _number(item['quantity'] ?? item['qty'], fallback: 1);
                final price = _number(item['price'] ?? item['unit_price']);
                final total = _number(item['total'], fallback: quantity * price);
                return ListTile(
                  leading: CircleAvatar(
                    child: Text('${index + 1}'),
                  ),
                  title: Text(name),
                  subtitle: Text('دانە: ${_compact(quantity)} × ${money(price)}'),
                  trailing: Text(
                    money(total),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                );
              },
            ),
          ),
        ],
        const SizedBox(height: 14),
        _SectionTitle(title: 'پارەدانەوەکان', count: payments.length),
        const SizedBox(height: 8),
        if (payments.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(22),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.info_outline_rounded),
                  SizedBox(width: 8),
                  Text('هێشتا پارەدانەوە تۆمار نەکراوە'),
                ],
              ),
            ),
          )
        else
          Card(
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: payments.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final payment = payments[index];
                final note = payment.getStringValue('note');
                return ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.payments_outlined),
                  ),
                  title: Text(
                    money(payment.getDoubleValue('amount')),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    [
                      if (payment.created.isNotEmpty)
                        AppHelpers.formatDateTime(payment.created),
                      if (note.isNotEmpty) note,
                    ].join('\n'),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 30),
      ],
    );
  }

  static double _number(dynamic value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static String _compact(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2);
  }
}

class _HeroAmount extends StatelessWidget {
  const _HeroAmount({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: Colors.white.withValues(alpha: 0.86)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.80),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 21, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.left,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

class _DebtError extends StatelessWidget {
  const _DebtError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline_rounded, size: 52),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('دووبارە هەوڵدانەوە'),
            ),
          ],
        ),
      ),
    );
  }
}
