import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:zhirox/widgets/app_design.dart';

class OwnerDomainCenterScreen extends StatefulWidget {
  const OwnerDomainCenterScreen({super.key});

  @override
  State<OwnerDomainCenterScreen> createState() => _OwnerDomainCenterScreenState();
}

class _OwnerDomainCenterScreenState extends State<OwnerDomainCenterScreen> {
  Map<String, dynamic> _overview = const {};
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;

  int _asInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('${value ?? 0}') ?? 0;

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
        PBService.getOwnerDomainOverview(),
        PBService.getOwnerDomainPage(page: 1, perPage: 100),
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
          fallback: 'نەتوانرا زانیاری دۆمەینەکان بهێنرێت.',
        );
      });
    }
  }

  Future<void> _edit(Map<String, dynamic> item) async {
    final host = TextEditingController(text: '${item['hostname'] ?? ''}');
    final target = TextEditingController(
      text: '${item['routing_target'] ?? ''}',
    );
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          scrollable: true,
          title: Text('${item['market_name'] ?? 'مارکێت'}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: host,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'دۆمەین',
                  hintText: 'portal.example.com',
                  prefixIcon: Icon(Icons.language_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: target,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'CNAME Target',
                  hintText: 'target.example.net',
                  prefixIcon: Icon(Icons.alt_route_rounded),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'ئەگەر دۆمەینەکە بەتاڵ بکەیت و پاشەکەوت بکەیت، '
                'ڕێکخستنەکە لادەبرێت. ئەم بەشە تەنها routing metadata ـە.',
                style: TextStyle(fontSize: 11),
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
      );
      if (ok != true) return;

      await PBService.setOwnerTenantDomain(
        adminId: item['id'].toString(),
        hostname: host.text.trim(),
        routingTarget: target.text.trim(),
      );
      if (!mounted) return;
      AppHelpers.showSnackBar(context, 'ڕێکخستنی دۆمەین نوێ کرایەوە.');
      await _load();
    } catch (error) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          error,
          fallback: 'نوێکردنەوەی دۆمەین سەرکەوتوو نەبوو.',
        ),
        isError: true,
      );
    } finally {
      host.dispose();
      target.dispose();
    }
  }

  Future<void> _check(Map<String, dynamic> item) async {
    try {
      await PBService.checkOwnerTenantDomain(item['id'].toString());
      if (!mounted) return;
      AppHelpers.showSnackBar(context, 'DNS و HTTPS پشکنران.');
      await _load();
    } catch (error) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          error,
          fallback: 'پشکنینی دۆمەین سەرکەوتوو نەبوو.',
        ),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('دۆمەین و HTTPS'),
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
                      const AppSurface(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.language_rounded, color: AppColors.primary),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'خاوەنی سیستەم تەنها دۆمەین، CNAME و دۆخی HTTPS '
                                'بەڕێوەدەبات. هیچ ناوەڕۆکی کاروباری مارکێت '
                                'لەم ناوەندەدا نییە.',
                                style: TextStyle(height: 1.55),
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
                          _metric('مارکێت', _asInt(_overview['tenant_count']), Icons.storefront_outlined),
                          _metric('دۆمەینی ڕێکخراو', _asInt(_overview['configured_domains']), Icons.public_rounded),
                          _metric('DNS پشتڕاست', _asInt(_overview['dns_verified']), Icons.verified_outlined),
                          _metric('HTTPS بەردەست', _asInt(_overview['https_reachable']), Icons.lock_outline_rounded),
                          _metric('پێویستی بە پشکنین', _asInt(_overview['needs_attention']), Icons.warning_amber_rounded),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const AppSectionHeader(
                        title: 'ڕێکخستنی دۆمەین',
                        subtitle: 'CNAME و HTTPS status بۆ هەر هەژماری مارکێت',
                      ),
                      const SizedBox(height: 10),
                      ..._items.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _card(item),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _metric(String label, int value, IconData icon) {
    return SizedBox(
      width: 160,
      child: AppSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.primary, size: 22),
            const SizedBox(height: 10),
            Text(
              value.toString(),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _card(Map<String, dynamic> item) {
    final configured = item['configured'] == true;
    final dns = '${item['dns_status'] ?? 'pending'}';
    final https = '${item['https_status'] ?? 'unknown'}';

    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                backgroundColor: AppColors.primarySoft,
                child: Icon(Icons.public_rounded, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item['market_name'] ?? 'مارکێت'}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      configured ? '${item['hostname']}' : 'هێشتا دۆمەین ڕێکنەخراوە',
                      style: Theme.of(context).textTheme.bodySmall,
                      textDirection: TextDirection.ltr,
                    ),
                  ],
                ),
              ),
              _status(dns, https),
            ],
          ),
          if (configured) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _mini(Icons.alt_route_rounded, 'CNAME: ${item['routing_target']}'),
                _mini(Icons.dns_outlined, 'DNS: ${_dnsLabel(dns)}'),
                _mini(Icons.lock_outline_rounded, 'HTTPS: ${_httpsLabel(https)}'),
                _mini(Icons.http_rounded, 'HTTP: ${item['last_http_status'] ?? '—'}'),
                _mini(Icons.history_rounded, _date(item['last_checked_at'])),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _edit(item),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(configured ? 'دەستکاری' : 'ڕێکخستن'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: configured ? () => _check(item) : null,
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: const Text('پشکنین'),
                ),
              ),
            ],
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

  Widget _status(String dns, String https) {
    final ok = dns == 'verified' && https == 'reachable';
    final pending = dns == 'pending' || https == 'unknown';
    final color = ok ? Colors.green : pending ? Colors.orange : Colors.red;
    final label = ok ? 'ئامادە' : pending ? 'چاوەڕوان' : 'پشکنین';
    return Chip(
      label: Text(label),
      backgroundColor: color.withValues(alpha: 0.10),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w800),
    );
  }

  String _dnsLabel(String value) => switch (value) {
        'verified' => 'پشتڕاست',
        'mismatch' => 'ناگونجێت',
        'error' => 'هەڵە',
        _ => 'چاوەڕوان',
      };

  String _httpsLabel(String value) => switch (value) {
        'reachable' => 'بەردەست',
        'unreachable' => 'نەگەیشتوو',
        'error' => 'هەڵە',
        _ => 'نەپشکنراو',
      };
}
