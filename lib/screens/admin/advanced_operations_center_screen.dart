import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:zhirox/screens/shared/user_profile_screen.dart';
import 'package:zhirox/services/advanced_customer_service.dart';
import 'package:zhirox/services/scheduled_report_export_service.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:zhirox/widgets/app_design.dart';

class AdvancedOperationsCenterScreen extends StatefulWidget {
  const AdvancedOperationsCenterScreen({super.key});

  @override
  State<AdvancedOperationsCenterScreen> createState() =>
      _AdvancedOperationsCenterScreenState();
}

class _AdvancedOperationsCenterScreenState
    extends State<AdvancedOperationsCenterScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _approvals = const [];
  Map<String, dynamic> _forecast = const {};
  List<Map<String, dynamic>> _anomalies = const [];
  List<Map<String, dynamic>> _employees = const [];
  Map<String, dynamic> _quality = const {};
  List<Map<String, dynamic>> _schedules = const [];
  List<Map<String, dynamic>> _reportRuns = const [];

  int _int(dynamic value) =>
      (value as num?)?.toInt() ?? int.tryParse('${value ?? 0}') ?? 0;
  double _double(dynamic value) =>
      (value as num?)?.toDouble() ?? double.tryParse('${value ?? 0}') ?? 0;

  String _money(dynamic value, {bool usd = false}) {
    final n = _double(value);
    final formatted = NumberFormat('#,##0.##', 'en_US').format(n);
    return usd ? '\$$formatted' : '$formatted د.ع';
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
      final values = await Future.wait<dynamic>([
        AdvancedCustomerService.getApprovalInbox(limit: 150),
        AdvancedCustomerService.getCashFlowForecast(days: 30),
        AdvancedCustomerService.getAnomalies(limit: 150),
        AdvancedCustomerService.getEmployeePerformance(days: 30),
        AdvancedCustomerService.getDataQuality(limit: 300),
        AdvancedCustomerService.getScheduledReports(),
        AdvancedCustomerService.getScheduledReportRuns(limit: 50),
      ]);
      if (!mounted) return;
      setState(() {
        _approvals = List<Map<String, dynamic>>.from(values[0] as List);
        _forecast = Map<String, dynamic>.from(values[1] as Map);
        _anomalies = List<Map<String, dynamic>>.from(values[2] as List);
        _employees = List<Map<String, dynamic>>.from(values[3] as List);
        _quality = Map<String, dynamic>.from(values[4] as Map);
        _schedules = List<Map<String, dynamic>>.from(values[5] as List);
        _reportRuns = List<Map<String, dynamic>>.from(values[6] as List);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppHelpers.backendErrorMessage(
          e,
          fallback: 'نەتوانرا ناوەندی زانیارییەکان باربکرێت.',
        );
      });
    }
  }

  List<Map<String, dynamic>> _list(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  Future<void> _decide(Map<String, dynamic> request, bool approve) async {
    final id = request['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final ok = await AppHelpers.showConfirmDialog(
      context,
      title: approve ? 'پەسەندکردن' : 'ڕەتکردنەوە',
      message: approve
          ? 'ئەم داواکاریی قەرزە پەسەند بکرێت؟'
          : 'ئەم داواکاریی قەرزە ڕەت بکرێتەوە؟',
    );
    if (!ok || !mounted) return;
    try {
      await AdvancedCustomerService.decideApproval(
        requestId: id,
        approve: approve,
      );
      if (mounted) await _load();
    } catch (e) {
      if (mounted) {
        AppHelpers.showSnackBar(
          context,
          AppHelpers.backendErrorMessage(e, fallback: 'کردارەکە سەرکەوتوو نەبوو.'),
          isError: true,
        );
      }
    }
  }

  Future<void> _addSchedule() async {
    var kind = 'daily_summary';
    var cadence = 'daily';
    var weekday = 1;
    final hour = TextEditingController(text: '8');
    final monthDay = TextEditingController(text: '1');
    final save = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, update) => AlertDialog(
          title: const Text('ڕاپۆرتی خۆکار'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: 'جۆری ڕاپۆرت'),
                  items: const [
                    DropdownMenuItem(value: 'daily_summary', child: Text('پوختەی ڕۆژانە')),
                    DropdownMenuItem(value: 'collections', child: Text('کۆکردنەوەی قەرز')),
                    DropdownMenuItem(value: 'cash_flow', child: Text('پێشبینی هاتووچۆی پارە')),
                    DropdownMenuItem(value: 'employee_performance', child: Text('کارایی کارمەند')),
                    DropdownMenuItem(value: 'data_quality', child: Text('کوالێتی داتا')),
                  ],
                  onChanged: (v) => update(() => kind = v ?? kind),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: cadence,
                  decoration: const InputDecoration(labelText: 'دووبارەبوونەوە'),
                  items: const [
                    DropdownMenuItem(value: 'daily', child: Text('ڕۆژانە')),
                    DropdownMenuItem(value: 'weekly', child: Text('هەفتانە')),
                    DropdownMenuItem(value: 'monthly', child: Text('مانگانە')),
                  ],
                  onChanged: (v) => update(() => cadence = v ?? cadence),
                ),
                const SizedBox(height: 10),
                if (cadence == 'weekly')
                  DropdownButtonFormField<int>(
                    initialValue: weekday,
                    decoration: const InputDecoration(labelText: 'ڕۆژی هەفتە'),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('دووشەممە')),
                      DropdownMenuItem(value: 2, child: Text('سێشەممە')),
                      DropdownMenuItem(value: 3, child: Text('چوارشەممە')),
                      DropdownMenuItem(value: 4, child: Text('پێنجشەممە')),
                      DropdownMenuItem(value: 5, child: Text('هەینی')),
                      DropdownMenuItem(value: 6, child: Text('شەممە')),
                      DropdownMenuItem(value: 7, child: Text('یەکشەممە')),
                    ],
                    onChanged: (v) => update(() => weekday = v ?? weekday),
                  ),
                if (cadence == 'monthly')
                  TextField(
                    controller: monthDay,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'ڕۆژی مانگ 1–28',
                    ),
                  ),
                if (cadence != 'daily') const SizedBox(height: 10),
                TextField(
                  controller: hour,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'کاتژمێر 0–23'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('پاشگەزبوونەوە'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('پاشەکەوت'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      await AdvancedCustomerService.saveScheduledReport(
        reportKind: kind,
        cadence: cadence,
        runHour: (int.tryParse(hour.text) ?? 8).clamp(0, 23).toInt(),
        weekday: cadence == 'weekly' ? weekday : null,
        monthDay: cadence == 'monthly'
            ? (int.tryParse(monthDay.text) ?? 1).clamp(1, 28).toInt()
            : null,
      );
      if (mounted) await _load();
    }
    hour.dispose();
    monthDay.dispose();
  }

  String _weekdayLabel(int weekday) {
    return switch (weekday) {
      1 => 'دووشەممە',
      2 => 'سێشەممە',
      3 => 'چوارشەممە',
      4 => 'پێنجشەممە',
      5 => 'هەینی',
      6 => 'شەممە',
      7 => 'یەکشەممە',
      _ => '—',
    };
  }

  String _scheduleTimingLabel(Map<String, dynamic> schedule) {
    final cadence = schedule['cadence']?.toString() ?? 'daily';
    final hour = _int(schedule['run_hour']);
    if (cadence == 'weekly') {
      return 'هەفتانە • ${_weekdayLabel(_int(schedule['weekday']))} • '
          '${hour.toString().padLeft(2, '0')}:00';
    }
    if (cadence == 'monthly') {
      return 'مانگانە • ڕۆژی ${_int(schedule['month_day'])} • '
          '${hour.toString().padLeft(2, '0')}:00';
    }
    return 'ڕۆژانە • ${hour.toString().padLeft(2, '0')}:00';
  }
  List<String> _scheduleRecipients(Map<String, dynamic> schedule) {
    final raw = schedule['recipients'];
    if (raw is! List) return const <String>[];
    return raw.map((value) => value.toString()).toList(growable: false);
  }

  Future<void> _toggleSchedule(Map<String, dynamic> schedule) async {
    try {
      final id = schedule['id']?.toString() ?? '';
      if (id.isEmpty) return;
      await AdvancedCustomerService.saveScheduledReport(
        id: id,
        reportKind: schedule['report_kind']?.toString() ?? 'daily_summary',
        cadence: schedule['cadence']?.toString() ?? 'daily',
        runHour: _int(schedule['run_hour']).clamp(0, 23).toInt(),
        weekday: schedule['weekday'] == null
            ? null
            : _int(schedule['weekday']).clamp(1, 7).toInt(),
        monthDay: schedule['month_day'] == null
            ? null
            : _int(schedule['month_day']).clamp(1, 28).toInt(),
        recipients: _scheduleRecipients(schedule),
        enabled: schedule['enabled'] != true,
      );
      if (mounted) await _load();
    } catch (e) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          e,
          fallback: 'نەتوانرا دۆخی ڕاپۆرتەکە بگۆڕدرێت.',
        ),
        isError: true,
      );
    }
  }

  Future<void> _deleteSchedule(Map<String, dynamic> schedule) async {
    final id = schedule['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final ok = await AppHelpers.showConfirmDialog(
      context,
      title: 'سڕینەوەی Scheduled Report',
      message: 'دڵنیایت دەتەوێت ئەم schedule ـە بسڕیتەوە؟',
    );
    if (!ok || !mounted) return;
    try {
      await AdvancedCustomerService.deleteScheduledReport(id);
      if (mounted) await _load();
    } catch (e) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          e,
          fallback: 'نەتوانرا schedule ـەکە بسڕدرێتەوە.',
        ),
        isError: true,
      );
    }
  }

  Future<void> _exportScheduledRun(
    Map<String, dynamic> run, {
    required bool pdf,
  }) async {
    try {
      if (pdf) {
        await ScheduledReportExportService.sharePdf(run);
      } else {
        await ScheduledReportExportService.shareCsv(run);
      }
    } catch (e) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          e,
          fallback: 'نەتوانرا فایلەکە دروست بکرێت.',
        ),
        isError: true,
      );
    }
  }

  Widget _scheduledRunCard(Map<String, dynamic> run) {
    final kind = run['report_kind']?.toString() ?? 'report';
    final generated = DateTime.tryParse(
      run['generated_at']?.toString() ?? '',
    );
    final generatedLabel = generated == null
        ? (run['generated_at']?.toString() ?? '')
        : DateFormat('yyyy/MM/dd HH:mm').format(generated.toLocal());
    final payload = run['payload'];
    final fieldCount = payload is Map ? payload.length : 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history_rounded),
              title: Text(
                ScheduledReportExportService.reportKindLabel(kind),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text('$generatedLabel • $fieldCount خانە'),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _exportScheduledRun(run, pdf: false),
                    icon: const Icon(Icons.table_view_outlined, size: 18),
                    label: const Text('CSV'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _exportScheduledRun(run, pdf: true),
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: const Text('PDF'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCustomer(String? id) async {
    if (id == null || id.isEmpty) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          userId: id,
          openFinancialChat: true,
        ),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ناوەندی زانیاریی ئۆپەراسیۆن'),
          actions: [
            IconButton(
              tooltip: 'نوێکردنەوە',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'پەسەند'),
              Tab(text: 'پێشبینی هاتووچۆی پارە'),
              Tab(text: 'مامەڵەی نائاسایی'),
              Tab(text: 'کارمەند'),
              Tab(text: 'ڕاپۆرت'),
              Tab(text: 'کوالێتی داتا'),
            ],
          ),
        ),
        body: _loading && _approvals.isEmpty && _forecast.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _forecast.isEmpty
                ? Center(
                    child: FilledButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(_error!),
                    ),
                  )
                : TabBarView(
                    children: [
                      _approvalTab(),
                      _forecastTab(),
                      _anomalyTab(),
                      _employeeTab(),
                      _scheduleTab(),
                      _qualityTab(),
                    ],
                  ),
      ),
    );
  }

  Widget _approvalTab() {
    if (_approvals.isEmpty) {
      return _empty('هیچ داواکاریی پەسەندکردن نییە');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _approvals.length,
        itemBuilder: (context, i) {
          final r = _approvals[i];
          final pending = r['status'] == 'pending';
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () => _openCustomer(r['customer_id']?.toString()),
                    leading: const Icon(Icons.approval_outlined),
                    title: Text(r['customer_name']?.toString() ?? 'کڕیار'),
                    subtitle: Text(
                      '${_money(r['debt_amount'])} • '
                      '${_int(r['approved_count'])}/${_int(r['required_approvals'])} پەسەند',
                    ),
                    trailing: Chip(label: Text(r['status']?.toString() ?? '')),
                  ),
                  if (pending)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _decide(r, false),
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('ڕەتکردنەوە'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => _decide(r, true),
                            icon: const Icon(Icons.check_rounded),
                            label: const Text('پەسەند'),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _forecastTab() {
    final items = _list(_forecast['items']);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _metricCard('30 ڕۆژ IQD', _money(_forecast['total_iqd']), Icons.trending_up_rounded),
              _metricCard('30 ڕۆژ USD', _money(_forecast['total_usd'], usd: true), Icons.attach_money_rounded),
            ],
          ),
          const SizedBox(height: 14),
          ...items.map((r) => ListTile(
            leading: const Icon(Icons.calendar_month_outlined),
            title: Text(r['due_date']?.toString() ?? ''),
            subtitle: Text('${_int(r['items'])} مامەڵە'),
            trailing: Text(
              '${_money(r['iqd'])}\n${_money(r['usd'], usd: true)}',
              textAlign: TextAlign.end,
            ),
          )),
        ],
      ),
    );
  }

  Widget _anomalyTab() {
    if (_anomalies.isEmpty) return _empty('هیچ مامەڵەی نائاسایی نەدۆزرایەوە');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _anomalies.length,
        itemBuilder: (context, i) {
          final a = _anomalies[i];
          final duplicate = a['anomaly'] == 'possible_duplicate';
          return ListTile(
            onTap: () => _openCustomer(a['customer_id']?.toString()),
            leading: Icon(
              duplicate ? Icons.copy_all_outlined : Icons.warning_amber_rounded,
            ),
            title: Text(a['customer_name']?.toString() ?? 'کڕیار'),
            subtitle: Text(
              duplicate ? 'گومان لە مامەڵەی دووبارە' : 'بڕی زۆر نائاسایی',
            ),
            trailing: Text(_money(a['amount'])),
          );
        },
      ),
    );
  }

  Widget _employeeTab() {
    if (_employees.isEmpty) return _empty('داتای کارمەند نییە');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _employees.length,
        itemBuilder: (context, i) {
          final e = _employees[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e['name']?.toString() ?? 'کارمەند',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text('کڕیاری نوێ: ${_int(e['customers_added'])}'),
                  Text('قەرز: ${_int(e['debts_added'])} • ${_money(e['debt_amount'])}'),
                  Text('پارەدانەوە: ${_int(e['payments_recorded'])} • ${_money(e['payment_amount'])}'),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _scheduleTab() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: _addSchedule,
            icon: const Icon(Icons.add_alarm_rounded),
            label: const Text('ڕاپۆرتی خۆکار زیاد بکە'),
          ),
          const SizedBox(height: 16),
          const AppSectionHeader(
            title: 'خشتەی ڕاپۆرتە خۆکارەکان',
            subtitle: 'ڕاپۆرتە خۆکارە چالاک و کاتی run ـی داهاتوو',
          ),
          const SizedBox(height: 8),
          if (_schedules.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: Text('هێشتا schedule نییە')),
            ),
          ..._schedules.map(
            (s) => ListTile(
              leading: const Icon(Icons.schedule_send_outlined),
              title: Text(
                ScheduledReportExportService.reportKindLabel(
                  s['report_kind']?.toString() ?? '',
                ),
              ),
              subtitle: Text(
                '${_scheduleTimingLabel(s)}\n'
                'next: ${s['next_run_at'] ?? '—'}',
              ),
              trailing: PopupMenuButton<String>(
                tooltip: 'بەڕێوەبردنی schedule',
                onSelected: (value) {
                  if (value == 'toggle') {
                    _toggleSchedule(s);
                  } else if (value == 'delete') {
                    _deleteSchedule(s);
                  }
                },
                itemBuilder: (context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'toggle',
                    child: Row(
                      children: [
                        Icon(
                          s['enabled'] == true
                              ? Icons.pause_circle_outline
                              : Icons.play_circle_outline,
                        ),
                        const SizedBox(width: 8),
                        Text(s['enabled'] == true ? 'وەستاندن' : 'بەردەوامکردنەوە'),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded),
                        SizedBox(width: 8),
                        Text('سڕینەوە'),
                      ],
                    ),
                  ),
                ],
                child: Icon(
                  s['enabled'] == true
                      ? Icons.check_circle_rounded
                      : Icons.pause_circle_outline,
                ),
              ),

            ),
          ),
          const SizedBox(height: 18),
          const AppSectionHeader(
            title: 'مێژووی ڕاپۆرتە خۆکارەکان',
            subtitle: 'وێنەی داتای ئەو کاتە ـە درووستکراوەکان؛ PDF یان CSV بکە',
          ),
          const SizedBox(height: 10),
          if (_reportRuns.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'هێشتا هیچ ڕاپۆرتی خۆکار ـێک run نەبووە',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ..._reportRuns.map(_scheduledRunCard),
        ],
      ),
    );
  }

  Widget _qualityTab() {
    final items = _list(_quality['items']);
    if (items.isEmpty) return _empty('کێشەی کوالێتی داتا نەدۆزرایەوە');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppSurface(
            child: Text(
              'کۆی کێشەکان: ${_int(_quality['count'])}',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
          const SizedBox(height: 10),
          ...items.map((q) => ListTile(
            onTap: () => _openCustomer(q['customer_id']?.toString()),
            leading: const Icon(Icons.rule_folder_outlined),
            title: Text(q['name']?.toString() ?? 'کڕیار'),
            subtitle: Text(q['phone']?.toString() ?? ''),
            trailing: Text(_qualityLabel(q['issue']?.toString() ?? '')),
          )),
        ],
      ),
    );
  }

  String _qualityLabel(String key) {
    return switch (key) {
      'missing_name' => 'ناو ناقصە',
      'invalid_phone' => 'مۆبایل نادروستە',
      'open_debt_without_due_date' => 'قەرزی بێ بەروار',
      'duplicate_name' => 'ناوی دووبارە',
      _ => key,
    };
  }

  Widget _metricCard(String label, String value, IconData icon) {
    return SizedBox(
      width: 220,
      child: AppSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            Text(label),
          ],
        ),
      ),
    );
  }

  Widget _empty(String text) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 160),
          Icon(Icons.inbox_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 10),
          Center(child: Text(text)),
        ],
      ),
    );
  }
}
