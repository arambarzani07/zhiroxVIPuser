import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/features/expiry/expiry_catalog_service.dart';
import 'package:zhirox/features/expiry/expiry_date_scanner.dart';
import 'package:zhirox/features/expiry/expiry_reminder_service.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/services/notification_service.dart';
import 'package:zhirox/utils/helpers.dart';

class ExpiryMonitorScreen extends StatefulWidget {
  const ExpiryMonitorScreen({super.key, required this.canManage});
  final bool canManage;

  @override
  State<ExpiryMonitorScreen> createState() => _ExpiryMonitorScreenState();
}

class _ExpiryMonitorScreenState extends State<ExpiryMonitorScreen> {
  bool get _mobileFeatures => !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
       defaultTargetPlatform == TargetPlatform.android);
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _arrivals = [];
  Map<String, List<Map<String, dynamic>>> _arrivalsByProduct = {};
  final _search = TextEditingController();
  bool _loading = true;
  int? _importCompleted;
  int? _importTotal;
  bool _remindersEnabled = false;
  bool _remindersBusy = false;
  int _scheduledDays = 0;
  String? _error;
  String _filter = 'active';

  @override
  void initState() {
    super.initState();
    _search.addListener(_refreshView);
    _load();
  }

  @override
  void dispose() {
    _search.removeListener(_refreshView);
    _search.dispose();
    super.dispose();
  }

  void _refreshView() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    final adminId = auth.adminId;
    setState(() {
      _loading = true;
      _importCompleted = null;
      _importTotal = null;
      _error = null;
    });
    try {
      final products = await ExpiryCatalogService.products(adminId);
      final arrivals = await ExpiryCatalogService.arrivals(adminId);
      if (!mounted) return;
      setState(() {
        _products = products;
        _arrivals = arrivals;
        _arrivalsByProduct = {};
        for (final arrival in arrivals) {
          (_arrivalsByProduct['${arrival['product_id']}'] ??= []).add(arrival);
        }
        _loading = false;
      });
      if (_mobileFeatures) {
        unawaited(_syncReminders(adminId, auth.userId, arrivals));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = AppHelpers.backendErrorMessage(
          error,
          fallback: 'نەتوانرا بەروارەکانی کاڵا بهێنرێن.',
        );
        _loading = false;
      });
    }
  }

  Future<void> _syncReminders(
    String tenant,
    String user,
    List<Map<String, dynamic>> arrivals,
  ) async {
    if (_remindersBusy) return;
    setState(() => _remindersBusy = true);
    try {
      final enabled = await ExpiryReminderService.enabled(tenant, user);
      final permitted = await NotificationService.isPermissionGranted();
      if (!mounted) return;
      setState(() => _remindersEnabled = enabled && permitted);
      if (enabled && permitted) {
        final count = await ExpiryReminderService.refresh(
          tenant: tenant,
          user: user,
          arrivals: arrivals,
        );
        if (mounted) setState(() => _scheduledDays = count);
      }
    } catch (_) {
      if (mounted) setState(() => _scheduledDays = 0);
    } finally {
      if (mounted) setState(() => _remindersBusy = false);
    }
  }

  Future<void> _toggleReminders(bool value) async {
    final auth = context.read<AuthProvider>();
    setState(() => _remindersBusy = true);
    try {
      final count = await ExpiryReminderService.setEnabled(
        tenant: auth.adminId,
        user: auth.userId,
        value: value,
        arrivals: _arrivals,
      );
      if (mounted) {
        setState(() {
          _remindersEnabled = value;
          _scheduledDays = count;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is FormatException
                  ? error.message
                  : 'نەتوانرا ئاگادارکردنەوە چالاک بکرێت.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _remindersBusy = false);
    }
  }

  static DateTime? _day(dynamic raw) {
    final date = DateTime.tryParse('${raw ?? ''}');
    return date == null ? null : DateTime(date.year, date.month, date.day);
  }

  int? _days(dynamic raw) {
    final date = _day(raw);
    if (date == null) return null;
    final now = DateTime.now();
    return date.difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  List<Map<String, dynamic>> _forProduct(
    String id, {
    bool includeResolved = true,
  }) => (_arrivalsByProduct[id] ?? const <Map<String, dynamic>>[])
      .where((a) => includeResolved || a['resolved_at'] == null)
      .toList();

  Map<String, dynamic>? _findProduct(String text) {
    final needle = text.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final product in _products) {
      if ('${product['barcode'] ?? ''}'.toLowerCase() == needle ||
          '${product['external_code'] ?? ''}'.toLowerCase() == needle) {
        return product;
      }
    }
    return null;
  }

  Future<String?> _scan() async {
    bool found = false;
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (scanContext) => Scaffold(
          appBar: AppBar(title: const Text('سکانکردنی بارکۆد')),
          body: MobileScanner(
            onDetect: (capture) {
              if (found || capture.barcodes.isEmpty) return;
              final code = capture.barcodes.first.rawValue?.trim();
              if (code == null || code.isEmpty) return;
              found = true;
              Navigator.of(scanContext).pop(code);
            },
          ),
        ),
      ),
    );
  }

  Future<void> _addArrival([Map<String, dynamic>? selected]) async {
    if (_products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('سەرەتا فایلی کاڵاکان هاوردە بکە.')),
      );
      return;
    }
    final lookup = TextEditingController(
      text: '${selected?['barcode'] ?? selected?['external_code'] ?? ''}',
    );
    final batch = TextEditingController();
    var product = selected;
    DateTime? expiry;
    String? formError;
    bool saving = false;
    final auth = context.read<AuthProvider>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('بەرواری هاتووی نوێ'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: lookup,
                  decoration: InputDecoration(
                    labelText: 'بارکۆد یان کۆدی کاڵا',
                    suffixIcon: _mobileFeatures ? IconButton(
                      tooltip: 'سکانکردنی بارکۆد',
                      icon: const Icon(Icons.qr_code_scanner),
                      onPressed: () async {
                        final code = await _scan();
                        if (!context.mounted || code == null) return;
                        lookup.text = code;
                        refresh(() {
                          product = _findProduct(code);
                          formError = null;
                        });
                      },
                    ) : null,
                  ),
                  onChanged: (text) => refresh(() {
                    product = _findProduct(text);
                    formError = null;
                  }),
                ),
                if (product != null)
                  ListTile(
                    title: Text('${product!['name']}'),
                    subtitle: Text('${product!['external_code']}'),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text('کاڵاکە لە فایلی هاوردەکراو نەدۆزرایەوە.'),
                  ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event),
                  label: Text(
                    expiry == null
                        ? 'بەرواری بەسەرچوون هەڵبژێرە'
                        : '${expiry!.year}/${expiry!.month}/${expiry!.day}',
                  ),
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: expiry ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (date != null) {
                      refresh(() {
                        expiry = date;
                        formError = null;
                      });
                    }
                  },
                ),
                if (_mobileFeatures)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.document_scanner_outlined),
                    label: const Text('خوێندنەوەی بەروار بە کامێرا'),
                    onPressed: () async {
                      final scanned = await Navigator.of(context)
                          .push<DateTime>(
                            MaterialPageRoute(
                              builder: (_) => const ExpiryDateScanner(),
                            ),
                          );
                      if (scanned != null && dialogContext.mounted) {
                        refresh(() {
                          expiry = scanned;
                          formError = null;
                        });
                      }
                    },
                  ),
                TextField(
                  controller: batch,
                  decoration: const InputDecoration(
                    labelText: 'ژمارەی بەچ (ئارەزوومەندانە)',
                  ),
                ),
                if (formError != null)
                  Text(
                    formError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const SizedBox(height: 8),
                const Text('هاتووی کۆن دەمێنێتەوە تا بە دەستی خۆت دایبخەیت.'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('پاشگەزبوونەوە'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (product == null || expiry == null) {
                        refresh(
                          () =>
                              formError = 'کاڵا و بەرواری بەسەرچوون دیاری بکە.',
                        );
                        return;
                      }
                      refresh(() => saving = true);
                      try {
                        await ExpiryCatalogService.addArrival(
                          adminId: auth.adminId,
                          actorId: auth.userId,
                          productId: '${product!['id']}',
                          expires: expiry!,
                          batchCode: batch.text,
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } catch (error) {
                        if (!dialogContext.mounted) return;
                        refresh(() {
                          saving = false;
                          formError = AppHelpers.backendErrorMessage(
                            error,
                            fallback: 'بەروارەکە پاشەکەوت نەکرا.',
                          );
                        });
                      }
                    },
              child: const Text('پاشەکەوت'),
            ),
          ],
        ),
      ),
    );
    lookup.dispose();
    batch.dispose();
    if (saved == true) await _load();
  }

  Future<void> _import() async {
    var completed = 0;
    var total = 0;
    try {
      final preview = await ExpiryCatalogService.pickFile();
      if (preview == null || !mounted) return;
      final suggested = preview.suggestedColumns();
      int code = suggested.code;
      int name = suggested.name;
      int? barcode = suggested.barcode;
      int? category = suggested.category;
      String? issue;
      final shouldImport = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, refresh) {
            Widget column(
              String title,
              int? value,
              ValueChanged<int?> changed, {
              bool optional = false,
            }) => DropdownButtonFormField<int>(
              initialValue: value,
              decoration: InputDecoration(labelText: title),
              items: [
                if (optional) const DropdownMenuItem<int>(child: Text('نییە')),
                ...List.generate(
                  preview.headers.length,
                  (i) => DropdownMenuItem(
                    value: i,
                    child: Text(
                      preview.headers[i],
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: changed,
            );
            return AlertDialog(
              title: const Text('پێشبینینی هاوردەکردنی کاڵا'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${preview.filename} · ${preview.rows.length} کاڵا'),
                    const Text(
                      'تەنها ناو و ناسنامەی کاڵا؛ بەروار و بڕی هاتووەکان ناگۆڕدرێن.',
                    ),
                    column(
                      'کۆدی کاڵا',
                      code,
                      (v) => refresh(() => code = v ?? 0),
                    ),
                    column(
                      'ناوی کاڵا',
                      name,
                      (v) => refresh(() => name = v ?? 0),
                    ),
                    column(
                      'بارکۆد',
                      barcode,
                      (v) => refresh(() => barcode = v),
                      optional: true,
                    ),
                    column(
                      'جۆر',
                      category,
                      (v) => refresh(() => category = v),
                      optional: true,
                    ),
                    if (preview.rows.isNotEmpty)
                      Text('نموونە: ${preview.rows.first.take(4).join(' · ')}'),
                    if (issue != null)
                      Text(
                        issue!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('پاشگەزبوونەوە'),
                ),
                FilledButton(
                  onPressed: () {
                    try {
                      preview.products(
                        codeColumn: code,
                        nameColumn: name,
                        barcodeColumn: barcode,
                        categoryColumn: category,
                      );
                      Navigator.pop(dialogContext, true);
                    } catch (error) {
                      refresh(
                        () => issue = error.toString().replaceFirst(
                          'FormatException: ',
                          '',
                        ),
                      );
                    }
                  },
                  child: const Text('هاوردەکردن'),
                ),
              ],
            );
          },
        ),
      );
      if (shouldImport != true || !mounted) return;
      final rows = preview.products(
        codeColumn: code,
        nameColumn: name,
        barcodeColumn: barcode,
        categoryColumn: category,
      );
      total = rows.length;
      setState(() {
        _loading = true;
        _importCompleted = 0;
        _importTotal = total;
      });
      final count = await ExpiryCatalogService.importProducts(
        rows,
        onProgress: (done, _) {
          completed = done;
          if (mounted) setState(() => _importCompleted = done);
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${count['inserted']} کاڵای نوێ · ${count['updated']} کاڵا نوێکرایەوە',
          ),
        ),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _importCompleted = null;
        _importTotal = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${completed > 0 ? '$completed لە $total کاڵا پاشەکەوت کرا. دووبارە هەمان فایل هاوردە بکە بۆ تەواوکردنی. ' : ''}'
            '${error is FormatException ? error.message : AppHelpers.backendErrorMessage(error, fallback: 'هاوردەکردنی فایل سەرکەوتوو نەبوو.')}',
          ),
        ),
      );
    }
  }

  Future<void> _resolve(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('داخستنی بەرواری کۆن'),
        content: const Text(
          'تەنها کاتێک دایبخە کە دڵنیایت ئەو کاڵایەی بەو بەروارەوە لە مارکێت نەماوە.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('پاشگەزبوونەوە'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('داخستن'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ExpiryCatalogService.resolve('${item['id']}');
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppHelpers.backendErrorMessage(
              error,
              fallback: 'داخستنی بەروار سەرکەوتوو نەبوو.',
            ),
          ),
        ),
      );
    }
  }

  void _details(Map<String, dynamic> product) {
    final arrivals = _forProduct('${product['id']}');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${product['name']}',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (arrivals.isEmpty)
                      const ListTile(
                        title: Text('هێشتا بەرواری هاتوو تۆمار نەکراوە.'),
                      ),
                    ...arrivals.map((a) {
                      final days = _days(a['expiry_date']);
                      final resolved = a['resolved_at'] != null;
                      return ListTile(
                        leading: Icon(
                          resolved
                              ? Icons.check_circle_outline
                              : days != null && days < 0
                              ? Icons.warning_amber
                              : Icons.event,
                        ),
                        title: Text('بەسەرچوون: ${a['expiry_date']}'),
                        subtitle: Text(
                          resolved
                              ? 'داخراوە'
                              : days == null
                              ? 'بەروار نەزانراوە'
                              : days < 0
                              ? 'بەسەرچووە'
                              : '$days ڕۆژ ماوە'
                                    '${'${a['batch_code'] ?? ''}'.isEmpty ? '' : ' · بەچ: ${a['batch_code']}'}',
                        ),
                        trailing: widget.canManage && !resolved
                            ? TextButton(
                                onPressed: () async {
                                  Navigator.pop(sheetContext);
                                  await _resolve(a);
                                },
                                child: const Text('داخستن'),
                              )
                            : null,
                      );
                    }),
                  ],
                ),
              ),
              if (widget.canManage)
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _addArrival(product);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('بەرواری هاتووی نوێ'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    int urgent = 0, expired = 0;
    for (final item in _arrivals) {
      if (item['resolved_at'] != null) continue;
      final days = _days(item['expiry_date']);
      if (days == null) continue;
      if (days < 0) {
        expired++;
      } else if (days <= 30) {
        urgent++;
      }
    }
    final items = _products.where((p) {
      final name = '${p['name'] ?? ''}'.toLowerCase();
      final code = '${p['external_code'] ?? ''}'.toLowerCase();
      final barcode = '${p['barcode'] ?? ''}'.toLowerCase();
      if (query.isNotEmpty &&
          !name.contains(query) &&
          !code.contains(query) &&
          !barcode.contains(query)) {
        return false;
      }
      final dates = _forProduct('${p['id']}', includeResolved: false);
      if (_filter == 'expired') {
        return dates.any((a) => (_days(a['expiry_date']) ?? 9999) < 0);
      }
      if (_filter == 'soon') {
        return dates.any((a) {
          final days = _days(a['expiry_date']);
          return days != null && days >= 0 && days <= 30;
        });
      }
      if (_filter == 'unrecorded') return dates.isEmpty;
      return true;
    }).toList();
    // The most urgent open expiry is shown first, even if the product was
    // imported later than the rest of the catalogue.
    final nearest = <String, int>{};
    for (final arrival in _arrivals) {
      if (arrival['resolved_at'] != null) continue;
      final id = '${arrival['product_id']}';
      final days = _day(arrival['expiry_date'])?.difference(todayOnly).inDays;
      if (days != null && days < (nearest[id] ?? 999999)) nearest[id] = days;
    }
    items.sort(
      (a, b) => (nearest['${a['id']}'] ?? 999999).compareTo(
        nearest['${b['id']}'] ?? 999999,
      ),
    );
    final header = <Widget>[
      Text(
        'بەسەرچوو: $expired · نزیکە: $urgent · کاڵا: ${_products.length}',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      const Text(
        'ئەم بەشە تەنها بەروار چاودێری دەکات؛ بڕ و فرۆشتن حساب ناکات.',
      ),
      if (_mobileFeatures)
        SwitchListTile.adaptive(
          title: const Text('ئاگادارکردنەوەی بەسەرچوونی کاڵا'),
          subtitle: Text(
            _remindersEnabled
                ? '٣٠، ٧ و ١ ڕۆژ پێش بەسەرچوون · $_scheduledDays بیرخستنەوە دابنراوە'
                : '٣٠، ٧ و ١ ڕۆژ پێش بەسەرچوون',
          ),
          value: _remindersEnabled,
          onChanged: _remindersBusy ? null : _toggleReminders,
        ),
      TextField(
        controller: _search,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          hintText: 'گەڕان بە ناو، کۆد یان بارکۆد',
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        children: [
          for (final entry in {
            'active': 'هەموو',
            'expired': 'بەسەرچوو',
            'soon': '٣٠ ڕۆژ',
            'unrecorded': 'بەروار نییە',
          }.entries)
            ChoiceChip(
              label: Text(entry.value),
              selected: _filter == entry.key,
              onSelected: (_) => setState(() => _filter = entry.key),
            ),
        ],
      ),
      const SizedBox(height: 8),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('چاودێری کاڵا'),
        actions: [
          IconButton(
            onPressed: _load,
            tooltip: 'نوێکردنەوە',
            icon: const Icon(Icons.refresh),
          ),
          if (widget.canManage)
            IconButton(
              onPressed: _importTotal == null ? _import : null,
              tooltip: 'هاوردەکردنی CSV / XLSX',
              icon: const Icon(Icons.upload_file),
            ),
        ],
      ),
      floatingActionButton: widget.canManage
          ? FloatingActionButton.extended(
              onPressed: () => _addArrival(),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('هاتووی نوێ'),
            )
          : null,
      body: _loading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_importTotal case final total?) ...[
                    Text('هاوردەکردن: ${_importCompleted ?? 0} / $total کاڵا'),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: 220,
                      child: LinearProgressIndicator(
                        value: total == 0
                            ? null
                            : (_importCompleted ?? 0) / total,
                      ),
                    ),
                  ] else
                    const CircularProgressIndicator(),
                ],
              ),
            )
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  TextButton(
                    onPressed: _load,
                    child: const Text('دووبارە هەوڵ بدە'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: header.length + (_products.isEmpty ? 1 : items.length),
              itemBuilder: (context, index) {
                if (index < header.length) return header[index];
                if (_products.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'فایلی کاڵاکانی کاشێر هاوردە بکە بۆ دەستپێکردن.',
                      ),
                    ),
                  );
                }
                final product = items[index - header.length];
                return Card(
                  child: ListTile(
                    title: Text('${product['name']}'),
                    subtitle: Text(() {
                      final dates = _forProduct(
                        '${product['id']}',
                        includeResolved: false,
                      );
                      if (dates.isEmpty) return 'هێشتا بەروار تۆمار نەکراوە';
                      final next = dates.first;
                      final days = _days(next['expiry_date']);
                      return 'نزیکترین بەروار: ${next['expiry_date']}'
                          '${days == null
                              ? ''
                              : days < 0
                              ? ' · بەسەرچووە'
                              : ' · $days ڕۆژ ماوە'}';
                    }()),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => _details(product),
                  ),
                );
              },
            ),
    );
  }
}
