import 'package:flutter/material.dart';

import 'data_quality_issue.dart';

class DataQualityCard extends StatelessWidget {
  final DataQualityIssue issue;
  final VoidCallback? onTap;
  final bool showSupportDetails;

  const DataQualityCard({
    super.key,
    required this.issue,
    this.onTap,
    this.showSupportDetails = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(issue.severity);
    final icon = _severityIcon(issue.severity);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: color.withOpacity(0.22),
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 19,
                      backgroundColor: color.withOpacity(0.12),
                      child: Icon(icon, color: color, size: 21),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            issue.title,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            issue.collectionLabel,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    ),
                    _SeverityBadge(
                      label: issue.severityLabel,
                      color: color,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  issue.message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.55,
                      ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lightbulb_outline_rounded,
                        color: color,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          issue.suggestion,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                height: 1.45,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoChip(label: issue.typeLabel),
                    _InfoChip(label: issue.safeActionLabel),
                    if (issue.isLikelyOldDataIssue)
                      const _InfoChip(label: 'زۆرجار داتای کۆنە'),
                    if (issue.canAutoFix)
                      const _InfoChip(label: 'دەتوانرێت بە سەلامەتی ڕێکبخرێت'),
                  ],
                ),
                if (showSupportDetails) ...[
                  const SizedBox(height: 10),
                  _SupportDetails(issue: issue),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _severityColor(DataQualitySeverity severity) {
    switch (severity) {
      case DataQualitySeverity.critical:
        return Colors.redAccent;
      case DataQualitySeverity.warning:
        return Colors.orangeAccent;
      case DataQualitySeverity.info:
        return Colors.blueAccent;
    }
  }

  IconData _severityIcon(DataQualitySeverity severity) {
    switch (severity) {
      case DataQualitySeverity.critical:
        return Icons.priority_high_rounded;
      case DataQualitySeverity.warning:
        return Icons.warning_amber_rounded;
      case DataQualitySeverity.info:
        return Icons.info_rounded;
    }
  }
}

class _SupportDetails extends StatelessWidget {
  final DataQualityIssue issue;

  const _SupportDetails({required this.issue});

  @override
  Widget build(BuildContext context) {
    final details = <String>[
      'بەش: ${issue.collection}',
      if (issue.recordId != null && issue.recordId!.isNotEmpty)
        'ژمارەی ناوخۆی داتا: ${issue.recordId}',
      if (issue.customerId != null && issue.customerId!.isNotEmpty)
        'کڕیار: ${issue.customerId}',
      if (issue.debtId != null && issue.debtId!.isNotEmpty)
        'قەرز: ${issue.debtId}',
      if (issue.paymentId != null && issue.paymentId!.isNotEmpty)
        'پارەدانەوە: ${issue.paymentId}',
      if (issue.notificationId != null && issue.notificationId!.isNotEmpty)
        'ئاگادارکردنەوە: ${issue.notificationId}',
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'وردەکاری بۆ پشتیوانی',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 6),
          ...details.map(
            (detail) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                detail,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade700,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeverityBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _SeverityBadge({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;

  const _InfoChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(
        label,
        style: const TextStyle(fontSize: 12),
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
