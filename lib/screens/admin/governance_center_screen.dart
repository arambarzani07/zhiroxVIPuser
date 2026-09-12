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

  @override
  void initState() {
    super.initState();
    tabs = TabController(length: 3, vsync: this);
    load();
  }

  @override
  void dispose() {
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
        client.from('audit_logs').select(
          'id,actor_id,action,entity_type,entity_id,changed_fields,occurred_at',
        ).order('occurred_at', ascending: false).limit(200),
        client.from('tenant_backups').select(
          'id,label,backup_type,record_counts,created_at,expires_at',
        ).order('created_at', ascending: false).limit(50),
      ]);
      if (!mounted) return;
      setState(() {
        employees = rows(result[0]);
        logs = rows(result[1]);
        backups = rows(result[2]);
      });
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
      final uid = PBService.client.auth.currentUser!.id;
      await PBService.client.from('employee_permissions').upsert({
        'employee_id': employee['id'],
        'admin_id': uid,
        ...value,
        'updated_by': uid,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      toast('دەسەڵاتەکان پاشەکەوت کران');
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
        final enabled = permissionOf(employee).values.where((v) => v == true).length;
        return Card(child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.badge_outlined)),
          title: Text((employee['name'] ?? 'کارمەند').toString()),
          subtitle: Text((employee['phone'] ?? '').toString() + ' • ' + enabled.toString() + ' مۆڵەت'),
          trailing: const Icon(Icons.tune_rounded),
          onTap: () => editPermissions(employee),
        ));
      },
    ),
  );

  Widget auditTab() => RefreshIndicator(
    onRefresh: load,
    child: ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: logs.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (_, i) {
        final log = logs[i];
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.history, size: 18)),
          title: Text(actionName((log['action'] ?? '').toString()) + ' • ' + (log['entity_type'] ?? '').toString()),
          subtitle: Text('ID: ' + (log['entity_id'] ?? '').toString() + '\n' + (log['occurred_at'] ?? '').toString()),
          isThreeLine: true,
        );
      },
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
  @override
  State<PermissionDialog> createState() => _PermissionDialogState();
}

class _PermissionDialogState extends State<PermissionDialog> {
  static const labels = <String, String>{
    'can_view_customers': 'بینینی کڕیار',
    'can_add_customers': 'زیادکردنی کڕیار',
    'can_edit_customers': 'دەستکاری کڕیار',
    'can_delete_customers': 'سڕینەوەی کڕیار',
    'can_view_debts': 'بینینی قەرز',
    'can_add_debts': 'زیادکردنی قەرز',
    'can_edit_debts': 'دەستکاری قەرز',
    'can_delete_debts': 'سڕینەوەی قەرز',
    'can_record_payments': 'تۆمارکردنی پارەدان',
    'can_view_financial_reports': 'بینینی ڕاپۆرتی دارایی',
    'can_export_data': 'Exportکردنی داتا',
    'can_send_notifications': 'ناردنی ئاگادارکردنەوە',
  };
  late final Map<String, bool> values;

  @override
  void initState() {
    super.initState();
    values = {for (final key in labels.keys) key: widget.initial[key] == true};
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('دەسەڵاتی ' + widget.employeeName),
    content: SizedBox(
      width: double.maxFinite,
      child: ListView(
        shrinkWrap: true,
        children: labels.entries.map((entry) => SwitchListTile(
          value: values[entry.key]!,
          title: Text(entry.value),
          onChanged: (value) => setState(() => values[entry.key] = value),
        )).toList(),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('پاشگەزبوونەوە')),
      FilledButton(onPressed: () => Navigator.pop(context, values), child: const Text('پاشەکەوت')),
    ],
  );
}
