import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zhirox/utils/latest_request.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/services/owner_autopilot_service.dart';
import 'package:zhirox/widgets/app_design.dart';

class OwnerAutoPilotControlCenterScreen extends StatefulWidget {
  const OwnerAutoPilotControlCenterScreen({super.key});

  @override
  State<OwnerAutoPilotControlCenterScreen> createState() =>
      _OwnerAutoPilotControlCenterScreenState();
}

class _OwnerAutoPilotControlCenterScreenState
    extends State<OwnerAutoPilotControlCenterScreen> {
  static const int _perPage = 25;

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  final LatestRequest _overviewRequest = LatestRequest();
  bool _loading = true;
  String _health = 'all';
  String? _error;
  int _page = 1;
  Map<String, dynamic> _data = const {};

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _overviewRequest.invalidate();
    _searchController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _map(dynamic value) => value is Map
      ? Map<String, dynamic>.from(value)
      : <String, dynamic>{};

  int _number(dynamic value) => value is num
      ? value.toInt()
      : int.tryParse(value?.toString() ?? '') ?? 0;

  Future<void> _refresh({bool resetPage = false}) async {
    if (!mounted) return;
    final request = _overviewRequest.begin();
    setState(() {
      if (resetPage) _page = 1;
      _loading = true;
      _error = null;
    });

    try {
      final data = await OwnerAutoPilotService.overview(
        search: _searchController.text,
        health: _health,
        page: _page,
        perPage: _perPage,
      );
      if (!mounted || !_overviewRequest.isCurrent(request)) return;
      setState(() => _data = data);
    } catch (error) {
      if (!mounted || !_overviewRequest.isCurrent(request)) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted && _overviewRequest.isCurrent(request)) {
        setState(() => _loading = false);
      }
    }
  }

  void _onSearchChanged(String _) {
    _overviewRequest.invalidate();
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 450),
      () => unawaited(_refresh(resetPage: true)),
    );
  }

  void _setHealth(String value) {
    if (_health == value) return;
    setState(() => _health = value);
    unawaited(_refresh(resetPage: true));
  }

  void _goToPage(int value) {
    if (value < 1 || value == _page) return;
    setState(() => _page = value);
    unawaited(_refresh());
  }

  Color _healthColor(BuildContext context, String status) {
    if (status == 'healthy') return const Color(0xFF0B9270);
    if (status == 'degraded') return const Color(0xFFC47B17);
    return Theme.of(context).colorScheme.error;
  }

  String _healthLabel(String status) {
    switch (status) {
      case 'healthy':
        return 'باشە';
      case 'degraded':
        return 'کێشەی هەیە';
      default:
        return 'پێویستی بە پشکنینە';
    }
  }

  Widget _metric(
    BuildContext context, {
    required String label,
    required int value,
    required IconData icon,
    Color? tint,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final color = tint ?? scheme.primary;
    return Container(
      constraints: const BoxConstraints(minWidth: 104),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 5),
          Text(
            value.toString(),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(BuildContext context, Map<String, dynamic> overview) {
    final scheme = Theme.of(context).colorScheme;
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            title: 'دۆخی گشتی AutoPilot',
            subtitle: 'کورتەی تەندروستی automation ـی هەموو مارکێتەکان',
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: width,
                    child: _metric(
                      context,
                      label: 'مارکێت',
                      value: _number(overview['total_markets']),
                      icon: Icons.storefront_rounded,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _metric(
                      context,
                      label: 'Healthy',
                      value: _number(overview['healthy']),
                      icon: Icons.check_circle_outline_rounded,
                      tint: const Color(0xFF0B9270),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _metric(
                      context,
                      label: 'Degraded',
                      value: _number(overview['degraded']),
                      icon: Icons.warning_amber_rounded,
                      tint: const Color(0xFFC47B17),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _metric(
                      context,
                      label: 'Attention',
                      value: _number(overview['attention']),
                      icon: Icons.error_outline_rounded,
                      tint: scheme.error,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _metric(
                      context,
                      label: 'Active Queue',
                      value: _number(overview['active_queue']),
                      icon: Icons.schedule_send_rounded,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _metric(
                      context,
                      label: 'Dead-letter',
                      value: _number(overview['dead_letter']),
                      icon: Icons.report_gmailerrorred_rounded,
                      tint: scheme.error,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _infoChip(
                context,
                'AutoPilot ON: ${_number(overview['autopilot_enabled'])}',
                Icons.auto_awesome_rounded,
              ),
              _infoChip(
                context,
                'Telegram: ${_number(overview['telegram_linked_customers'])}',
                Icons.telegram_rounded,
              ),
              _infoChip(
                context,
                'Risk: ${_number(overview['risk_total'])}',
                Icons.shield_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoChip(BuildContext context, String text, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: scheme.primary),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: scheme.primary,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _marketCard(BuildContext context, Map<String, dynamic> item) {
    final scheme = Theme.of(context).colorScheme;
    final health = _map(item['health']);
    final autopilot = _map(item['autopilot']);
    final telegram = _map(item['telegram']);
    final receipts = _map(item['receipts']);
    final statements = _map(item['statements']);
    final notifications = _map(item['notifications']);
    final risk = _map(item['risk']);
    final status = health['status']?.toString() ?? 'attention';
    final color = _healthColor(context, status);
    final enabled = autopilot['enabled'] == true;
    final mode = autopilot['mode']?.toString() ?? 'manual';
    final issueCount = _number(item['issue_count']);

    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.storefront_rounded, color: color, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['market_name']?.toString() ?? 'مارکێت',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item['admin_name']?.toString() ?? '',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  _healthLabel(status),
                  style: TextStyle(
                    color: color,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                enabled ? Icons.auto_awesome_rounded : Icons.pause_circle_outline,
                color: enabled ? const Color(0xFF0B9270) : scheme.onSurfaceVariant,
                size: 18,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  enabled ? 'AutoPilot چالاکە • $mode' : 'AutoPilot ناچالاکە • $mode',
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
                ),
              ),
              if (issueCount > 0)
                Text(
                  '$issueCount کێشە',
                  style: TextStyle(
                    color: scheme.error,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 12) / 4;
              return Row(
                children: [
                  SizedBox(
                    width: width,
                    child: _smallMetric('Queue', _number(health['active_queue'])),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: width,
                    child: _smallMetric('Retry', _number(health['retrying'])),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: width,
                    child: _smallMetric('Failed', _number(health['failed'])),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: width,
                    child: _smallMetric('Dead', _number(health['dead_letter'])),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 11),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _infoChip(
                context,
                'Telegram ${_number(telegram['linked_customers'])}',
                Icons.telegram_rounded,
              ),
              _infoChip(
                context,
                'Receipt/24h ${_number(receipts['sent_24h'])}',
                Icons.receipt_long_rounded,
              ),
              _infoChip(
                context,
                'Statement/30d ${_number(statements['completed_30d'])}',
                Icons.description_outlined,
              ),
              _infoChip(
                context,
                'Notify/24h ${_number(notifications['completed_24h'])}',
                Icons.notifications_active_outlined,
              ),
              _infoChip(
                context,
                'Risk ${_number(risk['total'])} • H ${_number(risk['high'])} • C ${_number(risk['critical'])}',
                Icons.shield_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _smallMetric(String label, int value) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        children: [
          Text(
            value.toString(),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 8.5),
          ),
        ],
      ),
    );
  }

  Widget _filters(BuildContext context) {
    const options = <(String, String)>[
      ('all', 'هەموو'),
      ('healthy', 'Healthy'),
      ('degraded', 'Degraded'),
      ('attention', 'Attention'),
    ];
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'گەڕان بە ناوی مارکێت یان بەڕێوەبەر',
            ),
            onChanged: _onSearchChanged,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final option in options)
                ChoiceChip(
                  label: Text(option.$2),
                  selected: _health == option.$1,
                  onSelected: (_) => _setHealth(option.$1),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pagination(BuildContext context, int totalPages, int totalItems) {
    if (totalPages <= 1) return const SizedBox.shrink();
    return AppSurface(
      child: Row(
        children: [
          IconButton.filledTonal(
            onPressed: _loading || _page <= 1 ? null : () => _goToPage(_page - 1),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  'پەڕە $_page / $totalPages',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  '$totalItems مارکێت',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            onPressed: _loading || _page >= totalPages
                ? null
                : () => _goToPage(_page + 1),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isSystemOwner = auth.user?.getBoolValue('is_system_owner') ?? false;
    if (!isSystemOwner) {
      return Scaffold(
        appBar: AppBar(title: const Text('AutoPilot Control Center')),
        body: const OwnerStatePanel.error(
          title: 'دەستگەیشتن ڕێگەپێنەدراوە',
          message: 'تەنها System Owner دەتوانێت ئەم ناوەندە ببینێت.',
          actionLabel: null,
        ),
      );
    }

    final overview = _map(_data['overview']);
    final rawItems = _data['items'];
    final items = rawItems is List
        ? rawItems
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
        : <Map<String, dynamic>>[];
    final totalPages = _number(_data['total_pages']);
    final totalItems = _number(_data['total_items']);

    if (_loading && _data.isEmpty) {
      return const Scaffold(
        body: SafeArea(child: OwnerStatePanel.loading()),
      );
    }

    if (_error != null && _data.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('AutoPilot Control Center')),
        body: OwnerStatePanel.error(
          message: _error,
          onAction: () => unawaited(_refresh()),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('AutoPilot Control Center'),
        actions: [
          IconButton(
            tooltip: 'نوێکردنەوە',
            onPressed: _loading ? null : () => unawaited(_refresh()),
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            _summaryCard(context, overview),
            const SizedBox(height: 12),
            _filters(context),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 14),
            AppSectionHeader(
              title: 'مارکێتەکان',
              subtitle: totalItems == 0
                  ? 'هیچ مارکێتێک بەم فیلتەرە نەدۆزرایەوە.'
                  : '$totalItems مارکێت لە ئەم فیلتەرەدا',
            ),
            const SizedBox(height: 10),
            if (items.isEmpty)
              const OwnerStatePanel.empty(
                title: 'هیچ مارکێتێک نەدۆزرایەوە',
                message: 'گەڕان یان فیلتەرەکە بگۆڕە.',
              )
            else
              for (final item in items) ...[
                _marketCard(context, item),
                const SizedBox(height: 10),
              ],
            _pagination(context, totalPages, totalItems),
          ],
        ),
      ),
    );
  }
}

