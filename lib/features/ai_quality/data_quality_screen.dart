import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../services/pb_service.dart';
import 'data_quality_card.dart';
import 'data_quality_checker.dart';
import 'data_quality_issue.dart';

class DataQualityScreen extends StatefulWidget {
  const DataQualityScreen({super.key});

  @override
  State<DataQualityScreen> createState() => _DataQualityScreenState();
}

class _DataQualityScreenState extends State<DataQualityScreen> {
  late Future<_QualityData> _future;
  bool _showDetails = false;

  @override
  void initState() {
    super.initState();
    _future = _loadData();
  }

  Future<_QualityData> _loadData() async {
    final users = await PBService.pb.collection('users').getFullList(
          batch: 500,
          sort: '-created',
        );
    final debts = await PBService.pb.collection('debts').getFullList(
          batch: 500,
          sort: '-created',
        );
    final payments = await PBService.pb.collection('payments').getFullList(
          batch: 500,
          sort: '-created',
        );
    final notifications = await PBService.pb
        .collection('notifications')
        .getFullList(batch: 500, sort: '-created');

    final issues = const DataQualityChecker().analyze(
      users: users,
      debts: debts,
      payments: payments,
      notifications: notifications,
    );

    issues.sort((a, b) => _severityRank(a.severity).compareTo(_severityRank(b.severity)));

    return _QualityData(
      users: users,
      debts: debts,
      payments: payments,
      notifications: notifications,
      issues: issues,
    );
  }

  static int _severityRank(DataQualitySeverity severity) {
    switch (severity) {
      case DataQualitySeverity.critical:
        return 0;
      case DataQualitySeverity.warning:
        return 1;
      case DataQualitySeverity.info:
        return 2;
    }
  }

  Future<void> _refresh() async {
    setState(() => _future = _loadData());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تەندروستی داتای مارکێت'),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'نوێکردنەوە',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: FutureBuilder<_QualityData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return _ErrorView(
                message: snapshot.error.toString(),
                onRetry: _refresh,
              );
            }

            final data = snapshot.data;
            if (data == null) {
              return _ErrorView(message: 'داتا نەدۆزرایەوە.', onRetry: _refresh);
            }

            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  _MainStatusCard(data: data),
                  _NumbersRow(data: data),
                  _ManagerGroups(data: data),
                  _SafePlanCard(data: data),
                  _DetailsSwitch(
                    value: _showDetails,
                    onChanged: (value) => setState(() => _showDetails = value),
                  ),
                  if (_showDetails)
                    ...data.issues.map(
                      (issue) => DataQualityCard(
                        issue: issue,
                        showSupportDetails: true,
                      ),
                    )
                  else if (data.issues.isEmpty)
                    const _EmptyQualityView(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MainStatusCard extends StatelessWidget {
  final _QualityData data;

  const _MainStatusCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final hasIssues = data.issues.isNotEmpty;
    final importantCount = data.issues.where((e) => e.isCritical).length;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: hasIssues
              ? [Colors.orange.withOpacity(0.18), Colors.blue.withOpacity(0.08)]
              : [Colors.green.withOpacity(0.18), Colors.blue.withOpacity(0.08)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasIssues ? Icons.manage_search_rounded : Icons.verified_rounded,
                size: 34,
                color: hasIssues ? Colors.orange.shade800 : Colors.green,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  hasIssues ? 'داتای مارکێت پێویستی بە ڕێکخستنەوە هەیە' : 'داتای مارکێت باش دیارە',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            hasIssues
                ? 'ئەم بەشە داتاکان دەخوێنێتەوە و تەنها پێشنیاری سەلامەت نیشان دەدات. هیچ داتایەک لێرە ناسڕدرێتەوە و ناگۆڕدرێت.'
                : 'هیچ خاڵێکی گرنگ بەپێی پشکنینی ئێستا نەدۆزرایەوە.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.6),
          ),
          if (importantCount > 0) ...[
            const SizedBox(height: 10),
            Text(
              '$importantCount خاڵی گرنگ پێویستی بە ئاگاداری هەیە.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ],
      ),
    );
  }
}

class _NumbersRow extends StatelessWidget {
  final _QualityData data;

  const _NumbersRow({required this.data});

  @override
  Widget build(BuildContext context) {
    final important = data.issues.where((e) => e.isCritical).length;
    final warning = data.issues.where((e) => e.isWarning).length;
    final oldData = data.issues.where((e) => e.isLikelyOldDataIssue).length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _MetricChip(label: 'هەموو خاڵەکان', value: data.issues.length),
          _MetricChip(label: 'گرنگ', value: important),
          _MetricChip(label: 'ئاگاداری', value: warning),
          _MetricChip(label: 'زۆرجار داتای کۆن', value: oldData),
        ],
      ),
    );
  }
}

class _ManagerGroups extends StatelessWidget {
  final _QualityData data;

  const _ManagerGroups({required this.data});

  @override
  Widget build(BuildContext context) {
    final oldData = data.issues.where((e) => e.type == DataQualityIssueType.missingAdminId).length;
    final money = data.issues.where((e) {
      return e.type == DataQualityIssueType.missingCustomer ||
          e.type == DataQualityIssueType.invalidDebtStatus ||
          e.type == DataQualityIssueType.invalidRemainingAmount ||
          e.type == DataQualityIssueType.paidDebtHasRemaining ||
          e.type == DataQualityIssueType.unpaidDebtHasNoRemaining ||
          e.type == DataQualityIssueType.orphanPayment;
    }).length;
    final profile = data.issues.length - oldData - money;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'کورتەی پشکنین',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _GroupTile(title: 'داتای کۆن', subtitle: 'پێویستی بە بەستنەوەی مارکێت هەیە.', count: oldData, icon: Icons.history_rounded, color: Colors.orangeAccent),
          _GroupTile(title: 'پارە و قەرز', subtitle: 'خاڵەکانی قەرز، ماوە و پارەدانەوە.', count: money, icon: Icons.account_balance_wallet_rounded, color: Colors.redAccent),
          _GroupTile(title: 'کڕیار و ئاگادارکردنەوە', subtitle: 'ژمارە، تۆمارکەر و پەیامەکان.', count: profile < 0 ? 0 : profile, icon: Icons.people_alt_rounded, color: Colors.blueAccent),
        ],
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final int count;
  final IconData icon;
  final Color color;

  const _GroupTile({required this.title, required this.subtitle, required this.count, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color.withOpacity(0.12), child: Icon(icon, color: color)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: Text(count.toString(), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
      ),
    );
  }
}

class _SafePlanCard extends StatelessWidget {
  final _QualityData data;

  const _SafePlanCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final safeCount = data.issues.where((e) => e.canAutoFix).length;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.task_alt_rounded),
                const SizedBox(width: 8),
                Text('پلانی پێشنیارکراو', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              data.issues.isEmpty
                  ? 'هیچ کارێکی گرنگ پێویست نییە.'
                  : 'سەرەتا وردەکارییەکان ببینە. دواتر دەتوانرێت پلانی ڕێکخستنەوەی سەلامەت زیاد بکرێت.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
            if (safeCount > 0) ...[
              const SizedBox(height: 8),
              Text('$safeCount خاڵ دەتوانرێت دواتر بە سەلامەتی ڕێکبخرێت.', style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailsSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _DetailsSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        title: const Text('بینینی وردەکاری بۆ پشتیوانی'),
        subtitle: const Text('وردەکارییە ناوخۆییەکان تەنها کاتێک دەرکەون کە پێویستت بە پشکنینی ورد هەبێت.'),
        secondary: const Icon(Icons.support_agent_rounded),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final int value;

  const _MetricChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text('$label: $value'), visualDensity: VisualDensity.compact);
  }
}

class _EmptyQualityView extends StatelessWidget {
  const _EmptyQualityView();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(Icons.verified_rounded, size: 64, color: Colors.greenAccent.shade400),
          const SizedBox(height: 12),
          Text('هیچ خاڵێکی گرنگ نەدۆزرایەوە ✅', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('داتاکان بەپێی یاساکانی پشکنین باش دیارن.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 56, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text('پشکنینی داتا سەرکەوتوو نەبوو', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('دووبارە هەوڵ بدەوە')),
          ],
        ),
      ),
    );
  }
}

class _QualityData {
  final List<RecordModel> users;
  final List<RecordModel> debts;
  final List<RecordModel> payments;
  final List<RecordModel> notifications;
  final List<DataQualityIssue> issues;

  const _QualityData({required this.users, required this.debts, required this.payments, required this.notifications, required this.issues});
}
