import 'package:flutter/material.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/widgets/app_design.dart';

enum AppAsyncState { loading, error, empty, ready }

class AppAsyncStateView extends StatelessWidget {
  const AppAsyncStateView({
    super.key,
    required this.state,
    required this.child,
    this.message,
    this.onRetry,
    this.loadingLabel = 'زانیارییەکان وەردەگیرێن...',
    this.emptyTitle = 'هیچ زانیارییەک نییە',
    this.emptyMessage,
    this.emptyIcon = Icons.inbox_outlined,
  });

  final AppAsyncState state;
  final Widget child;
  final String? message;
  final Future<void> Function()? onRetry;
  final String loadingLabel;
  final String emptyTitle;
  final String? emptyMessage;
  final IconData emptyIcon;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case AppAsyncState.ready:
        return child;
      case AppAsyncState.loading:
        return _StateScaffold(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                loadingLabel,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      case AppAsyncState.error:
        return _StateScaffold(
          scrollable: true,
          onRefresh: onRetry,
          child: _MessageState(
            icon: Icons.cloud_off_rounded,
            iconColor: AppColors.warning,
            title: 'نەتوانرا زانیارییەکان وەربگیرێن',
            message: message ?? 'دووبارە هەوڵ بدە.',
            actionLabel: onRetry == null ? null : 'دووبارە هەوڵ بدە',
            onAction: onRetry,
          ),
        );
      case AppAsyncState.empty:
        return _StateScaffold(
          child: _MessageState(
            icon: emptyIcon,
            iconColor: Theme.of(context).colorScheme.primary,
            title: emptyTitle,
            message: emptyMessage,
          ),
        );
    }
  }
}

class _StateScaffold extends StatelessWidget {
  const _StateScaffold({
    required this.child,
    this.scrollable = false,
    this.onRefresh,
  });

  final Widget child;
  final bool scrollable;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    if (!scrollable) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: child,
        ),
      );
    }

    final content = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const SizedBox(height: 96),
        child,
      ],
    );

    if (onRefresh == null) return content;
    return RefreshIndicator(onRefresh: onRefresh!, child: content);
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? message;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 28, color: iconColor),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          if (message?.trim().isNotEmpty == true) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                height: 1.7,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: () => onAction!(),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
