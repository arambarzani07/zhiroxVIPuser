import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

class IntelligenceCenterScreen extends StatefulWidget {
  const IntelligenceCenterScreen({super.key});

  @override
  State<IntelligenceCenterScreen> createState() => _IntelligenceCenterScreenState();
}

class _IntelligenceCenterScreenState extends State<IntelligenceCenterScreen> {
  _IntelligenceSnapshot? _snapshot;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<List<Map<String, dynamic>>> _fetchAll(
    String table,
    String columns,
  ) async {
    await PBService.ensureInitialized();
    const pageSize = 500;
    var from = 0;
    final rows = <Map<String, dynamic>>[];

    while (true) {
      final raw = await PBService.client
          .from(table)
          .select(columns)
          .range(from, from + pageSize - 1);
      final page = (raw as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
      rows.addAll(page);
      if (page.length < pageSize) break;
      from += pageSize;
    }
    return rows;
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final auth = context.read<AuthProvider>();
      if (!auth.isLoggedIn || auth.userRole != 'admin') {
        throw StateError('admin_required');
      }

      final results = await Future.wait([
        _fetchAll(
          'debts',
          'id,customer_id,amount,remaining,due_date,status,created_at',
        ),
        _fetchAll('payments', 'id,debt_id,amount,created_at'),
        _fetchAll('profiles', 'id,name,phone,role,active'),
      ]);

      final snapshot = _IntelligenceSnapshot.build(
        debts: results[0],
        payments: results[1],
        profiles: results[2],
      );

      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'نەتوانرا زانیارییە زیرەکەکان باربکرێن. پەیوەندی ئینتەرنێت بپشکنە و دووبارە هەوڵ بدە.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!auth.isLoggedIn || auth.userRole != 'admin') {
      return const SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Intelligence Center تەنها بۆ بەڕێوەبەر بەردەستە.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (_loading && _snapshot == null) {
      return const SafeArea(child: Center(child: CircularProgressIndicator()));
    }

    if (_snapshot == null) {
      return SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(28),
            children: [
              const SizedBox(height: 100),
              const Icon(Icons.insights_rounded, size: 58, color: Colors.orange),
              const SizedBox(height: 18),
              Text(
                _error ?? 'هەڵەیەک ڕوویدا.',
                textAlign: TextAlign.center,
                style: const TextStyle(height: 1.7),
              ),
              const SizedBox(height: 20),
              Center(
                child: ElevatedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('دووبارە هەوڵ بدە'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final snapshot = _snapshot!;
    final background =
        isDark ? AppDarkColors.background : const Color(0xFFF5F7FA);

    return ColoredBox(
      color: background,
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            children: [
              _buildHeader(snapshot, isDark),
              const SizedBox(height: 16),
              _buildSectionTitle(
                icon: Icons.query_stats_rounded,
                title: 'پێشبینی پارە و قەرز',
                subtitle: 'کورتەی ٧ و ٣٠ ڕۆژی داهاتوو',
                isDark: isDark,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _metricCard(
                      isDark: isDark,
                      icon: Icons.warning_amber_rounded,
                      title: 'دواکەوتوو',
                      value: AppHelpers.formatCurrency(snapshot.overdueAmount),
                      subtitle: '${snapshot.overdueCount} قەرز',
                      accent: Colors.red,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _metricCard(
                      isDark: isDark,
                      icon: Icons.event_upcoming_rounded,
                      title: 'تا ٧ ڕۆژ',
                      value: AppHelpers.formatCurrency(snapshot.due7Amount),
                      subtitle: '${snapshot.due7Count} قەرز',
                      accent: Colors.orange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _metricCard(
                      isDark: isDark,
                      icon: Icons.calendar_month_rounded,
                      title: 'تا ٣٠ ڕۆژ',
                      value: AppHelpers.formatCurrency(snapshot.due30Amount),
                      subtitle: '${snapshot.due30Count} قەرز',
                      accent: Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _metricCard(
                      isDark: isDark,
                      icon: Icons.payments_rounded,
                      title: 'وەرگیراوی ٣٠ ڕۆژ',
                      value: AppHelpers.formatCurrency(snapshot.collected30),
                      subtitle: '${snapshot.paymentCount30} پارەدان',
                      accent: Colors.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildSectionTitle(
                icon: Icons.auto_awesome_rounded,
                title: 'Smart Alerts',
                subtitle: 'خاڵە گرنگەکان کە پێویستیان بە سەرنجە',
                isDark: isDark,
              ),
              const SizedBox(height: 10),
              ...snapshot.alerts.map(
                (alert) => _alertCard(alert, isDark),
              ),
              const SizedBox(height: 20),
              _buildSectionTitle(
                icon: Icons.shield_outlined,
                title: 'Risk Score ـی کڕیارەکان',
                subtitle: 'نمرەی ٠ تا ١٠٠ بەپێی دواکەوتن و بڕی ماوە',
                isDark: isDark,
              ),
              const SizedBox(height: 10),
              if (snapshot.risks.isEmpty)
                _emptyCard(
                  isDark,
                  'هیچ قەرزی کراوەیەک نییە بۆ هەژمارکردنی Risk Score.',
                )
              else
                ...snapshot.risks.take(8).map(
                      (risk) => _riskCard(risk, isDark),
                    ),
              const SizedBox(height: 12),
              Text(
                'تێبینی: Risk Score لەم قۆناغەدا مۆدێلێکی هەژمارییە و لە دواکەوتن، بڕی قەرزی ماوە و ماوەی دواکەوتن دروست دەکرێت؛ بڕیاری کۆتایی لەلایەن بەڕێوەبەرە.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.65,
                  color: isDark
                      ? AppDarkColors.textSecondary
                      : const Color(0xFF667085),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(_IntelligenceSnapshot snapshot, bool isDark) {
    final health = snapshot.healthScore;
    final healthLabel = health >= 80
        ? 'باش'
        : health >= 60
            ? 'مامناوەند'
            : 'پێویستی بە سەرنج هەیە';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary,
            AppColors.primary.withValues(alpha: 0.78),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ZHIROX Intelligence Center',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'پێشبینی، مەترسی و خاڵە گرنگەکان لە یەک شوێن',
                      style: TextStyle(color: Colors.white70, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _loading ? null : _load,
                icon: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.refresh_rounded, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Health Score',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$health / 100',
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      healthLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 58,
                color: Colors.white.withValues(alpha: 0.18),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'کۆی قەرزی ماوە',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      AppHelpers.formatCurrency(snapshot.totalRemaining),
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${snapshot.openCount} قەرزی کراوە',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isDark,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.primary, size: 21),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: isDark
                      ? AppDarkColors.textPrimary
                      : const Color(0xFF101828),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 10.5,
                  color: isDark
                      ? AppDarkColors.textSecondary
                      : const Color(0xFF667085),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metricCard({
    required bool isDark,
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: isDark ? AppDarkColors.cardBorder : const Color(0xFFE7EAF0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppDarkColors.textSecondary
                        : const Color(0xFF475467),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: isDark
                  ? AppDarkColors.textPrimary
                  : const Color(0xFF101828),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              color: isDark
                  ? AppDarkColors.textSecondary
                  : const Color(0xFF98A2B3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _alertCard(_SmartAlert alert, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: isDark ? AppDarkColors.cardBorder : const Color(0xFFE7EAF0),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: alert.color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(alert.icon, color: alert.color, size: 20),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: isDark
                        ? AppDarkColors.textPrimary
                        : const Color(0xFF344054),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  alert.message,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.55,
                    color: isDark
                        ? AppDarkColors.textSecondary
                        : const Color(0xFF667085),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _riskCard(_CustomerRisk risk, bool isDark) {
    final accent = risk.score >= 70
        ? Colors.red
        : risk.score >= 40
            ? Colors.orange
            : Colors.green;
    final label = risk.score >= 70
        ? 'مەترسی بەرز'
        : risk.score >= 40
            ? 'مامناوەند'
            : 'کەم';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppDarkColors.cardBorder : const Color(0xFFE7EAF0),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: risk.score / 100,
                  strokeWidth: 5,
                  backgroundColor: accent.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                ),
                Text(
                  '${risk.score}',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  risk.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: isDark
                        ? AppDarkColors.textPrimary
                        : const Color(0xFF101828),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$label  •  ${risk.overdueCount} دواکەوتوو  •  ${risk.maxOverdueDays} ڕۆژ',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.3,
                    color: isDark
                        ? AppDarkColors.textSecondary
                        : const Color(0xFF667085),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                AppHelpers.formatCurrency(risk.remaining),
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: isDark
                      ? AppDarkColors.textPrimary
                      : const Color(0xFF344054),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'ماوە',
                style: TextStyle(
                  fontSize: 9.5,
                  color: isDark
                      ? AppDarkColors.textSecondary
                      : const Color(0xFF98A2B3),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyCard(bool isDark, String text) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppDarkColors.cardBorder : const Color(0xFFE7EAF0),
        ),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11.5,
          color: isDark
              ? AppDarkColors.textSecondary
              : const Color(0xFF667085),
        ),
      ),
    );
  }
}

class _IntelligenceSnapshot {
  const _IntelligenceSnapshot({
    required this.totalRemaining,
    required this.openCount,
    required this.overdueAmount,
    required this.overdueCount,
    required this.due7Amount,
    required this.due7Count,
    required this.due30Amount,
    required this.due30Count,
    required this.collected30,
    required this.paymentCount30,
    required this.healthScore,
    required this.risks,
    required this.alerts,
  });

  final double totalRemaining;
  final int openCount;
  final double overdueAmount;
  final int overdueCount;
  final double due7Amount;
  final int due7Count;
  final double due30Amount;
  final int due30Count;
  final double collected30;
  final int paymentCount30;
  final int healthScore;
  final List<_CustomerRisk> risks;
  final List<_SmartAlert> alerts;

  static double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static DateTime? _date(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  static _IntelligenceSnapshot build({
    required List<Map<String, dynamic>> debts,
    required List<Map<String, dynamic>> payments,
    required List<Map<String, dynamic>> profiles,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final next7 = today.add(const Duration(days: 7));
    final next30 = today.add(const Duration(days: 30));
    final last30 = now.subtract(const Duration(days: 30));

    final customerNames = <String, String>{};
    for (final profile in profiles) {
      if (profile['role']?.toString() != 'customer') continue;
      final id = profile['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final name = profile['name']?.toString().trim() ?? '';
      customerNames[id] = name.isEmpty ? 'کڕیار' : name;
    }

    var totalRemaining = 0.0;
    var openCount = 0;
    var overdueAmount = 0.0;
    var overdueCount = 0;
    var due7Amount = 0.0;
    var due7Count = 0;
    var due30Amount = 0.0;
    var due30Count = 0;
    final aggregates = <String, _RiskAccumulator>{};

    for (final debt in debts) {
      final remaining = _number(debt['remaining']);
      if (remaining <= 0) continue;
      final customerId = debt['customer_id']?.toString() ?? '';
      if (customerId.isEmpty) continue;

      openCount++;
      totalRemaining += remaining;
      final acc = aggregates.putIfAbsent(
        customerId,
        () => _RiskAccumulator(customerId),
      );
      acc.remaining += remaining;
      acc.openCount++;

      final due = _date(debt['due_date']);
      if (due == null) continue;
      final dueDay = DateTime(due.year, due.month, due.day);

      if (dueDay.isBefore(today)) {
        final days = today.difference(dueDay).inDays;
        overdueAmount += remaining;
        overdueCount++;
        acc.overdueRemaining += remaining;
        acc.overdueCount++;
        if (days > acc.maxOverdueDays) acc.maxOverdueDays = days;
      } else if (!dueDay.isAfter(next7)) {
        due7Amount += remaining;
        due7Count++;
        acc.due7Amount += remaining;
      }

      if (!dueDay.isBefore(today) && !dueDay.isAfter(next30)) {
        due30Amount += remaining;
        due30Count++;
      }
    }

    var collected30 = 0.0;
    var paymentCount30 = 0;
    for (final payment in payments) {
      final created = _date(payment['created_at']);
      if (created == null || created.isBefore(last30)) continue;
      collected30 += _number(payment['amount']);
      paymentCount30++;
    }

    final risks = <_CustomerRisk>[];
    for (final acc in aggregates.values) {
      final overdueShare =
          acc.remaining <= 0 ? 0.0 : acc.overdueRemaining / acc.remaining;
      final overdueFrequency =
          acc.openCount <= 0 ? 0.0 : acc.overdueCount / acc.openCount;
      final severity = (acc.maxOverdueDays / 60).clamp(0.0, 1.0);
      final dueSoonShare =
          acc.remaining <= 0 ? 0.0 : (acc.due7Amount / acc.remaining).clamp(0.0, 1.0);
      final score = (overdueShare * 45 +
              overdueFrequency * 25 +
              severity * 25 +
              dueSoonShare * 5)
          .round()
          .clamp(0, 100);
      risks.add(
        _CustomerRisk(
          customerId: acc.customerId,
          name: customerNames[acc.customerId] ?? 'کڕیار',
          remaining: acc.remaining,
          overdueRemaining: acc.overdueRemaining,
          overdueCount: acc.overdueCount,
          maxOverdueDays: acc.maxOverdueDays,
          score: score,
        ),
      );
    }
    risks.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return b.overdueRemaining.compareTo(a.overdueRemaining);
    });

    final highRiskCount = risks.where((risk) => risk.score >= 70).length;
    final overdueRatio =
        totalRemaining <= 0 ? 0.0 : (overdueAmount / totalRemaining).clamp(0.0, 1.0);
    final highRiskRatio =
        risks.isEmpty ? 0.0 : (highRiskCount / risks.length).clamp(0.0, 1.0);
    final healthScore =
        (100 - (overdueRatio * 65) - (highRiskRatio * 35)).round().clamp(0, 100);

    final alerts = <_SmartAlert>[];
    if (overdueAmount > 0) {
      alerts.add(
        _SmartAlert(
          title: 'قەرزی دواکەوتوو پێویستی بە سەرنج هەیە',
          message:
              '${AppHelpers.formatCurrency(overdueAmount)} لە $overdueCount قەرزدا دواکەوتووە.',
          icon: Icons.warning_amber_rounded,
          color: Colors.red,
        ),
      );
    }
    if (due7Amount > 0) {
      alerts.add(
        _SmartAlert(
          title: '٧ ڕۆژی داهاتوو',
          message:
              '${AppHelpers.formatCurrency(due7Amount)} لە $due7Count قەرزدا نزیکە لە بەرواری دانەوە.',
          icon: Icons.schedule_rounded,
          color: Colors.orange,
        ),
      );
    }
    if (highRiskCount > 0) {
      alerts.add(
        _SmartAlert(
          title: 'کڕیاری مەترسیدار',
          message:
              '$highRiskCount کڕیار Risk Score ـی ٧٠ یان زیاتر هەیە؛ پێداچوونەوەیان پێشنیار دەکرێت.',
          icon: Icons.person_search_rounded,
          color: Colors.deepOrange,
        ),
      );
    }
    if (alerts.isEmpty) {
      alerts.add(
        const _SmartAlert(
          title: 'دۆخی گشتی باشە',
          message:
              'لە ئێستادا ئاگادارکردنەوەی گرنگ نییە. بەردەوام بە لە پشکنینی قەرز و دانەوەکان.',
          icon: Icons.verified_rounded,
          color: Colors.green,
        ),
      );
    }

    return _IntelligenceSnapshot(
      totalRemaining: totalRemaining,
      openCount: openCount,
      overdueAmount: overdueAmount,
      overdueCount: overdueCount,
      due7Amount: due7Amount,
      due7Count: due7Count,
      due30Amount: due30Amount,
      due30Count: due30Count,
      collected30: collected30,
      paymentCount30: paymentCount30,
      healthScore: healthScore,
      risks: risks,
      alerts: alerts,
    );
  }
}

class _RiskAccumulator {
  _RiskAccumulator(this.customerId);

  final String customerId;
  double remaining = 0;
  double overdueRemaining = 0;
  double due7Amount = 0;
  int openCount = 0;
  int overdueCount = 0;
  int maxOverdueDays = 0;
}

class _CustomerRisk {
  const _CustomerRisk({
    required this.customerId,
    required this.name,
    required this.remaining,
    required this.overdueRemaining,
    required this.overdueCount,
    required this.maxOverdueDays,
    required this.score,
  });

  final String customerId;
  final String name;
  final double remaining;
  final double overdueRemaining;
  final int overdueCount;
  final int maxOverdueDays;
  final int score;
}

class _SmartAlert {
  const _SmartAlert({
    required this.title,
    required this.message,
    required this.icon,
    required this.color,
  });

  final String title;
  final String message;
  final IconData icon;
  final Color color;
}
