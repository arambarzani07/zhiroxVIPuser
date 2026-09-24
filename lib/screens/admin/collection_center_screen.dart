import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:zhirox/screens/shared/user_profile_screen.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:zhirox/widgets/app_design.dart';

class CollectionCenterScreen extends StatefulWidget {
  const CollectionCenterScreen({super.key});

  @override
  State<CollectionCenterScreen> createState() => _CollectionCenterScreenState();
}

class _CollectionCenterScreenState extends State<CollectionCenterScreen> {
  static const Map<String, String> _filters = {
    'all': 'هەموو',
    'overdue': 'دواکەوتوو',
    '1_7': '١–٧ ڕۆژ',
    '8_30': '٨–٣٠ ڕۆژ',
    '31_60': '٣١–٦٠ ڕۆژ',
    '60_plus': '+٦٠ ڕۆژ',
    'followup_due': 'بەدواداچوون',
  };

  bool _loading = true;
  String? _error;
  String _filter = 'all';
  Map<String, dynamic> _data = const {};

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
      await PBService.ensureInitialized();
      final raw = await PBService.client.rpc(
        'get_collection_center',
        params: {
          'p_filter': _filter,
          'p_limit': 150,
        },
      );
      if (raw is! Map) throw Exception('invalid collection center response');
      if (!mounted) return;
      setState(() {
        _data = Map<String, dynamic>.from(raw);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppHelpers.backendErrorMessage(
          error,
          fallback:
              'نەتوانرا ناوەندی بەدواداچوون باربکرێت. دووبارە هەوڵ بدە.',
        );
      });
    }
  }

  Map<String, dynamic> get _summary {
    final raw = _data['summary'];
    return raw is Map ? Map<String, dynamic>.from(raw) : const {};
  }

  List<Map<String, dynamic>> get _items {
    final raw = _data['items'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  int _int(dynamic value) => int.tryParse('${value ?? 0}') ?? 0;

  double _double(dynamic value) =>
      (value as num?)?.toDouble() ??
      double.tryParse('${value ?? 0}') ??
      0;

  String _money(dynamic value, String currency) {
    final number = _double(value);
    final formatted = NumberFormat('#,##0.##', 'en_US').format(number);
    return currency == 'USD' ? '\$$formatted' : '$formatted د.ع';
  }

  String _dateLabel(dynamic value) {
    final text = value?.toString() ?? '';
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return '';
    return DateFormat('yyyy/MM/dd').format(parsed.toLocal());
  }

  String _fullName(Map<String, dynamic> item) {
    final parts = <String>[
      item['name']?.toString().trim() ?? '',
      item['father_name']?.toString().trim() ?? '',
      item['grandfather_name']?.toString().trim() ?? '',
    ].where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? 'کڕیار' : parts.join(' ');
  }

  String _agingLabel(Map<String, dynamic> item) {
    final days = _int(item['overdue_days']);
    if (days <= 0) return 'لە کاتیدایە';
    if (days <= 7) return '١–٧ ڕۆژ دواکەوتوو';
    if (days <= 30) return '٨–٣٠ ڕۆژ دواکەوتوو';
    if (days <= 60) return '٣١–٦٠ ڕۆژ دواکەوتوو';
    return '+٦٠ ڕۆژ دواکەوتوو';
  }

  Future<void> _scheduleFollowUp(Map<String, dynamic> item) async {
    final current = DateTime.tryParse(
      item['next_followup_date']?.toString() ?? '',
    );
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: current ?? now.add(const Duration(days: 1)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5, 12, 31),
    );
    if (selected == null || !mounted) return;

    final controller = TextEditingController(
      text: item['followup_note']?.toString() ?? '',
    );
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('بەدواداچوونی داهاتوو'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('بەروار: ${DateFormat('yyyy/MM/dd').format(selected)}'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: 'تێبینی',
                hintText: 'نموونە: پەیوەندی بکە بۆ پارەدانەوە',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('پاشگەزبوونەوە'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('پاشەکەوت'),
          ),
        ],
      ),
    );
    final note = controller.text.trim();
    controller.dispose();
    if (save != true || !mounted) return;

    try {
      await PBService.client.rpc(
        'set_customer_followup',
        params: {
          'p_customer_id': item['customer_id']?.toString(),
          'p_next_followup_date': DateFormat('yyyy-MM-dd').format(selected),
          'p_note': note,
        },
      );
      if (!mounted) return;
      AppHelpers.showSnackBar(context, 'بەدواداچوون پاشەکەوت کرا');
      await _load();
    } catch (error) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          error,
          fallback: 'پاشەکەوتکردنی بەدواداچوون سەرکەوتوو نەبوو.',
        ),
        isError: true,
      );
    }
  }

  Future<void> _completeFollowUp(Map<String, dynamic> item) async {
    final ok = await AppHelpers.showConfirmDialog(
      context,
      title: 'تەواوکردنی بەدواداچوون',
      message: 'ئەم بەدواداچوونە وەک تەواوکراو تۆمار بکرێت؟',
    );
    if (!ok || !mounted) return;

    try {
      await PBService.client.rpc(
        'complete_customer_followup',
        params: {'p_customer_id': item['customer_id']?.toString()},
      );
      if (!mounted) return;
      AppHelpers.showSnackBar(context, 'بەدواداچوون تەواو کرا');
      await _load();
    } catch (error) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          error,
          fallback: 'تەواوکردنی بەدواداچوون سەرکەوتوو نەبوو.',
        ),
        isError: true,
      );
    }
  }

  Future<void> _openCustomer(Map<String, dynamic> item) async {
    final id = item['customer_id']?.toString() ?? '';
    if (id.isEmpty) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          userId: id,
          openFinancialChat: true,
        ),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? AppDarkColors.background : const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('ناوەندی بەدواداچوونی قەرز'),
        actions: [
          IconButton(
            tooltip: 'نوێکردنەوە',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            _buildSummary(),
            const SizedBox(height: 18),
            const AppSectionHeader(
              title: 'فلتەر',
              subtitle: 'کڕیاران بە ماوەی دواکەوتن یان بەدواداچوون',
            ),
            const SizedBox(height: 10),
            _buildFilters(),
            const SizedBox(height: 18),
            if (_loading && _items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null && _items.isEmpty)
              _buildError()
            else if (_items.isEmpty)
              _buildEmpty()
            else
              ..._items.map(_buildCustomerCard),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary() {
    final summary = _summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader(
          title: 'پوختە',
          subtitle: 'قەرزی دواکەوتوو و کارە پێویستەکان',
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _SummaryCard(
              icon: Icons.people_alt_outlined,
              label: 'کڕیاری دواکەوتوو',
              value: _int(summary['overdue_customers']).toString(),
            ),
            _SummaryCard(
              icon: Icons.today_outlined,
              label: 'پێویستی ئەمڕۆ',
              value: _int(summary['due_today_customers']).toString(),
            ),
            _SummaryCard(
              icon: Icons.event_repeat_outlined,
              label: 'بەدواداچوونی کاتی',
              value: _int(summary['followups_due']).toString(),
            ),
            _SummaryCard(
              icon: Icons.account_balance_wallet_outlined,
              label: 'دواکەوتووی IQD',
              value: _money(summary['overdue_iqd'], 'IQD'),
              wide: true,
            ),
            _SummaryCard(
              icon: Icons.attach_money_rounded,
              label: 'دواکەوتووی USD',
              value: _money(summary['overdue_usd'], 'USD'),
              wide: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _filters.entries.map((entry) {
          final selected = _filter == entry.key;
          return Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: FilterChip(
              selected: selected,
              label: Text(entry.value),
              onSelected: (_) {
                if (_filter == entry.key) return;
                setState(() => _filter = entry.key);
                _load();
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildError() {
    return AppSurface(
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 42),
          const SizedBox(height: 10),
          Text(
            _error ?? '',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('دووبارە هەوڵ بدە'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return const AppSurface(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            Icon(Icons.task_alt_rounded, size: 44),
            SizedBox(height: 10),
            Text(
              'هیچ کڕیارێک لەم فلتەرەدا نییە',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerCard(Map<String, dynamic> item) {
    final overdueDays = _int(item['overdue_days']);
    final priority = _int(item['priority_score']);
    final followupDate = _dateLabel(item['next_followup_date']);
    final followupNote = item['followup_note']?.toString().trim() ?? '';
    final hasFollowup = followupDate.isNotEmpty;
    final phone = item['phone']?.toString().trim() ?? '';
    final overdueIqd = _double(item['overdue_iqd']);
    final overdueUsd = _double(item['overdue_usd']);
    final balanceIqd = _double(item['balance_iqd']);
    final balanceUsd = _double(item['balance_usd']);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppSurface(
        padding: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openCustomer(item),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      backgroundColor: AppColors.primarySoft,
                      child: const Icon(
                        Icons.person_outline_rounded,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                _fullName(item),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                              if (item['is_vip'] == true)
                                const _MiniBadge(
                                  icon: Icons.workspace_premium_rounded,
                                  text: 'VIP',
                                ),
                              if (item['is_pinned'] == true)
                                const _MiniBadge(
                                  icon: Icons.push_pin_outlined,
                                  text: 'Pin',
                                ),
                            ],
                          ),
                          if (phone.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              phone,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                    _PriorityBadge(score: priority),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoPill(
                      icon: Icons.schedule_rounded,
                      text: _agingLabel(item),
                    ),
                    _InfoPill(
                      icon: Icons.receipt_long_outlined,
                      text:
                          '${_int(item['open_debt_count'])} قەرزی کراوە',
                    ),
                    if (item['oldest_due_date'] != null)
                      _InfoPill(
                        icon: Icons.event_busy_outlined,
                        text:
                            'کۆنترین: ${_dateLabel(item['oldest_due_date'])}',
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (balanceIqd > 0)
                  _AmountLine(
                    label: 'باڵانسی IQD',
                    value: _money(balanceIqd, 'IQD'),
                  ),
                if (overdueIqd > 0)
                  _AmountLine(
                    label: 'دواکەوتووی IQD',
                    value: _money(overdueIqd, 'IQD'),
                    emphasized: true,
                  ),
                if (balanceUsd > 0)
                  _AmountLine(
                    label: 'باڵانسی USD',
                    value: _money(balanceUsd, 'USD'),
                  ),
                if (overdueUsd > 0)
                  _AmountLine(
                    label: 'دواکەوتووی USD',
                    value: _money(overdueUsd, 'USD'),
                    emphasized: true,
                  ),
                if (overdueDays == 0)
                  const _AmountLine(
                    label: 'دۆخ',
                    value: 'هێشتا دواکەوتوو نییە',
                  ),
                if (hasFollowup) ...[
                  const Divider(height: 24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.event_repeat_rounded, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          followupNote.isEmpty
                              ? 'بەدواداچوون: $followupDate'
                              : 'بەدواداچوون: $followupDate\n$followupNote',
                          style: const TextStyle(height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _scheduleFollowUp(item),
                        icon: const Icon(Icons.event_available_outlined),
                        label: Text(
                          hasFollowup
                              ? 'گۆڕینی بەدواداچوون'
                              : 'دانانی بەدواداچوون',
                        ),
                      ),
                    ),
                    if (hasFollowup) ...[
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: 'تەواوکراو',
                        onPressed: () => _completeFollowUp(item),
                        icon: const Icon(Icons.task_alt_rounded),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    this.wide = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cardWidth = wide ? width - 32 : (width - 42) / 2;
    return SizedBox(
      width: cardWidth.clamp(150, 520).toDouble(),
      child: AppSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.primary),
            const SizedBox(height: 10),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    final label = score >= 70
        ? 'فوری'
        : score >= 40
            ? 'گرنگ'
            : 'ئاسایی';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .secondaryContainer
            .withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label • $score',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12),
          const SizedBox(width: 3),
          Text(
            text,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}

class _AmountLine extends StatelessWidget {
  const _AmountLine({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
      color: emphasized ? Theme.of(context).colorScheme.error : null,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
