import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/screens/shared/user_profile_screen.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

class IntelligenceCenterScreen extends StatefulWidget {
  const IntelligenceCenterScreen({super.key});

  @override
  State<IntelligenceCenterScreen> createState() =>
      _IntelligenceCenterScreenState();
}

class _IntelligenceCenterScreenState extends State<IntelligenceCenterScreen> {
  final _questionController = TextEditingController();

  Map<String, dynamic>? _snapshot;
  Map<String, dynamic>? _ai;
  bool _aiEnabled = false;
  bool _loading = true;
  bool _analyzing = false;
  String? _error;
  String? _aiError;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSnapshot());
  }

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _maps(dynamic value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  double _num(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  String _functionMessage(dynamic value) {
    final code = value is Map ? value['error']?.toString() ?? '' : '$value';
    switch (code) {
      case 'unauthorized':
        return 'پەیوەندی هەژمارەکەت نوێ بکەرەوە و دووبارە هەوڵ بدە.';
      case 'admin_required':
        return 'ZHIROX AI تەنها بۆ بەڕێوەبەر بەردەستە.';
      case 'account_inactive':
        return 'هەژماری بەڕێوەبەر ناچالاکە.';
      case 'subscription_expired':
        return 'ماوەی بەشداریکردن تەواو بووە.';
      case 'ai_not_configured':
        return 'AI provider هێشتا لە سێرڤەر چالاک نەکراوە.';
      default:
        if (code.startsWith('openai_')) {
          return 'خزمەتگوزاری AI کاتییەکە بەردەست نییە؛ دووبارە هەوڵ بدە.';
        }
        return 'هەڵەیەک لە ZHIROX AI ڕوویدا.';
    }
  }

  String _transportMessage(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('401') ||
        text.contains('jwt') ||
        text.contains('unauthorized')) {
      return _functionMessage({'error': 'unauthorized'});
    }
    if (text.contains('timeout') ||
        text.contains('socket') ||
        text.contains('network') ||
        text.contains('fetch')) {
      return 'پەیوەندی ئینتەرنێت بپشکنە و دووبارە هەوڵ بدە.';
    }
    return 'هەڵەیەک لە ZHIROX AI ڕوویدا.';
  }

  Future<Map<String, dynamic>> _invoke(
    String action, {
    String question = '',
  }) async {
    await PBService.ensureInitialized();
    try {
      final response = await PBService.client.functions.invoke(
        'intelligence-ai',
        body: {
          'action': action,
          if (question.trim().isNotEmpty) 'question': question.trim(),
        },
      );
      final data = response.data;
      if (data is! Map) throw const FormatException('invalid_ai_response');
      return Map<String, dynamic>.from(data);
    } catch (error) {
      throw Exception(_transportMessage(error));
    }
  }

  Future<void> _loadSnapshot() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _invoke('snapshot');
      if (data['ok'] != true) throw Exception(_functionMessage(data));
      if (!mounted) return;
      setState(() {
        _snapshot = _map(data['snapshot']);
        _aiEnabled = data['ai_enabled'] == true;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _runAi() async {
    if (_analyzing || !_aiEnabled) return;
    setState(() {
      _analyzing = true;
      _aiError = null;
    });

    try {
      final data = await _invoke(
        'analyze',
        question: _questionController.text,
      );
      if (!mounted) return;
      final nextSnapshot = _map(data['snapshot']);
      final nextAi = _map(data['ai']);
      setState(() {
        if (nextSnapshot.isNotEmpty) _snapshot = nextSnapshot;
        _aiEnabled = data['ai_enabled'] == true;
        _ai = nextAi.isEmpty ? null : nextAi;
        _aiError = data['error'] == null ? null : _functionMessage(data);
        _analyzing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _aiError = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _openCustomer(String customerId) async {
    if (customerId.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UserProfileScreen(
          userId: customerId,
          openFinancialChat: true,
        ),
      ),
    );
    if (mounted) unawaited(_loadSnapshot());
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background =
        isDark ? AppDarkColors.background : const Color(0xFFF5F7FA);

    if (!auth.isLoggedIn || auth.userRole != 'admin') {
      return const SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'ZHIROX AI Intelligence تەنها بۆ بەڕێوەبەر بەردەستە.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (_loading && _snapshot == null) {
      return ColoredBox(
        color: background,
        child: const SafeArea(
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_snapshot == null) {
      return ColoredBox(
        color: background,
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _loadSnapshot,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(28),
              children: [
                const SizedBox(height: 120),
                const Icon(
                  Icons.auto_awesome_rounded,
                  size: 58,
                  color: Colors.orange,
                ),
                const SizedBox(height: 18),
                Text(
                  _error ?? 'نەتوانرا زانیارییەکان باربکرێن.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(height: 1.7),
                ),
                const SizedBox(height: 18),
                Center(
                  child: ElevatedButton.icon(
                    onPressed: _loadSnapshot,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('دووبارە هەوڵ بدە'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final snapshot = _snapshot!;
    final totals = _map(snapshot['totals']);
    final risks = _maps(snapshot['top_risks']);

    return ColoredBox(
      color: background,
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _loadSnapshot,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
            children: [
              _buildHeader(snapshot),
              const SizedBox(height: 14),
              _buildMetrics(totals, isDark),
              const SizedBox(height: 18),
              _buildAiConsole(isDark),
              if (_ai != null) ...[
                const SizedBox(height: 16),
                _buildAiResult(_ai!, isDark),
              ],
              const SizedBox(height: 20),
              _sectionTitle(
                icon: Icons.shield_outlined,
                title: 'مەترسیی کڕیارەکان',
                subtitle:
                    'Risk Score ـی هەژماری • AI بۆ شیکردنەوەی هۆکار بەکاردێت',
                isDark: isDark,
              ),
              const SizedBox(height: 10),
              if (risks.isEmpty)
                _emptyCard(isDark, 'هیچ قەرزی کراوەیەک نییە.')
              else
                ...risks.take(8).map((risk) => _riskCard(risk, isDark)),
              const SizedBox(height: 16),
              Text(
                'ZHIROX AI تەنها پێشنیار و شیکردنەوە دەدات؛ هیچ قەرز، پارەدانەوە، نامە یان بڕیارێک بەخۆکار جێبەجێ ناکات.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.7,
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

  Widget _buildHeader(Map<String, dynamic> snapshot) {
    final health = _num(snapshot['health_score']).round();
    final marketName = snapshot['market_name']?.toString().trim() ?? '';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary,
            AppColors.primary.withValues(alpha: 0.76),
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
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 25,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ZHIROX AI Intelligence',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      marketName.isEmpty
                          ? 'شیکردنەوەی زیرەکی دارایی'
                          : marketName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              _statusPill(),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                '$health',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Text(
                ' / 100',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  health >= 80
                      ? 'دۆخی دارایی باشە'
                      : health >= 60
                          ? 'دۆخ مامناوەندە'
                          : 'پێویستی بە سەرنجی زیاترە',
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusPill() {
    final color = _aiEnabled ? Colors.greenAccent : Colors.orangeAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.65)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _aiEnabled ? Icons.bolt_rounded : Icons.info_outline_rounded,
            color: Colors.white,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            _aiEnabled ? 'AI چالاک' : 'AI ناچالاک',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetrics(Map<String, dynamic> totals, bool isDark) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _metricCard(
                isDark: isDark,
                icon: Icons.account_balance_wallet_outlined,
                title: 'کۆی قەرزی ماوە',
                value: AppHelpers.formatCurrency(
                  _num(totals['total_remaining_iqd']),
                ),
                accent: Colors.red,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _metricCard(
                isDark: isDark,
                icon: Icons.warning_amber_rounded,
                title: 'دواکەوتوو',
                value: AppHelpers.formatCurrency(_num(totals['overdue_iqd'])),
                subtitle: '${_num(totals['overdue_count']).round()} قەرز',
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
                icon: Icons.payments_outlined,
                title: 'وەرگیراوی ٣٠ ڕۆژ',
                value: AppHelpers.formatCurrency(
                  _num(totals['collected_30_iqd']),
                ),
                subtitle:
                    '${_num(totals['collection_change_percent']).toStringAsFixed(1)}%',
                accent: Colors.green,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _metricCard(
                isDark: isDark,
                icon: Icons.people_outline_rounded,
                title: 'کڕیار',
                value: '${_num(totals['customers']).round()}',
                subtitle:
                    '${_num(totals['high_risk_customers']).round()} مەترسی بەرز',
                accent: Colors.blue,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAiConsole(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFE4E7EC),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.psychology_alt_rounded, color: AppColors.primary),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'پرسیار لە ZHIROX AI',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: isDark
                        ? AppDarkColors.textPrimary
                        : const Color(0xFF101828),
                  ),
                ),
              ),
              if (_analyzing)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _aiEnabled
                ? 'پرسیاری تایبەت بکە، یان خانەکە بەتاڵ بهێڵە بۆ تحلیلی گشتی.'
                : 'هەژمار و Risk Score کار دەکات، بەڵام AI provider هێشتا لە سێرڤەر چالاک نەکراوە.',
            style: TextStyle(
              fontSize: 11,
              height: 1.6,
              color: isDark
                  ? AppDarkColors.textSecondary
                  : const Color(0xFF667085),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _questionController,
            enabled: _aiEnabled && !_analyzing,
            minLines: 2,
            maxLines: 4,
            textDirection: TextDirection.rtl,
            decoration: InputDecoration(
              hintText:
                  'نموونە: کام کڕیاران پێویستە ئەم هەفتەیە پەیوەندییان پێوە بکرێت؟',
              hintStyle: TextStyle(color: Colors.grey[500], fontSize: 11),
              filled: true,
              fillColor: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (_aiError != null) ...[
            const SizedBox(height: 10),
            Text(
              _aiError!,
              style: const TextStyle(
                color: Colors.orange,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _aiEnabled && !_analyzing ? _runAi : null,
              icon: _analyzing
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.auto_awesome_rounded),
              label: Text(_analyzing ? 'AI شیکاری دەکات...' : 'تحلیلی AI'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiResult(Map<String, dynamic> ai, bool isDark) {
    final alerts = _maps(ai['alerts']);
    final recommendations = _maps(ai['recommendations']);
    final customers = _maps(ai['customer_insights']);
    final model = ai['model']?.toString() ?? '';
    final confidence = (_num(ai['confidence']) * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          icon: Icons.auto_awesome_rounded,
          title: 'تحلیلی AI',
          subtitle: model.isEmpty
              ? 'پێشنیاری زیرەکی'
              : '$model • confidence $confidence%',
          isDark: isDark,
        ),
        const SizedBox(height: 10),
        _textCard(
          isDark,
          ai['executive_summary']?.toString() ?? '',
          icon: Icons.summarize_rounded,
        ),
        if ((ai['health_assessment']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 10),
          _textCard(
            isDark,
            ai['health_assessment'].toString(),
            icon: Icons.monitor_heart_outlined,
          ),
        ],
        if (alerts.isNotEmpty) ...[
          const SizedBox(height: 14),
          _smallTitle('ئاگادارکردنەوەکانی AI', isDark),
          const SizedBox(height: 8),
          ...alerts.map((item) => _aiAlertCard(item, isDark)),
        ],
        if (recommendations.isNotEmpty) ...[
          const SizedBox(height: 14),
          _smallTitle('پێشنیارەکان', isDark),
          const SizedBox(height: 8),
          ...recommendations.map((item) => _recommendationCard(item, isDark)),
        ],
        if (customers.isNotEmpty) ...[
          const SizedBox(height: 14),
          _smallTitle('شیکردنەوەی کڕیار', isDark),
          const SizedBox(height: 8),
          ...customers.take(5).map((item) => _customerAiCard(item, isDark)),
        ],
      ],
    );
  }

  Widget _riskCard(Map<String, dynamic> risk, bool isDark) {
    final score = _num(risk['risk_score']).round();
    final color = score >= 70
        ? Colors.red
        : score >= 40
            ? Colors.orange
            : Colors.green;
    final customerId = risk['customer_id']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: customerId.isEmpty
              ? null
              : () => unawaited(_openCustomer(customerId)),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : const Color(0xFFE9EDF3),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '$score',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        risk['name']?.toString() ?? 'کڕیار',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: isDark
                              ? AppDarkColors.textPrimary
                              : const Color(0xFF1D2939),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ماوە: ${AppHelpers.formatCurrency(_num(risk['remaining_iqd']))} • '
                        'دواکەوتوو: ${AppHelpers.formatCurrency(_num(risk['overdue_iqd']))}',
                        maxLines: 2,
                        style: TextStyle(
                          fontSize: 10.5,
                          height: 1.5,
                          color: isDark
                              ? AppDarkColors.textSecondary
                              : const Color(0xFF667085),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_left_rounded, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _aiAlertCard(Map<String, dynamic> item, bool isDark) {
    final severity = item['severity']?.toString() ?? 'low';
    final color = severity == 'high'
        ? Colors.red
        : severity == 'medium'
            ? Colors.orange
            : Colors.blue;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.10 : 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 19, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['title']?.toString() ?? '',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: isDark
                        ? AppDarkColors.textPrimary
                        : const Color(0xFF1D2939),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item['detail']?.toString() ?? '',
                  style: TextStyle(
                    height: 1.55,
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
      ),
    );
  }

  Widget _recommendationCard(Map<String, dynamic> item, bool isDark) {
    final priority = item['priority']?.toString() ?? 'low';
    final color = priority == 'high'
        ? Colors.red
        : priority == 'medium'
            ? Colors.orange
            : Colors.green;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.07)
              : const Color(0xFFE9EDF3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item['title']?.toString() ?? '',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                    color: isDark
                        ? AppDarkColors.textPrimary
                        : const Color(0xFF1D2939),
                  ),
                ),
              ),
            ],
          ),
          if ((item['why']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              item['why'].toString(),
              style: TextStyle(
                fontSize: 10.5,
                height: 1.55,
                color: isDark
                    ? AppDarkColors.textSecondary
                    : const Color(0xFF667085),
              ),
            ),
          ],
          if ((item['action']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'هەنگاو: ${item['action']}',
              style: TextStyle(
                fontSize: 10.5,
                height: 1.55,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _customerAiCard(Map<String, dynamic> item, bool isDark) {
    final customerId = item['customer_id']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: customerId.isEmpty
              ? null
              : () => unawaited(_openCustomer(customerId)),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : const Color(0xFFE9EDF3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['customer_name']?.toString() ?? 'کڕیار',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                    color: isDark
                        ? AppDarkColors.textPrimary
                        : const Color(0xFF1D2939),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  item['assessment']?.toString() ?? '',
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.55,
                    color: isDark
                        ? AppDarkColors.textSecondary
                        : const Color(0xFF667085),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  item['next_action']?.toString() ?? '',
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.55,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _metricCard({
    required bool isDark,
    required IconData icon,
    required String title,
    required String value,
    required Color accent,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.07)
              : const Color(0xFFE9EDF3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 10.5,
              color: isDark
                  ? AppDarkColors.textSecondary
                  : const Color(0xFF667085),
            ),
          ),
          const SizedBox(height: 3),
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
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5,
                color: accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle({
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
                  fontWeight: FontWeight.w900,
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

  Widget _smallTitle(String title, bool isDark) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w900,
        color: isDark ? AppDarkColors.textPrimary : const Color(0xFF1D2939),
      ),
    );
  }

  Widget _textCard(
    bool isDark,
    String text, {
    required IconData icon,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: isDark ? 0.10 : 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.7,
                color: isDark
                    ? AppDarkColors.textPrimary
                    : const Color(0xFF344054),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyCard(bool isDark, String text) {
    return Container(
      padding: const EdgeInsets.all(18),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          color: isDark
              ? AppDarkColors.textSecondary
              : const Color(0xFF667085),
        ),
      ),
    );
  }
}
