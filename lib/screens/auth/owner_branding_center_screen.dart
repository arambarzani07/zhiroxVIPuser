import 'package:flutter/material.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/helpers.dart';

class OwnerBrandingCenterScreen extends StatefulWidget {
  const OwnerBrandingCenterScreen({super.key});

  @override
  State<OwnerBrandingCenterScreen> createState() =>
      _OwnerBrandingCenterScreenState();
}

class _OwnerBrandingCenterScreenState extends State<OwnerBrandingCenterScreen> {
  Map<String, dynamic> _overview = const {};
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;

  int _asInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('${value ?? 0}') ?? 0;

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
        PBService.getOwnerBrandingOverview(),
        PBService.getOwnerBrandingPage(page: 1, perPage: 100),
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
          fallback: 'نەتوانرا ڕێکخستنی ناسنامەی مارکێتەکان بهێنرێت.',
        );
      });
    }
  }

  Future<void> _edit(Map<String, dynamic> item) async {
    final brandName = TextEditingController(
      text: '${item['brand_name'] ?? ''}',
    );
    final logoUrl = TextEditingController(
      text: '${item['logo_url'] ?? ''}',
    );
    final primaryColor = TextEditingController(
      text: '${item['primary_color_hex'] ?? '#4459DB'}',
    );
    var enabled = item['branding_enabled'] == true;
    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            scrollable: true,
            title: Text('${item['market_name'] ?? 'مارکێت'}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: enabled,
                  onChanged: item['feature_enabled'] == true
                      ? (value) => setDialogState(() => enabled = value)
                      : null,
                  title: const Text('چالاککردنی ناسنامەی تایبەت'),
                  subtitle: Text(
                    item['feature_enabled'] == true
                        ? 'ناو، لۆگۆ و ڕەنگی تایبەتی مارکێت بەکاربهێنە.'
                        : 'ئەم تایبەتمەندییە بۆ پلانی ئەم مارکێتە چالاک نییە.',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: brandName,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'ناوی پیشاندراو',
                    prefixIcon: Icon(Icons.storefront_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: logoUrl,
                  textDirection: TextDirection.ltr,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'بەستەری لۆگۆ',
                    hintText: 'https://...',
                    prefixIcon: Icon(Icons.image_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: primaryColor,
                  textDirection: TextDirection.ltr,
                  maxLength: 7,
                  decoration: const InputDecoration(
                    labelText: 'ڕەنگی سەرەکی',
                    hintText: '#4459DB',
                    prefixIcon: Icon(Icons.palette_outlined),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('پاشگەزبوونەوە'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('پاشەکەوت'),
              ),
            ],
          ),
        ),
      );
      if (accepted != true) return;

      final color = primaryColor.text.trim().toUpperCase();
      final validColor = RegExp(r'^#[0-9A-F]{6}$').hasMatch(color);
      if (!validColor) {
        if (!mounted) return;
        AppHelpers.showSnackBar(
          context,
          'ڕەنگ دەبێت بە شێوەی #4459DB بێت.',
          isError: true,
        );
        return;
      }

      await PBService.setOwnerTenantBranding(
        adminId: item['id'].toString(),
        enabled: enabled,
        brandName: brandName.text.trim(),
        logoUrl: logoUrl.text.trim(),
        primaryColorHex: color,
      );
      if (!mounted) return;
      AppHelpers.showSnackBar(context, 'ڕێکخستنەکە پاشەکەوت کرا.');
      await _load();
    } catch (error) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          error,
          fallback: 'پاشەکەوتکردنی ڕێکخستنەکە سەرکەوتوو نەبوو.',
        ),
        isError: true,
      );
    } finally {
      brandName.dispose();
      logoUrl.dispose();
      primaryColor.dispose();
    }
  }

  Widget _summaryCard(String title, int value, IconData icon) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Icon(icon),
              const SizedBox(height: 8),
              Text(
                '$value',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              Text(title, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ناسنامە و ڕووکار'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'نوێکردنەوە',
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
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('دووبارە هەوڵدانەوە'),
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
                      Text(
                        'ناسنامەی تایبەتی مارکێتەکان',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'ناو، لۆگۆ و ڕەنگی پیشاندانی مارکێت بەبێ دەستگەیشتن بە ناوەڕۆکی کاری مارکێت.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _summaryCard(
                            'ڕێکخراو',
                            _asInt(_overview['configured_tenants']),
                            Icons.palette_outlined,
                          ),
                          const SizedBox(width: 8),
                          _summaryCard(
                            'چالاک',
                            _asInt(_overview['enabled_tenants']),
                            Icons.check_circle_outline,
                          ),
                          const SizedBox(width: 8),
                          _summaryCard(
                            'مۆڵەت‌پێدراو',
                            _asInt(_overview['entitled_tenants']),
                            Icons.verified_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      if (_items.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Text(
                              'هیچ مارکێتێک بۆ پیشاندان بەردەست نییە.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      for (final item in _items)
                        Card(
                          child: ListTile(
                            minTileHeight: 82,
                            leading: CircleAvatar(
                              child: Icon(
                                item['branding_enabled'] == true
                                    ? Icons.palette_rounded
                                    : Icons.palette_outlined,
                              ),
                            ),
                            title: Text(
                              '${item['market_name'] ?? 'مارکێت'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              item['feature_enabled'] == true
                                  ? (item['branding_enabled'] == true
                                      ? 'ناسنامەی تایبەت چالاکە'
                                      : 'ئامادەی چالاککردن')
                                  : 'تایبەتمەندییەکە مۆڵەتی نییە',
                            ),
                            trailing: const Icon(Icons.chevron_left_rounded),
                            onTap: () => _edit(item),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
