import 'package:flutter/material.dart';

import 'data_quality_issue.dart';

class DataQualityCard extends StatelessWidget {
  final DataQualityIssue issue;
  final VoidCallback? onTap;

  const DataQualityCard({
    super.key,
    required this.issue,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(issue.severity);
    final icon = _severityIcon(issue.severity);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: color.withOpacity(0.35),
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
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
                      radius: 18,
                      backgroundColor: color.withOpacity(0.12),
                      child: Icon(icon, color: color, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        issue.title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                    _SeverityBadge(
                      label: issue.severityLabel,
                      color: color,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  issue.message,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'پێشنیار: ${issue.suggestion}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoChip(label: issue.collection),
                    _InfoChip(label: issue.typeLabel),
                    if (issue.recordId != null && issue.recordId!.isNotEmpty)
                      _InfoChip(label: 'ID: ${issue.recordId}'),
                    if (issue.canAutoFix) const _InfoChip(label: 'Auto-fix later'),
                  ],
                ),
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
        return Icons.error_rounded;
      case DataQualitySeverity.warning:
        return Icons.warning_amber_rounded;
      case DataQualitySeverity.info:
        return Icons.info_rounded;
    }
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
