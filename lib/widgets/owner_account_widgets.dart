import 'package:flutter/material.dart';
import 'package:zhirox/widgets/app_design.dart';

/// Common identity layout for Owner cards that show platform account metadata.
class OwnerAccountIdentity extends StatelessWidget {
  const OwnerAccountIdentity({
    super.key,
    required this.marketName,
    required this.adminName,
    required this.phone,
    required this.icon,
  });

  final String marketName;
  final String adminName;
  final String phone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          child: Icon(icon, color: scheme.onPrimaryContainer),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                marketName,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              if (adminName.isNotEmpty || phone.isNotEmpty)
                const SizedBox(height: 2),
              if (adminName.isNotEmpty)
                Text(adminName, style: Theme.of(context).textTheme.bodyMedium),
              if (phone.isNotEmpty)
                Text(
                  phone,
                  textDirection: TextDirection.ltr,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Icon and text wrap together, including when placed inside a Wrap.
class OwnerMetadata extends StatelessWidget {
  const OwnerMetadata(this.icon, this.label, {super.key});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 5),
                child: Icon(icon, size: 14),
              ),
            ),
            TextSpan(text: label),
          ],
        ),
        style: const TextStyle(fontSize: 12),
      );
}

class OwnerStatusBadge extends StatelessWidget {
  const OwnerStatusBadge({
    super.key,
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
}

class OwnerLifecycleBadge extends StatelessWidget {
  const OwnerLifecycleBadge(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'trial' => ('تاقیکردنەوە', Colors.blue),
      'grace' => ('ماوەی ڕێگەپێدراو', Colors.orange),
      'suspended' => ('ڕاگیراو', Colors.red),
      'archived' => ('ئەرشیڤکراو', Colors.grey),
      _ => ('چالاک', Colors.green),
    };
    return OwnerStatusBadge(label: label, color: color);
  }
}

class OwnerMetricCard extends StatelessWidget {
  const OwnerMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.width = 160,
    this.iconColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final double width;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: AppSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: iconColor ?? Theme.of(context).colorScheme.primary, size: 22),
              const SizedBox(height: 10),
              Text(
                value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                textDirection: TextDirection.ltr,
              ),
              const SizedBox(height: 2),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      );
}

class OwnerDetailRow extends StatelessWidget {
  const OwnerDetailRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.valueDirection,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final TextDirection? valueDirection;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OwnerMetadata(icon, label),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 19),
              child: Text(
                value,
                textDirection: valueDirection,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: valueColor,
                    ),
              ),
            ),
          ],
        ),
      );
}

class OwnerCheckBadge extends StatelessWidget {
  const OwnerCheckBadge({
    super.key,
    required this.label,
    required this.ok,
    required this.icon,
  });

  final String label;
  final bool ok;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final color = ok ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
        child: IconTheme(
          data: IconThemeData(color: color),
          child: OwnerMetadata(
            ok ? Icons.check_circle_rounded : icon,
            label,
          ),
        ),
      ),
    );
  }
}
