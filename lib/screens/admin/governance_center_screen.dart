// ignore_for_file: prefer_interpolation_to_compose_strings, unnecessary_underscores

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/helpers.dart';

class GovernanceCenterScreen extends StatefulWidget {
  const GovernanceCenterScreen({super.key});
  @override
  State<GovernanceCenterScreen> createState() => _GovernanceCenterScreenState();
}

class _GovernanceCenterScreenState extends State<GovernanceCenterScreen>
    with SingleTickerProviderStateMixin {
  late final TabController tabs;
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> employees = [];
  List<Map<String, dynamic>> logs = [];
  List<Map<String, dynamic>> backups = [];
  final auditSearch = TextEditingController();
  String? auditActor;
  DateTime? auditFrom;
  DateTime? auditTo;
  bool auditHasMore = false;
  bool auditLoading = false;
  static const auditPageSize = 100;

  @override
  void initState() {
    super.initState();
    tabs = TabController(length: 3, vsync: this);
    load();
  }

  @override
  void dispose() {
    auditSearch.dispose();
    tabs.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> rows(dynamic value) => (value as List)
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();

  Future<void> load() async {
    if (mounted) setState(() { loading = true; error = null; });
    try {
      await PBService.ensureInitialized();
      final client = PBService.client;
      final uid = client.auth.currentUser!.id;
      final result = await Future.wait([
        client.from('profiles').select(
          'id,name,phone,active,employee_permissions!employee_permissions_employee_id_fkey(*)',
        ).eq('role', 'employee').eq('admin_id', uid).order('name'),
        client.from('tenant_backups').select(
          'id,label,backup_type,record_counts,created_at,expires_at',
        ).order('created_at', ascending: false).limit(50),
      ]);
      if (!mounted) return;
      setState(() {
        employees = rows(result[0]);
        backups = rows(result[1]);
      });
      await loadAudit(reset: true);
    } catch (e) {
      if (mounted) {
        setState(() => error = AppHelpers.backendErrorMessage(
          e,
          fallback: 'نەتوانرا زانیارییەکان بهێنرێن. دووبارە هەوڵ بدە.',
        ));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> loadAudit({bool reset = false}) async {
    if (auditLoading) return;
    setState(() => auditLoading = true);
    try {
      final start = reset ? 0 : logs.length;
      var query = PBService.client.from('audit_logs').select(
        'id,actor_id,action,entity_type,entity_id,changed_fields,occurred_at',
      );
      if (auditActor != null) query = query.eq('actor_id', auditActor!);
      if (auditFrom != null) {
        query = query.gte('occurred_at', auditFrom!.toUtc().toIso8601String());
      }
      if (auditTo != null) {
        final end = DateTime(auditTo!.year, auditTo!.month, auditTo!.day + 1);
        query = query.lt('occurred_at', end.toUtc().toIso8601String());
      }
      final term = auditSearch.text.trim();
      if (term.isNotEmpty) {
        final safe = term.replaceAll(RegExp(r'[,()]'), '');
        query = query.or('entity_id.ilike.%$safe%,action.ilike.%$safe%,entity_type.ilike.%$safe%');
      }
      final page = rows(await query.order('occurred_at', ascending: false)
          .range(start, start + auditPageSize - 1));
      if (!mounted) return;
      setState(() {
        logs = reset ? page : [...logs, ...page];
        auditHasMore = page.length == auditPageSize;
      });
    } catch (e) {
      if (mounted) {
        toast(AppHelpers.backendErrorMessage(e,
            fallback: 'گەڕان لە تۆماری چاودێری سەرکەوتوو نەبوو.'), bad: true);
      }
    } finally {
      if (mounted) setState(() => auditLoading = false);
    }
  }

  Future<void> pickAuditDate({required bool from}) async {
    final date = await showDatePicker(
      context: context,
      initialDate: (from ? auditFrom : auditTo) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null) return;
    setState(() { if (from) { auditFrom = date; } else { auditTo = date; } });
    await loadAudit(reset: true);
  }

  Future<void> exportAuditCsv() async {
    try {
      final all = <Map<String, dynamic>>[];
      const chunkSize = 500;
      for (var offset = 0; ; offset += chunkSize) {
        var query = PBService.client.from('audit_logs').select(
          'actor_id,action,entity_type,entity_id,occurred_at',
        );
        if (auditActor != null) query = query.eq('actor_id', auditActor!);
        if (auditFrom != null) query = query.gte('occurred_at', auditFrom!.toUtc().toIso8601String());
        if (auditTo != null) {
          final end = DateTime(auditTo!.year, auditTo!.month, auditTo!.day + 1);
          query = query.lt('occurred_at', end.toUtc().toIso8601String());
        }
        final safe = auditSearch.text.trim().replaceAll(RegExp(r'[,()]'), '');
        if (safe.isNotEmpty) {
          query = query.or(
            'entity_id.ilike.%$safe%,action.ilike.%$safe%,entity_type.ilike.%$safe%',
          );
        }
        final page = rows(await query.order('occurred_at', ascending: false)
            .range(offset, offset + chunkSize - 1));
        all.addAll(page);
        if (page.length < chunkSize) break;
      }
      String csv(dynamic value) => '"${(value ?? '').toString().replaceAll('"', '""')}"';
      final content = StringBuffer('\uFEFFبەروار,کاربەر,کردار,جۆر,ناسنامە\n');
      for (final row in all) {
        content.writeln([
          row['occurred_at'], row['actor_id'], row['action'],
          row['entity_type'], row['entity_id'],
        ].map(csv).join(','));
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/zhirox-audit-${DateTime.now().millisecondsSinceEpoch}.csv');
      await file.writeAsString(content.toString());
      await Share.shareXFiles([XFile(file.path)]);
    } catch (e) {
      if (mounted) {
        toast(AppHelpers.backendErrorMessage(e,
            fallback: 'هەناردەکردنی تۆماری چاودێری سەرکەوتوو نەبوو.'), bad: true);
      }
    }
  }

  Map<String, dynamic> permissionOf(Map<String, dynamic> employee) {
    final raw = employee['employee_permissions'];
    if (raw is List && raw.isNotEmpty && raw.first is Map) {
      return Map<String, dynamic>.from(raw.first as Map);
    }
    return {};
  }

  Future<void> editPermissions(Map<String, dynamic> employee) async {
    final value = await showDialog<Map<String, bool>>(
      context: context,
      builder: (_) => PermissionDialog(
        employeeName: (employee['name'] ?? 'کارمەند').toString(),
        initial: permissionOf(employee),
      ),
    );
    if (value == null) return;
    try {
      await PBService.client.rpc(
        'set_employee_permissions_v2',
        params: {
          'p_employee_id': employee['id'],
          'p_permissions': value,
        },
      );
      toast('هەموو دەسەڵاتەکان پاشەکەوت کران');
      await load();
    } catch (e) {
      toast(AppHelpers.backendErrorMessage(
        e,
        fallback: 'دەسەڵاتەکان پاشەکەوت نەکران. دووبارە هەوڵ بدە.',
      ), bad: true);
    }
  }

  Future<void> createBackup() async {
    try {
      await PBService.client.rpc('create_tenant_backup', params: {
        'p_label': 'Manual backup ' + DateTime.now().toIso8601String(),
        'p_type': 'manual',
      });
      toast('Backup درووست کرا');
      await load();
    } catch (e) {
      toast(AppHelpers.backendErrorMessage(
        e,
        fallback: 'Backup درووست نەکرا. دووبارە هەوڵ بدە.',
      ), bad: true);
    }
  }

  Future<void> restoreBackup(Map<String, dynamic> backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('گەڕاندنەوەی Backup'),
        content: const Text(
          'پێش Restoreکردن Backupێکی پاراستن بە خۆکاری درووست دەکرێت. دڵنیایت؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('نەخێر'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await PBService.client.rpc(
        'restore_tenant_backup',
        params: {'p_backup_id': backup['id']},
      );
      toast('داتا بە سەرکەوتوویی گەڕێندرایەوە');
      await load();
    } catch (e) {
      toast(AppHelpers.backendErrorMessage(
        e,
        fallback: 'Restore سەرکەوتوو نەبوو. دووبارە هەوڵ بدە.',
      ), bad: true);
    }
  }

  Future<void> exportCsv() async {
    try {
      final raw = await PBService.client.rpc('get_tenant_export');
      final data = Map<String, dynamic>.from(raw as Map);
      final output = StringBuffer();
      output.writeln('type,id,name,phone,amount,remaining,status,created_at');
      String safe(dynamic v) =>
          '"' + (v ?? '').toString().replaceAll('"', '""') + '"';
      for (final item in (data['profiles'] as List? ?? [])) {
        final x = Map<String, dynamic>.from(item as Map);
        output.writeln(['profile',x['id'],x['name'],x['phone'],'','',x['role'],x['created_at']].map(safe).join(','));
      }
      for (final item in (data['debts'] as List? ?? [])) {
        final x = Map<String, dynamic>.from(item as Map);
        output.writeln(['debt',x['id'],'','','',x['amount'],x['remaining'],x['status'],x['created_at']].map(safe).join(','));
      }
      for (final item in (data['payments'] as List? ?? [])) {
        final x = Map<String, dynamic>.from(item as Map);
        output.writeln(['payment',x['id'],'','',x['amount'],'','',x['created_at']].map(safe).join(','));
      }
      final dir = await getTemporaryDirectory();
      final file = File(dir.path + '/zhirox-export.csv');
      await file.writeAsString('\uFEFF' + output.toString(), flush: true);
      await Share.shareXFiles([XFile(file.path, mimeType: 'text/csv')]);
    } catch (e) {
      toast(AppHelpers.backendErrorMessage(
        e,
        fallback: 'Export سەرکەوتوو نەبوو. دووبارە هەوڵ بدە.',
      ), bad: true);
    }
  }

  Future<void> exportJson() async {
    try {
      final raw = await PBService.client.rpc('get_tenant_export');
      final dir = await getTemporaryDirectory();
      final file = File(dir.path + '/zhirox-backup.json');
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(raw), flush: true);
      await Share.shareXFiles([XFile(file.path, mimeType: 'application/json')]);
    } catch (e) {
      toast(AppHelpers.backendErrorMessage(
        e,
        fallback: 'Export سەرکەوتوو نەبوو. دووبارە هەوڵ بدە.',
      ), bad: true);
    }
  }

  void toast(String value, {bool bad = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(value),
      backgroundColor: bad ? Colors.red : Colors.green,
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('بەڕێوەبردن و پاراستن'),
      actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))],
      bottom: TabBar(controller: tabs, tabs: const [
        Tab(icon: Icon(Icons.admin_panel_settings_outlined), text: 'دەسەڵات'),
        Tab(icon: Icon(Icons.history_rounded), text: 'Audit'),
        Tab(icon: Icon(Icons.backup_outlined), text: 'Backup'),
      ]),
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
            ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(error!)))
            : TabBarView(controller: tabs, children: [
                permissionsTab(),
                auditTab(),
                backupTab(),
              ]),
  );

  Widget permissionsTab() => RefreshIndicator(
    onRefresh: load,
    child: ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: employees.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final employee = employees[i];
        final enabled = PermissionDialog.permissionKeys
            .where((key) => permissionOf(employee)[key] == true)
            .length;
        return Card(child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.badge_outlined)),
          title: Text((employee['name'] ?? 'کارمەند').toString()),
          subtitle: Text((employee['phone'] ?? '').toString() + ' • ' + enabled.toString() + '/60 دەسەڵات'),
          trailing: const Icon(Icons.tune_rounded),
          onTap: () => editPermissions(employee),
        ));
      },
    ),
  );

  Widget auditTab() => RefreshIndicator(
    onRefresh: () => loadAudit(reset: true),
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: auditSearch,
          decoration: const InputDecoration(labelText: 'گەڕان بە کردار یان ناسنامە', prefixIcon: Icon(Icons.search)),
          onSubmitted: (_) => loadAudit(reset: true),
        ),
        DropdownButton<String?>(
          value: auditActor,
          isExpanded: true,
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('هەموو کاربەران')),
            for (final person in employees)
              DropdownMenuItem<String?>(value: person['id'].toString(), child: Text((person['name'] ?? person['id']).toString())),
          ],
          onChanged: (value) { setState(() => auditActor = value); loadAudit(reset: true); },
        ),
        Wrap(spacing: 8, children: [
          TextButton.icon(
            onPressed: () => pickAuditDate(from: true),
            icon: const Icon(Icons.date_range),
            label: Text(auditFrom == null ? 'لە بەروار' : '${auditFrom!.year}/${auditFrom!.month}/${auditFrom!.day}'),
          ),
          TextButton.icon(
            onPressed: () => pickAuditDate(from: false),
            icon: const Icon(Icons.date_range),
            label: Text(auditTo == null ? 'تا بەروار' : '${auditTo!.year}/${auditTo!.month}/${auditTo!.day}'),
          ),
          TextButton(
            onPressed: () { setState(() { auditFrom = null; auditTo = null; auditActor = null; auditSearch.clear(); }); loadAudit(reset: true); },
            child: const Text('پاککردنەوەی پاڵاوتن'),
          ),
          TextButton.icon(
            onPressed: exportAuditCsv,
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('هەناردەکردنی CSV'),
          ),
        ]),
        for (var i = 0; i < logs.length; i++) ...[
          if (i > 0) const Divider(),
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.history, size: 18)),
            title: Text(actionName((logs[i]['action'] ?? '').toString()) + ' • ' + (logs[i]['entity_type'] ?? '').toString()),
            subtitle: Text('ناسنامە: ' + (logs[i]['entity_id'] ?? '').toString() + '\n' + (logs[i]['occurred_at'] ?? '').toString()),
            isThreeLine: true,
          ),
        ],
        if (auditHasMore) TextButton(
          onPressed: auditLoading ? null : () => loadAudit(),
          child: const Text('زیاتر پیشان بدە'),
        ),
        if (auditLoading) const Center(child: CircularProgressIndicator()),
      ],
    ),
  );

  Widget backupTab() => RefreshIndicator(
    onRefresh: load,
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton.icon(
          onPressed: createBackup,
          icon: const Icon(Icons.backup),
          label: const Text('Backupی نوێ درووست بکە'),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: exportCsv,
            icon: const Icon(Icons.table_view),
            label: const Text('Excel / CSV'),
          )),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(
            onPressed: exportJson,
            icon: const Icon(Icons.data_object),
            label: const Text('JSON'),
          )),
        ]),
        const SizedBox(height: 18),
        const Text('Backup ـەکان', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        const SizedBox(height: 8),
        ...backups.map((backup) => Card(child: ListTile(
          leading: const Icon(Icons.cloud_done_outlined),
          title: Text((backup['label'] ?? 'Backup').toString()),
          subtitle: Text((backup['created_at'] ?? '').toString() + '\n' + (backup['record_counts'] ?? {}).toString()),
          isThreeLine: true,
          trailing: IconButton(
            tooltip: 'Restore',
            icon: const Icon(Icons.restore_rounded),
            onPressed: () => restoreBackup(backup),
          ),
        ))),
      ],
    ),
  );

  String actionName(String value) => const {
    'insert': 'زیادکردن',
    'update': 'دەستکاری',
    'delete': 'سڕینەوە',
    'restore': 'گەڕاندنەوە',
    'permission_change': 'گۆڕینی دەسەڵات',
    'backup': 'Backup',
    'backup_restore': 'Restore',
  }[value] ?? value;
}

class PermissionDialog extends StatefulWidget {
  const PermissionDialog({super.key, required this.employeeName, required this.initial});
  final String employeeName;
  final Map<String, dynamic> initial;

  static const groups = <_PermissionGroup>[
    _PermissionGroup('کڕیار', Icons.people_outline_rounded, {
      'can_view_customers': 'بینینی کڕیارەکان',
      'can_add_customers': 'زیادکردنی کڕیار',
      'can_edit_customers': 'دەستکاریکردنی کڕیار',
      'can_delete_customers': 'سڕینەوەی کڕیار',
      'can_approve_customers': 'پەسەندکردنی کڕیار',
      'can_manage_customer_links': 'بەڕێوەبردنی لینکی کڕیار',
      'can_pin_customers': 'Pin کردنی کڕیار',
      'can_manage_vip_customers': 'بەڕێوەبردنی کڕیاری VIP',
      'can_merge_customer_identities': 'یەکخستنی ناسنامەی کڕیار',
      'can_view_customer_phone': 'بینینی ژمارەی مۆبایلی کڕیار',
      'can_view_customer_notes': 'بینینی تێبینی کڕیار',
      'can_edit_customer_notes': 'دەستکاریکردنی تێبینی کڕیار',
      'can_view_customer_balances': 'بینینی باڵانسی کڕیار',
    }),
    _PermissionGroup('قەرز و پارەدانەوە', Icons.account_balance_wallet_outlined, {
      'can_view_debts': 'بینینی قەرزەکان',
      'can_add_debts': 'زیادکردنی قەرز',
      'can_edit_debts': 'دەستکاریکردنی قەرز',
      'can_delete_debts': 'سڕینەوەی قەرز',
      'can_set_debt_limit': 'دانانی سنووری قەرز',
      'can_set_due_date': 'دانانی بەرواری دانەوە',
      'can_restore_debts': 'گەڕاندنەوەی قەرزی سڕاوە',
      'can_record_payments': 'تۆمارکردنی پارەدانەوە',
      'can_view_payment_history': 'بینینی مێژووی پارەدانەوە',
      'can_edit_payments': 'دەستکاریکردنی پارەدانەوە',
      'can_delete_payments': 'سڕینەوەی پارەدانەوە',
      'can_refund_payments': 'گەڕاندنەوەی پارەدانەوە',
      'can_manage_collections': 'بەڕێوەبردنی بەدواداچوونی قەرز',
    }),
    _PermissionGroup('پسووڵە و ڕاپۆرت', Icons.receipt_long_outlined, {
      'can_manage_receipts': 'بەڕێوەبردنی پسووڵە',
      'can_create_receipts': 'دروستکردنی پسووڵە',
      'can_edit_receipts': 'دەستکاریکردنی پسووڵە',
      'can_delete_receipts': 'سڕینەوەی پسووڵە',
      'can_export_receipts': 'هەناردەکردنی پسووڵە',
      'can_create_statements': 'دروستکردنی کەشفی حیساب',
      'can_view_financial_reports': 'بینینی ڕاپۆرتی دارایی',
      'can_view_report_summary': 'بینینی پوختەی ڕاپۆرت',
      'can_export_reports': 'هەناردەکردنی ڕاپۆرت',
      'can_export_data': 'هەناردەکردنی داتا',
      'can_import_data': 'هاوردەکردنی داتا',
    }),
    _PermissionGroup('داشبۆرد و زیرەکی', Icons.dashboard_outlined, {
      'can_view_dashboard': 'بینینی داشبۆرد',
      'can_view_recent_activity': 'بینینی چالاکییە نوێکان',
      'can_view_transactions': 'بینینی هەموو مامەڵەکان',
      'can_view_market_rates': 'بینینی نرخی بازاڕ',
      'can_manage_market_rate_refresh': 'نوێکردنەوەی نرخی بازاڕ',
      'can_view_intelligence': 'بینینی ناوەندی زیرەکی',
      'can_view_expiry': 'بینینی چاودێری بەرواری کاڵا',
      'can_manage_expiry': 'بەڕێوەبردنی کاڵای بەسەرچوو',
    }),
    _PermissionGroup('ئاگادارکردنەوە و Sync', Icons.sync_outlined, {
      'can_send_notifications': 'ناردنی ئاگادارکردنەوە',
      'can_manage_notifications': 'بەڕێوەبردنی ئاگادارکردنەوە',
      'can_manage_notification_templates': 'بەڕێوەبردنی قالبی ئاگادارکردنەوە',
      'can_send_bulk_notifications': 'ناردنی ئاگادارکردنەوەی کۆمەڵەیی',
      'can_manage_daftar_sync': 'بەڕێوەبردنی Daftar Sync',
      'can_view_sync_logs': 'بینینی لۆگی Sync',
      'can_retry_failed_sync': 'دووبارەکردنەوەی Sync ـی شکستخواردوو',
    }),
    _PermissionGroup('بەڕێوەبردن و پاراستن', Icons.security_outlined, {
      'can_manage_employees': 'بەڕێوەبردنی کارمەندان',
      'can_view_audit_log': 'بینینی Audit Log',
      'can_manage_backup': 'بەڕێوەبردنی Backup',
      'can_run_manual_backup': 'دروستکردنی Backup ـی دەستی',
      'can_restore_backup': 'گەڕاندنەوە لە Backup',
      'can_manage_subscription': 'بەڕێوەبردنی بەشداری',
      'can_manage_settings': 'بەڕێوەبردنی ڕێکخستنەکان',
      'can_manage_security_settings': 'ڕێکخستنی پاراستن و ئاسایش',
    }),
  ];

  static const permissionKeys = <String>[
    'can_view_customers', 'can_add_customers', 'can_edit_customers',
    'can_delete_customers', 'can_approve_customers', 'can_manage_customer_links',
    'can_pin_customers', 'can_manage_vip_customers', 'can_merge_customer_identities',
    'can_view_customer_phone', 'can_view_customer_notes', 'can_edit_customer_notes',
    'can_view_customer_balances', 'can_view_debts', 'can_add_debts',
    'can_edit_debts', 'can_delete_debts', 'can_set_debt_limit', 'can_set_due_date',
    'can_restore_debts', 'can_record_payments', 'can_view_payment_history',
    'can_edit_payments', 'can_delete_payments', 'can_refund_payments',
    'can_manage_collections', 'can_manage_receipts', 'can_create_receipts',
    'can_edit_receipts', 'can_delete_receipts', 'can_export_receipts',
    'can_create_statements', 'can_view_financial_reports', 'can_view_report_summary',
    'can_export_reports', 'can_export_data', 'can_import_data', 'can_view_dashboard',
    'can_view_recent_activity', 'can_view_transactions', 'can_view_market_rates',
    'can_manage_market_rate_refresh', 'can_view_intelligence', 'can_view_expiry',
    'can_manage_expiry', 'can_send_notifications', 'can_manage_notifications',
    'can_manage_notification_templates', 'can_send_bulk_notifications',
    'can_manage_daftar_sync', 'can_view_sync_logs', 'can_retry_failed_sync',
    'can_manage_employees', 'can_view_audit_log', 'can_manage_backup',
    'can_run_manual_backup', 'can_restore_backup', 'can_manage_subscription',
    'can_manage_settings', 'can_manage_security_settings',
  ];

  @override
  State<PermissionDialog> createState() => _PermissionDialogState();
}

class _PermissionGroup {
  const _PermissionGroup(this.title, this.icon, this.permissions);
  final String title;
  final IconData icon;
  final Map<String, String> permissions;
}

class _PermissionDialogState extends State<PermissionDialog> {
  late final Map<String, bool> values;

  @override
  void initState() {
    super.initState();
    values = {
      for (final key in PermissionDialog.permissionKeys)
        key: widget.initial[key] == true,
    };
  }

  int get enabledCount => values.values.where((value) => value).length;

  void setAll(bool enabled) {
    setState(() {
      for (final key in values.keys) {
        values[key] = enabled;
      }
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
    contentPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
    title: Row(
      children: [
        const Icon(Icons.admin_panel_settings_outlined),
        const SizedBox(width: 8),
        Expanded(child: Text('دەسەڵاتی ' + widget.employeeName)),
        Text(
          '$enabledCount/60',
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ],
    ),
    content: SizedBox(
      width: double.maxFinite,
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => setAll(true),
                    icon: const Icon(Icons.done_all_rounded, size: 18),
                    label: const Text('هەمووی چالاک بکە'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => setAll(false),
                    icon: const Icon(Icons.block_outlined, size: 18),
                    label: const Text('هەمووی داخە'),
                  ),
                ),
              ],
            ),
          ),
          for (final group in PermissionDialog.groups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
              child: Row(
                children: [
                  Icon(group.icon, size: 18),
                  const SizedBox(width: 7),
                  Text(
                    group.title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var index = 0;
                      index < group.permissions.length;
                      index++) ...[
                    SwitchListTile(
                      dense: true,
                      value: values[group.permissions.keys.elementAt(index)] ?? false,
                      title: Text(group.permissions.values.elementAt(index)),
                      onChanged: (value) => setState(
                        () => values[group.permissions.keys.elementAt(index)] = value,
                      ),
                    ),
                    if (index < group.permissions.length - 1)
                      const Divider(height: 1),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('پاشگەزبوونەوە'),
      ),
      FilledButton.icon(
        onPressed: () => Navigator.pop(context, values),
        icon: const Icon(Icons.save_outlined),
        label: const Text('پاشەکەوت'),
      ),
    ],
  );
}
