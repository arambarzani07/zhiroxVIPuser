import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

class DebtRestoreScreen extends StatefulWidget {
  const DebtRestoreScreen({super.key});

  @override
  State<DebtRestoreScreen> createState() => _DebtRestoreScreenState();
}

class _DebtRestoreScreenState extends State<DebtRestoreScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;
  String? _error;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool showLoader = true}) async {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    if (auth.userRole != 'admin') {
      setState(() {
        _items = [];
        _isLoading = false;
        _error = 'تەنها بەڕێوەبەر دەتوانێت کردارە سڕاوەکان ببینێت.';
      });
      return;
    }

    if (showLoader) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final response = await PBService.client.functions.invoke(
        'debt-restore-admin',
        body: const {'action': 'list'},
      );
      final data = response.data;
      if (data is! Map || data['items'] is! List) {
        throw Exception('invalid_restore_response');
      }
      final rows = (data['items'] as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      if (!mounted) return;
      setState(() {
        _items = rows;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = AppHelpers.backendErrorMessage(
          e,
          fallback: 'نەتوانرا کردارە سڕاوەکان وەربگیرێن. دووبارە هەوڵ بدە.',
        );
      });
    }
  }

  Future<void> _restore(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty || _busyId != null) return;

    setState(() => _busyId = id);
    try {
      final response = await PBService.client.functions.invoke(
        'debt-restore-admin',
        body: {'action': 'restore', 'debt_id': id},
      );
      final data = response.data;
      if (data is! Map || data['restored'] != true) {
        final code = data is Map ? data['error']?.toString() : null;
        throw Exception(code ?? 'restore_failed');
      }
      if (!mounted) return;
      setState(() => _items.removeWhere((row) => row['id']?.toString() == id));
      AppHelpers.showSnackBar(context, 'قەرزەکە گەڕێندرایەوە ✅');
    } catch (e) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          e,
          fallback: 'گەڕاندنەوەی قەرز سەرکەوتوو نەبوو.',
        ),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAdmin = context.watch<AuthProvider>().userRole == 'admin';
    final background =
        isDark ? AppDarkColors.background : const Color(0xFFF7F8FA);

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: const Text(
          'گەڕاندنەوەی کردار',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        backgroundColor: isDark ? AppDarkColors.card : Colors.white,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'نوێکردنەوە',
            onPressed: _isLoading || !isAdmin ? null : () => _load(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: !isAdmin
          ? _buildDenied(isDark)
          : RefreshIndicator(
              onRefresh: () => _load(showLoader: false),
              child: _buildBody(isDark),
            ),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_isLoading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 220),
          Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
        ],
      );
    }

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 28),
        children: [
          const SizedBox(height: 150),
          const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.orange),
          const SizedBox(height: 14),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(
              height: 1.6,
              color: isDark
                  ? AppDarkColors.textPrimary
                  : const Color(0xFF344054),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton.icon(
              onPressed: () => _load(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('دووبارە هەوڵ بدە'),
            ),
          ),
        ],
      );
    }

    if (_items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 28),
        children: [
          const SizedBox(height: 150),
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(
              Icons.restore_from_trash_outlined,
              size: 36,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'هیچ قەرزێکی سڕاوە نییە',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: isDark
                  ? AppDarkColors.textPrimary
                  : const Color(0xFF344054),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'قەرزە سڕاوەکان لێرە دەردەکەون و دەتوانیت بە یەک کلیک بیانگەڕێنیتەوە.',
            textAlign: TextAlign.center,
            style: TextStyle(
              height: 1.6,
              fontSize: 12,
              color: isDark
                  ? AppDarkColors.textSecondary
                  : const Color(0xFF98A2B3),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: _items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _buildCard(_items[index], isDark),
    );
  }

  Widget _buildCard(Map<String, dynamic> item, bool isDark) {
    final id = item['id']?.toString() ?? '';
    final customerName = item['customer_name']?.toString().trim() ?? '';
    final description = item['description']?.toString().trim() ?? '';
    final currency = item['currency']?.toString().trim() ?? 'IQD';
    final amount = _asDouble(item['amount']);
    final deletedAt = item['deleted_at']?.toString() ?? '';
    final busy = _busyId == id;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? AppDarkColors.cardBorder
              : const Color(0xFFE9EDF3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.red,
                  size: 22,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customerName.isEmpty ? 'کڕیار' : customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? AppDarkColors.textPrimary
                            : const Color(0xFF344054),
                      ),
                    ),
                    if (deletedAt.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        'سڕاوەتەوە: ${AppHelpers.formatDate(deletedAt)}',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: isDark
                              ? AppDarkColors.textSecondary
                              : const Color(0xFF98A2B3),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                AppHelpers.formatCurrencyWithType(
                  amount,
                  currency,
                  showConversion: false,
                ),
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: isDark
                      ? AppDarkColors.textPrimary
                      : const Color(0xFF101828),
                ),
              ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                height: 1.5,
                fontSize: 12,
                color: isDark
                    ? AppDarkColors.textSecondary
                    : const Color(0xFF667085),
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton.icon(
              onPressed: busy || _busyId != null ? null : () => _restore(item),
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.restore_rounded, size: 19),
              label: const Text('گەڕاندنەوە'),
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDenied(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline_rounded, size: 48, color: Colors.orange),
            const SizedBox(height: 14),
            Text(
              'تەنها بەڕێوەبەر دەسەڵاتی گەڕاندنەوەی کردارە سڕاوەکانی هەیە.',
              textAlign: TextAlign.center,
              style: TextStyle(
                height: 1.6,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? AppDarkColors.textPrimary
                    : const Color(0xFF344054),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
