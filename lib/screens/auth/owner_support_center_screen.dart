import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:zhirox/widgets/app_design.dart';

class OwnerSupportCenterScreen extends StatefulWidget {
  const OwnerSupportCenterScreen({super.key});

  @override
  State<OwnerSupportCenterScreen> createState() =>
      _OwnerSupportCenterScreenState();
}

class _OwnerSupportCenterScreenState extends State<OwnerSupportCenterScreen> {
  Map<String, dynamic> _overview = const {};
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;
  String _filter = 'active';

  int _asInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('${value ?? 0}') ?? 0;

  double _asDouble(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('${value ?? 0}') ?? 0;

  String _date(dynamic value) {
    final parsed = DateTime.tryParse('${value ?? ''}');
    if (parsed == null) return '—';
    return DateFormat('yyyy/MM/dd HH:mm').format(parsed.toLocal());
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
        PBService.getOwnerSupportOverview(),
        PBService.getOwnerSupportTicketsPage(page: 1, perPage: 100),
      ]);
      final rows = <Map<String, dynamic>>[];
      final raw = results[1]['items'];
      if (raw is List) {
        for (final item in raw) {
          if (item is Map) rows.add(Map<String, dynamic>.from(item));
        }
      }
      if (!mounted) return;
      setState(() {
        _overview = results[0];
        _items = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppHelpers.backendErrorMessage(
          error,
          fallback: 'نەتوانرا Support Center بخوێنرێتەوە.',
        );
      });
    }
  }

  List<Map<String, dynamic>> get _visibleItems {
    if (_filter == 'all') return _items;
    if (_filter == 'active') {
      return _items
          .where(
            (item) => !const ['resolved', 'closed']
                .contains((item['status'] ?? '').toString()),
          )
          .toList(growable: false);
    }
    return _items
        .where((item) => (item['status'] ?? '').toString() == _filter)
        .toList(growable: false);
  }

  Future<void> _manageTicket(Map<String, dynamic> item) async {
    var status = (item['status'] ?? 'open').toString();
    var priority = (item['priority'] ?? 'normal').toString();
    final responseController = TextEditingController(
      text: (item['owner_response'] ?? '').toString(),
    );

    try {
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            scrollable: true,
            title: Text((item['subject'] ?? 'Support').toString()),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (item['message'] ?? '').toString(),
                  style: Theme.of(ctx).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(
                    labelText: 'دۆخی Ticket',
                    prefixIcon: Icon(Icons.flag_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'open', child: Text('Open')),
                    DropdownMenuItem(
                      value: 'in_progress',
                      child: Text('In Progress'),
                    ),
                    DropdownMenuItem(
                      value: 'waiting_admin',
                      child: Text('Waiting Admin'),
                    ),
                    DropdownMenuItem(
                      value: 'resolved',
                      child: Text('Resolved'),
                    ),
                    DropdownMenuItem(value: 'closed', child: Text('Closed')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => status = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: priority,
                  decoration: const InputDecoration(
                    labelText: 'Priority',
                    prefixIcon: Icon(Icons.priority_high_rounded),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('Low')),
                    DropdownMenuItem(value: 'normal', child: Text('Normal')),
                    DropdownMenuItem(value: 'high', child: Text('High')),
                    DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => priority = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: responseController,
                  maxLines: 5,
                  maxLength: 3000,
                  decoration: const InputDecoration(
                    labelText: 'وەڵامی Owner',
                    hintText: 'وەڵامێکی تەکنیکی و ڕوون بنووسە...',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.reply_rounded),
                  ),
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
                  'status': status,
                  'priority': priority,
                  'response': responseController.text.trim(),
                }),
                child: const Text('پاشەکەوت'),
              ),
            ],
          ),
        ),
      );

      if (result == null) return;

      await PBService.updateOwnerSupportTicket(
        ticketId: item['id'].toString(),
        status: result['status'].toString(),
        priority: result['priority'].toString(),
        ownerResponse: result['response'].toString(),
      );
      if (!mounted) return;
      AppHelpers.showSnackBar(context, 'Ticket نوێ کرایەوە.');
      await _load();
    } catch (error) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          error,
          fallback: 'نوێکردنەوەی Ticket سەرکەوتوو نەبوو.',
        ),
        isError: true,
      );
    } finally {
      responseController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final visible = _visibleItems;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Support Center'),
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
                              Icons.support_agent_rounded,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'ئەم بەشە تەنها داواکاری Support ـی خۆی Admin '
                                'و metadata ـی تەکنیکی پیشان دەدات. Owner هیچ '
                                'دەستگەیشتنێکی بە ناوەڕۆکی کاروباری مارکێت نییە.',
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
                            'Open',
                            _asInt(_overview['open_tickets']).toString(),
                            Icons.markunread_mailbox_outlined,
                          ),
                          _metric(
                            context,
                            'In Progress',
                            _asInt(_overview['in_progress_tickets']).toString(),
                            Icons.pending_actions_outlined,
                          ),
                          _metric(
                            context,
                            'Waiting Admin',
                            _asInt(_overview['waiting_admin_tickets']).toString(),
                            Icons.person_search_outlined,
                          ),
                          _metric(
                            context,
                            'Response Overdue',
                            _asInt(_overview['overdue_response_tickets'])
                                .toString(),
                            Icons.timer_off_outlined,
                          ),
                          _metric(
                            context,
                            'Resolution Overdue',
                            _asInt(_overview['overdue_resolution_tickets'])
                                .toString(),
                            Icons.warning_amber_rounded,
                          ),
                          _metric(
                            context,
                            'Resolved / ٣٠ ڕۆژ',
                            _asInt(_overview['resolved_30d']).toString(),
                            Icons.task_alt_rounded,
                          ),
                          _metric(
                            context,
                            'Avg First Response',
                            '${_asDouble(_overview['avg_first_response_hours']).toStringAsFixed(1)}h',
                            Icons.speed_rounded,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _filterChip('active', 'چالاک'),
                            _filterChip('open', 'Open'),
                            _filterChip('in_progress', 'In Progress'),
                            _filterChip('waiting_admin', 'Waiting'),
                            _filterChip('resolved', 'Resolved'),
                            _filterChip('closed', 'Closed'),
                            _filterChip('all', 'هەموو'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      const AppSectionHeader(
                        title: 'Support Tickets',
                        subtitle:
                            'SLA بەپێی Standard / Priority / VIP هەژمار دەکرێت',
                      ),
                      const SizedBox(height: 10),
                      if (visible.isEmpty)
                        const AppSurface(
                          child: Center(
                            child: Padding(
                              padding: EdgeInsets.all(20),
                              child: Text('هیچ Ticket ـێک لەم دۆخەدا نییە.'),
                            ),
                          ),
                        )
                      else
                        ...visible.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _ticketCard(context, item),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _filterChip(String value, String label) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _filter == value,
        onSelected: (_) => setState(() => _filter = value),
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

  Widget _ticketCard(
    BuildContext context,
    Map<String, dynamic> item,
  ) {
    final market = (item['market_name'] ?? 'مارکێت').toString();
    final admin = (item['admin_name'] ?? '').toString();
    final phone = (item['phone'] ?? '').toString();
    final subject = (item['subject'] ?? '').toString();
    final message = (item['message'] ?? '').toString();
    final status = (item['status'] ?? 'open').toString();
    final priority = (item['priority'] ?? 'normal').toString();
    final tier = (item['support_tier'] ?? 'standard').toString();
    final responseOverdue = item['response_overdue'] == true;
    final resolutionOverdue = item['resolution_overdue'] == true;
    final ownerResponse = (item['owner_response'] ?? '').toString();

    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                backgroundColor: AppColors.primarySoft,
                child: Icon(
                  Icons.support_agent_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subject,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      admin.isEmpty ? '$market • $phone' : '$market • $admin',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              _statusChip(status),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            message,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _mini(Icons.category_outlined, (item['category'] ?? '').toString()),
              _mini(Icons.priority_high_rounded, priority),
              _mini(Icons.workspace_premium_outlined, tier),
              _mini(
                Icons.timer_outlined,
                'Response: ${_date(item['response_due_at'])}',
              ),
              _mini(
                Icons.event_available_outlined,
                'Resolve: ${_date(item['resolution_due_at'])}',
              ),
              if ((item['app_version'] ?? '').toString().isNotEmpty)
                _mini(
                  Icons.system_update_alt_rounded,
                  (item['app_version'] ?? '').toString(),
                ),
              if ((item['platform'] ?? '').toString().isNotEmpty)
                _mini(
                  Icons.phone_iphone_rounded,
                  (item['platform'] ?? '').toString(),
                ),
            ],
          ),
          if (responseOverdue || resolutionOverdue) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                if (responseOverdue)
                  const Chip(
                    avatar: Icon(Icons.timer_off_outlined, size: 16),
                    label: Text('Response SLA Overdue'),
                  ),
                if (resolutionOverdue)
                  const Chip(
                    avatar: Icon(Icons.warning_amber_rounded, size: 16),
                    label: Text('Resolution SLA Overdue'),
                  ),
              ],
            ),
          ],
          if (ownerResponse.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'وەڵامی Owner: $ownerResponse',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _manageTicket(item),
              icon: const Icon(Icons.manage_accounts_outlined, size: 18),
              label: const Text('بەڕێوەبردنی Ticket'),
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
      'in_progress' => ('In Progress', Colors.blue),
      'waiting_admin' => ('Waiting', Colors.orange),
      'resolved' => ('Resolved', Colors.green),
      'closed' => ('Closed', Colors.grey),
      _ => ('Open', Colors.red),
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
