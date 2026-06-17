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
  DataQualitySeverity? _selectedSeverity;

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

    final notifications =
        await PBService.pb.collection('notifications').getFullList(
              batch: 500,
              sort: '-created',
            );

    final checker = const DataQualityChecker();

    final issues = checker.analyze(
      users: users,
      debts: debts,
      payments: payments,
      notifications: notifications,
    );

    issues.sort((a, b) {
      return _severityRank(a.severity).compareTo(_severityRank(b.severity));
    });

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
    setState(() {
      _future = _loadData();
    });
    await _future;
  }

  List<DataQualityIssue> _filterIssues(List<DataQualityIssue> issues) {
    if (_selectedSeverity == null) return issues;
    return issues.where((issue) => issue.severity == _selectedSeverity).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('پشکنینی ژیرانەی داتا'),
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
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            if (snapshot.hasError) {
              return _ErrorView(
                message: snapshot.error.toString(),
                onRetry: _refresh,
              );
            }

            final data = snapshot.data;
            if (data == null) {
              return _ErrorView(
                message: 'داتا نەدۆزرایەوە.',
                onRetry: _refresh,
              );
            }

            final filteredIssues = _filterIssues(data.issues);

            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  _HeaderSummary(data: data),
                  const SizedBox(height: 8),
                  _FilterBar(
                    selectedSeverity: _selectedSeverity,
                    onChanged: (severity) {
                      setState(() {
                        _selectedSeverity = severity;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  if (filteredIssues.isEmpty)
                    const _EmptyQualityView()
                  else
                    ...filteredIssues.map(
                      (issue) => DataQualityCard(issue: issue),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HeaderSummary extends StatelessWidget {
  final _QualityData data;

  const _HeaderSummary({required this.data});

  @override
  Widget build(BuildContext context) {
    final criticalCount =
        data.issues.where((e) => e.severity == DataQualitySeverity.critical).length;
    final warningCount =
        data.issues.where((e) => e.severity == DataQualitySeverity.warning).length;
    final infoCount =
        data.issues.where((e) => e.severity == DataQualitySeverity.info).length;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary.withOpacity(0.18),
            Theme.of(context).colorScheme.secondary.withOpacity(0.10),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology_alt_rounded),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AI Data Quality Checker',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'ئەم بەشە داتاکانی سیستەم دەخوێنێتەوە و کێشەکان دەدۆزێتەوە، بەبێ ئەوەی هیچ داتایەک بسڕێتەوە یان بگۆڕێت.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SummaryChip(
                label: 'هەموو کێشەکان',
                value: data.issues.length,
                icon: Icons.rule_folder_rounded,
              ),
              _SummaryChip(
                label: 'مەترسیدار',
                value: criticalCount,
                icon: Icons.error_rounded,
              ),
              _SummaryChip(
                label: 'ئاگاداری',
                value: warningCount,
                icon: Icons.warning_amber_rounded,
              ),
              _SummaryChip(
                label: 'زانیاری',
                value: infoCount,
                icon: Icons.info_rounded,
              ),
              _SummaryChip(
                label: 'کڕیار/بەکارهێنەر',
                value: data.users.length,
                icon: Icons.people_rounded,
              ),
              _SummaryChip(
                label: 'قەرز',
                value: data.debts.length,
                icon: Icons.receipt_long_rounded,
              ),
              _SummaryChip(
                label: 'پارەدانەوە',
                value: data.payments.length,
                icon: Icons.payments_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final DataQualitySeverity? selectedSeverity;
  final ValueChanged<DataQualitySeverity?> onChanged;

  const _FilterBar({
    required this.selectedSeverity,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('هەموو'),
            selected: selectedSeverity == null,
            onSelected: (_) => onChanged(null),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('مەترسیدار'),
            selected: selectedSeverity == DataQualitySeverity.critical,
            onSelected: (_) => onChanged(DataQualitySeverity.critical),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('ئاگاداری'),
            selected: selectedSeverity == DataQualitySeverity.warning,
            onSelected: (_) => onChanged(DataQualitySeverity.warning),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('زانیاری'),
            selected: selectedSeverity == DataQualitySeverity.info,
            onSelected: (_) => onChanged(DataQualitySeverity.info),
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;

  const _SummaryChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text('$label: $value'),
      visualDensity: VisualDensity.compact,
    );
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
          Icon(
            Icons.verified_rounded,
            size: 64,
            color: Colors.greenAccent.shade400,
          ),
          const SizedBox(height: 12),
          Text(
            'هیچ کێشەیەکی گرنگ نەدۆزرایەوە ✅',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'داتاکان بەپێی یاساکانی پشکنین باش دیارن.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorView({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 56,
                color: Colors.redAccent,
              ),
              const SizedBox(height: 12),
              Text(
                'پشکنینی داتا سەرکەوتوو نەبوو',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('دووبارە هەوڵ بدەوە'),
              ),
            ],
          ),
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

  const _QualityData({
    required this.users,
    required this.debts,
    required this.payments,
    required this.notifications,
    required this.issues,
  });
}
