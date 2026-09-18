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
        limit: _pageSize,
        offset: loadMore ? _items.length : 0,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = loadMore ? [..._items, ...page.items] : page.items;
        _totalCount = page.totalCount;
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
                    trailing: const Icon(Icons.chevron_left_rounded),
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
