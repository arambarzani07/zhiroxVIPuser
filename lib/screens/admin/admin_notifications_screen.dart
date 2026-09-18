import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zhirox/screens/shared/user_profile_screen.dart';
import 'package:zhirox/services/customer_push_service.dart';
import 'package:zhirox/widgets/manual_push_broadcast_card.dart';

class AdminNotificationsScreen extends StatefulWidget {
  const AdminNotificationsScreen({super.key});

  @override
  State<AdminNotificationsScreen> createState() =>
      _AdminNotificationsScreenState();
}

class _AdminNotificationsScreenState extends State<AdminNotificationsScreen> {
  static const int _pageSize = 60;

  final CustomerPushGateway _gateway = const CustomerPushService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<CustomerPushOverviewItem> _items = const [];
  CustomerPushOverviewSummary? _summary;
  String _filter = 'all';
  String? _busyCustomerId;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _totalCount = 0;
  String? _error;
  Timer? _searchDebounce;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore ||
        _loading ||
        _loadingMore ||
        !_scrollController.hasClients ||
        _scrollController.position.extentAfter >= 500) {
      return;
    }
    unawaited(_load(loadMore: true));
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      unawaited(_load());
    });
  }

  Future<void> _load({bool loadMore = false}) async {
    if (!mounted) return;
    if (loadMore && (_loadingMore || !_hasMore)) return;

    final generation = ++_generation;
    setState(() {
      if (loadMore) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
      }
    });

    try {
      final page = await _gateway.loadOverview(
        search: _searchController.text.trim(),
        filter: _filter,
        limit: _pageSize,
        offset: loadMore ? _items.length : 0,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = loadMore ? [..._items, ...page.items] : page.items;
        _totalCount = page.totalCount;
        _summary = page.summary;
        _hasMore = page.hasMore;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = 'نەتوانرا دۆخی ئاگادارکردنەوەی کڕیاران باربکرێت';
      });
    }
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'sent':
        return 'نێردرا';
      case 'pending':
        return 'لە ڕیزدایە';
      case 'partial':
        return 'بەشێکی نێردرا';
      case 'failed':
        return 'شکست';
      case 'no_device':
        return 'ئامێری چالاک نەبوو';
      default:
        return 'هێشتا نەنێردراوە';
    }
  }

  Color _statusColor(BuildContext context, CustomerPushOverviewItem item) {
    if (!item.active) return Theme.of(context).colorScheme.outline;
    switch (item.latestStatus) {
      case 'failed':
        return Theme.of(context).colorScheme.error;
      case 'pending':
      case 'partial':
        return Colors.orange;
      default:
        return Colors.green;
    }
  }

  int _filterCount(String filter) {
    final summary = _summary;
    if (summary == null) return 0;
    switch (filter) {
      case 'active':
        return summary.active;
      case 'inactive':
        return summary.inactive;
      case 'failed':
        return summary.failed;
      case 'pending':
        return summary.pending;
      default:
        return summary.all;
    }
  }

  String _filterLabel(String filter) {
    switch (filter) {
      case 'active':
        return 'چالاک';
      case 'inactive':
        return 'ناچالاک';
      case 'failed':
        return 'شکست';
      case 'pending':
        return 'لە ڕیزدایە';
      default:
        return 'هەموو';
    }
  }

  void _selectFilter(String filter) {
    if (_filter == filter) return;
    setState(() => _filter = filter);
    unawaited(_load());
  }

  Future<void> _sendManual(CustomerPushOverviewItem item) async {
    if (_busyCustomerId != null || !item.active) return;
    final formKey = GlobalKey<FormState>();
    var draft = '';
    final message = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: Text('ئاگاداری بۆ ${item.name}'),
        content: Form(
          key: formKey,
          child: TextFormField(
            autofocus: true,
            minLines: 3,
            maxLines: 5,
            maxLength: CustomerPushService.manualMessageMaxLength,
            onChanged: (value) => draft = value,
            decoration: const InputDecoration(
              labelText: 'پەیامی ئاگادارکردنەوە',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final normalized = value?.trim() ?? '';
              if (normalized.isEmpty) return 'پەیام بنووسە';
              if (normalized.length > CustomerPushService.manualMessageMaxLength) {
                return 'پەیام زۆر درێژە';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('پاشگەزبوونەوە'),
          ),
          FilledButton.icon(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.of(dialogContext).pop(draft.trim());
            },
            icon: const Icon(Icons.send_rounded),
            label: const Text('ناردن'),
          ),
        ],
      ),
    );
    if (!mounted || message == null) return;

    setState(() => _busyCustomerId = item.customerId);
    try {
      final result = await _gateway.sendManual(item.customerId, message);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.targetDevices > 0
                ? 'ئاگاداری بۆ ${result.targetDevices} ئامێر ڕیزکرا'
                : 'هیچ ئامێرێکی چالاک بۆ ئەم کڕیارە نییە',
          ),
        ),
      );
      unawaited(_load());
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ناردنی ئاگاداری سەرکەوتوو نەبوو')),
      );
    } finally {
      if (mounted) setState(() => _busyCustomerId = null);
    }
  }

  Future<void> _openCustomer(CustomerPushOverviewItem item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(userId: item.customerId),
      ),
    );
    if (mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('ئاگادارکردنەوەکان'),
        actions: [
          IconButton(
            tooltip: 'نوێکردنەوە',
            onPressed: _loading ? null : () => _load(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(),
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            const ManualPushBroadcastCard(),
            const SizedBox(height: 18),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: const ['all', 'active', 'inactive', 'failed', 'pending']
                    .map((filter) {
                  final selected = _filter == filter;
                  return Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      selected: selected,
                      showCheckmark: false,
                      onSelected: (_) => _selectFilter(filter),
                      label: Text(
                        '${_filterLabel(filter)} (${_filterCount(filter)})',
                      ),
                    ),
                  );
                }).toList(growable: false),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'کڕیارەکان',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '$_totalCount کڕیار',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'گەڕان بە ناو یان ژمارە...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          unawaited(_load());
                        },
                        icon: const Icon(Icons.clear_rounded),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 42),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Column(
                  children: [
                    Icon(
                      Icons.cloud_off_rounded,
                      color: theme.colorScheme.error,
                      size: 38,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => _load(),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('دووبارە هەوڵبدەوە'),
                    ),
                  ],
                ),
              )
            else if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: Center(
                  child: Text('هیچ کڕیارێک نەدۆزرایەوە'),
                ),
              )
            else ...[
              ..._items.map((item) {
                final color = _statusColor(context, item);
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    onTap: () => _openCustomer(item),
                    leading: CircleAvatar(
                      backgroundColor: color.withValues(alpha: 0.12),
                      foregroundColor: color,
                      child: Icon(
                        item.active
                            ? Icons.notifications_active_rounded
                            : Icons.notifications_off_outlined,
                      ),
                    ),
                    title: Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (item.phone.isNotEmpty)
                          Text(
                            item.phone,
                            textDirection: TextDirection.ltr,
                          ),
                        Text(
                          item.active
                              ? 'چالاک • ${item.deviceCount} ئامێر • ${_statusLabel(item.latestStatus)}'
                              : item.activeLinkCount > 0
                                  ? 'QR چالاکە • هێشتا ئامێر پەیوەست نییە'
                                  : 'ئاگادارکردنەوە ناچالاکە',
                          style: TextStyle(color: color),
                        ),
                      ],
                    ),
                    trailing: item.active
                        ? PopupMenuButton<String>(
                            tooltip: 'کردارەکان',
                            enabled: _busyCustomerId == null,
                            onSelected: (value) {
                              if (value == 'send') {
                                unawaited(_sendManual(item));
                              } else if (value == 'open') {
                                unawaited(_openCustomer(item));
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem<String>(
                                value: 'send',
                                child: Row(
                                  children: [
                                    Icon(Icons.send_rounded, size: 20),
                                    SizedBox(width: 10),
                                    Text('ناردنی ئاگاداری'),
                                  ],
                                ),
                              ),
                              PopupMenuItem<String>(
                                value: 'open',
                                child: Row(
                                  children: [
                                    Icon(Icons.person_outline_rounded, size: 20),
                                    SizedBox(width: 10),
                                    Text('کردنەوەی کڕیار'),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : const Icon(Icons.chevron_left_rounded),
                  ),
                );
              }),
              if (_loadingMore)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (_hasMore)
                TextButton.icon(
                  onPressed: () => _load(loadMore: true),
                  icon: const Icon(Icons.expand_more_rounded),
                  label: const Text('کڕیاری زیاتر'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
