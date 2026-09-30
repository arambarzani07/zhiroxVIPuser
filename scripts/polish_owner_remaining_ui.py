from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AUTH = ROOT / 'lib' / 'screens' / 'auth'
DESIGN = ROOT / 'lib' / 'widgets' / 'app_design.dart'


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'missing expected pattern: {label}')
    return text.replace(old, new, 1)


# 1) Strengthen the shared Owner design language so every Owner route gets
# the same controls, expansion panels and state presentation.
design = DESIGN.read_text()
if 'class OwnerStatePanel extends StatelessWidget' not in design:
    marker = '''      progressIndicatorTheme: ProgressIndicatorThemeData(\n        color: scheme.primary,\n        linearTrackColor: scheme.surfaceContainer,\n      ),\n'''
    extra = marker + '''      checkboxTheme: CheckboxThemeData(\n        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),\n        side: BorderSide(color: scheme.outline),\n        fillColor: WidgetStateProperty.resolveWith((states) {\n          if (states.contains(WidgetState.selected)) return scheme.primary;\n          return Colors.transparent;\n        }),\n      ),\n      radioTheme: RadioThemeData(\n        fillColor: WidgetStateProperty.resolveWith((states) {\n          if (states.contains(WidgetState.selected)) return scheme.primary;\n          return scheme.onSurfaceVariant;\n        }),\n      ),\n      expansionTileTheme: ExpansionTileThemeData(\n        iconColor: scheme.primary,\n        collapsedIconColor: scheme.onSurfaceVariant,\n        textColor: scheme.onSurface,\n        collapsedTextColor: scheme.onSurface,\n        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),\n        childrenPadding: const EdgeInsets.only(bottom: 8),\n        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),\n        collapsedShape:\n            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),\n      ),\n      textButtonTheme: TextButtonThemeData(\n        style: TextButton.styleFrom(\n          foregroundColor: scheme.primary,\n          minimumSize: const Size(44, 44),\n          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),\n          textStyle: const TextStyle(\n            fontFamily: 'NotoKufiArabic',\n            fontWeight: FontWeight.w800,\n          ),\n        ),\n      ),\n      elevatedButtonTheme: ElevatedButtonThemeData(\n        style: ElevatedButton.styleFrom(\n          elevation: 0,\n          minimumSize: const Size(48, 52),\n          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),\n          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),\n          textStyle: const TextStyle(\n            fontFamily: 'NotoKufiArabic',\n            fontWeight: FontWeight.w800,\n          ),\n        ),\n      ),\n'''
    design = replace_once(design, marker, extra, 'owner control theme marker')

    design += r'''

class OwnerStatePanel extends StatelessWidget {
  const OwnerStatePanel({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.busy = false,
  });

  const OwnerStatePanel.loading({super.key})
      : icon = Icons.hourglass_top_rounded,
        title = 'چاوەڕوان بە…',
        message = 'زانیارییەکان لە سێرڤەرەوە نوێ دەکرێنەوە.',
        actionLabel = null,
        onAction = null,
        busy = true;

  const OwnerStatePanel.empty({
    super.key,
    this.title = 'هیچ زانیارییەک نییە',
    this.message,
    this.actionLabel,
    this.onAction,
  })  : icon = Icons.inbox_outlined,
        busy = false;

  const OwnerStatePanel.error({
    super.key,
    this.title = 'زانیارییەکان نەهاتن',
    this.message,
    this.actionLabel = 'دووبارە هەوڵ بدە',
    this.onAction,
  })  : icon = Icons.cloud_off_rounded,
        busy = false;

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: AppSurface(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: busy
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: scheme.primary,
                          ),
                        )
                      : Icon(icon, color: scheme.primary, size: 27),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                if (message != null && message!.trim().isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.6,
                        ),
                  ),
                ],
                if (onAction != null && actionLabel != null) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: onAction,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
'''
    DESIGN.write_text(design)

# 2) Make loading presentation identical across all Owner center screens.
files = sorted(AUTH.glob('owner_*_screen.dart'))
files += [AUTH / 'admin_management_screen.dart', AUTH / 'import_permission_screen.dart']
for path in files:
    if not path.exists():
        continue
    text = path.read_text()
    if "package:zhirox/widgets/app_design.dart" not in text:
        text = text.replace(
            "import 'package:flutter/material.dart';\n",
            "import 'package:flutter/material.dart';\nimport 'package:zhirox/widgets/app_design.dart';\n",
            1,
        )
    text = text.replace(
        'const Center(child: CircularProgressIndicator())',
        'const OwnerStatePanel.loading()',
    )
    path.write_text(text)

# 3) The markets screen still carried its pre-Owner hard-coded palette.
# Point it at the live Owner Theme without changing any account logic.
markets = AUTH / 'admin_management_screen.dart'
text = markets.read_text()
old = '''    final isDark = Theme.of(context).brightness == Brightness.dark;\n    final surface = isDark ? AppDarkColors.card : Colors.white;\n    final border = isDark ? AppDarkColors.cardBorder : const Color(0xFFEAECF0);\n    final textPrimary =\n        isDark ? AppDarkColors.textPrimary : const Color(0xFF1D2939);\n    final textSecondary =\n        isDark ? AppDarkColors.textSecondary : const Color(0xFF667085);\n\n    return Scaffold(\n      backgroundColor:\n          isDark ? AppDarkColors.background : const Color(0xFFF7F8FA),\n'''
new = '''    final theme = Theme.of(context);\n    final scheme = theme.colorScheme;\n    final isDark = theme.brightness == Brightness.dark;\n    final surface = scheme.surfaceContainerLowest;\n    final border = scheme.outlineVariant;\n    final textPrimary = scheme.onSurface;\n    final textSecondary = scheme.onSurfaceVariant;\n\n    return Scaffold(\n      backgroundColor: theme.scaffoldBackgroundColor,\n'''
if old in text:
    text = text.replace(old, new, 1)

text = text.replace(
    'backgroundColor: isDark ? AppDarkColors.surface : Colors.white,\n        foregroundColor: textPrimary,',
    'backgroundColor: theme.appBarTheme.backgroundColor,\n        foregroundColor: textPrimary,',
    1,
)
markets.write_text(text)

print(f'polished {len(files)} Owner UI files')
