import 'package:flutter/material.dart';
import 'package:zhirox/features/customers/customer_directory_controller.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/widgets/app_design.dart';

class CustomerCenterHeader extends StatelessWidget {
  const CustomerCenterHeader({
    super.key,
    required this.title,
    required this.icon,
    required this.totalCount,
    required this.countLabel,
    required this.searchController,
    required this.onSearchChanged,
    required this.onClearSearch,
    this.canAdd = false,
    this.onAdd,
    this.showFilters = false,
    this.selectedFilter = 'all',
    this.onFilterSelected,
  });

  final String title;
  final IconData icon;
  final int totalCount;
  final String countLabel;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final bool canAdd;
  final VoidCallback? onAdd;
  final bool showFilters;
  final String selectedFilter;
  final ValueChanged<String>? onFilterSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primary,
            scheme.primary.withValues(alpha: 0.88),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(AppDesign.radiusMedium),
          bottomRight: Radius.circular(AppDesign.radiusMedium),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: Colors.white, size: 22),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 112),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '$totalCount $countLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                  if (canAdd && onAdd != null) ...[
                    const SizedBox(width: AppSpacing.xs),
                    Material(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(AppDesign.radiusSmall),
                      child: IconButton(
                        tooltip: 'زیادکردن',
                        onPressed: onAdd,
                        icon: const Icon(
                          Icons.person_add_alt_1_rounded,
                          color: Colors.white,
                          size: 21,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: searchController,
                onChanged: onSearchChanged,
                style: TextStyle(color: scheme.onSurface),
                decoration: InputDecoration(
                  hintText: 'گەڕان بە ناو یان ژمارە...',
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: scheme.primary,
                    size: 21,
                  ),
                  suffixIcon: searchController.text.isNotEmpty
                      ? IconButton(
                          tooltip: 'پاککردنەوە',
                          onPressed: onClearSearch,
                          icon: const Icon(Icons.close_rounded, size: 18),
                        )
                      : null,
                  fillColor: scheme.surfaceContainerLowest,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppDesign.radiusSmall),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.34),
                    ),
                  ),
                ),
              ),
              if (showFilters) ...[
                const SizedBox(height: AppSpacing.sm),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.tune_rounded,
                        color: Colors.white70,
                        size: 18,
                      ),
                      const SizedBox(width: 7),
                      ...CustomerDirectoryController.filterLabels.entries.map(
                        (entry) {
                          final selected = entry.key == selectedFilter;
                          return Padding(
                            padding: const EdgeInsetsDirectional.only(end: 7),
                            child: ChoiceChip(
                              label: Text(entry.value),
                              selected: selected,
                              onSelected: (_) => onFilterSelected?.call(entry.key),
                              showCheckmark: false,
                              selectedColor: Colors.white,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.14),
                              side: BorderSide(
                                color: Colors.white.withValues(
                                  alpha: selected ? 0.95 : 0.38,
                                ),
                              ),
                              labelStyle: TextStyle(
                                color: selected ? scheme.primary : Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                              ),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class CustomerInboxWarning extends StatelessWidget {
  const CustomerInboxWarning({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        0,
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(AppDesign.radiusSmall),
        border: Border.all(
          color: AppColors.warning.withValues(alpha: 0.32),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: AppColors.warning,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('هەوڵدانەوە'),
          ),
        ],
      ),
    );
  }
}

class CustomerCardAction {
  const CustomerCardAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
}

class CustomerDirectoryCard extends StatelessWidget {
  const CustomerDirectoryCard({
    super.key,
    required this.customerId,
    required this.name,
    required this.displayName,
    required this.phone,
    required this.isEmployee,
    required this.approved,
    required this.isPinned,
    required this.isVip,
    required this.unread,
    required this.timeLabel,
    required this.preview,
    required this.balance,
    required this.hasBalance,
    required this.balanceUnavailable,
    required this.openDebtCount,
    required this.canManage,
    required this.onTap,
    this.onLongPress,
    this.actions = const [],
  });

  final String customerId;
  final String name;
  final String displayName;
  final String phone;
  final bool isEmployee;
  final bool approved;
  final bool isPinned;
  final bool isVip;
  final bool unread;
  final String timeLabel;
  final String preview;
  final double balance;
  final bool hasBalance;
  final bool balanceUnavailable;
  final int openDebtCount;
  final bool canManage;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final List<CustomerCardAction> actions;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    final card = Container(
      key: ValueKey<String>('user-card-$customerId'),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
        border: Border.all(
          color: unread
              ? scheme.primary.withValues(alpha: 0.30)
              : scheme.outline.withValues(alpha: 0.75),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 13,
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 19,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14.5,
                              ),
                            ),
                          ),
                          if (isVip) ...[
                            const SizedBox(width: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Text(
                                'VIP',
                                style: TextStyle(
                                  color: Colors.amber.shade700,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                          if (isPinned) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.push_pin_rounded,
                              size: 14,
                              color: scheme.primary,
                            ),
                          ],
                          if (unread) ...[
                            const SizedBox(width: 6),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                          if (!isEmployee && timeLabel.isNotEmpty) ...[
                            const SizedBox(width: 7),
                            Text(
                              timeLabel,
                              textDirection: TextDirection.ltr,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight:
                                    unread ? FontWeight.w800 : FontWeight.w500,
                                color: unread
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                          if (isEmployee && approved)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'چالاک',
                                style: TextStyle(
                                  color: AppColors.success,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (isEmployee)
                        Text(
                          phone.isEmpty ? 'ژمارە مۆبایل نەدراوە' : phone,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        )
                      else ...[
                        Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: unread
                                ? scheme.onSurface
                                : scheme.onSurfaceVariant,
                            fontSize: 11,
                            fontWeight:
                                unread ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                balanceUnavailable
                                    ? 'ماوە: نەتوانرا باربکرێت'
                                    : hasBalance
                                        ? 'ماوە: ${_formatBalance(balance)}'
                                        : 'ماوە: ...',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: balanceUnavailable
                                      ? AppColors.warning
                                      : !hasBalance
                                          ? scheme.onSurfaceVariant
                                          : balance > 0
                                              ? AppColors.danger
                                              : AppColors.success,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (openDebtCount > 0) ...[
                              const SizedBox(width: 7),
                              Flexible(
                                child: Text(
                                  '$openDebtCount قەرزی کراوە',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (!canManage) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_left_rounded,
                    color: isDark
                        ? Colors.grey.shade600
                        : Colors.grey.shade400,
                    size: 22,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    final padded = Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: card,
    );

    if (!canManage || actions.isEmpty) return padded;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CustomerQuickSwipe(actions: actions, child: card),
    );
  }

  String _formatBalance(double value) {
    final raw = value.roundToDouble() == value
        ? value.toInt().toString()
        : value.toStringAsFixed(2);
    final parts = raw.split('.');
    final chars = parts.first.split('').reversed.toList();
    final groups = <String>[];
    for (var i = 0; i < chars.length; i += 3) {
      groups.add(chars.skip(i).take(3).toList().reversed.join());
    }
    final whole = groups.reversed.join(',');
    return parts.length == 1 ? '$whole د.ع' : '$whole.${parts[1]} د.ع';
  }
}

class CustomerQuickSwipe extends StatefulWidget {
  const CustomerQuickSwipe({
    super.key,
    required this.actions,
    required this.child,
  });

  final List<CustomerCardAction> actions;
  final Widget child;

  @override
  State<CustomerQuickSwipe> createState() => _CustomerQuickSwipeState();
}

class _CustomerQuickSwipeState extends State<CustomerQuickSwipe> {
  static _CustomerQuickSwipeState? _openedState;
  double _offset = 0;
  bool _dragging = false;

  void _close({bool clearRegistry = true}) {
    if (!mounted) return;
    setState(() {
      _dragging = false;
      _offset = 0;
    });
    if (clearRegistry && identical(_openedState, this)) {
      _openedState = null;
    }
  }

  void _claimOpenSlot() {
    final previous = _openedState;
    if (previous != null && !identical(previous, this)) {
      previous._close(clearRegistry: false);
    }
    _openedState = this;
  }

  @override
  void dispose() {
    if (identical(_openedState, this)) _openedState = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.actions.isEmpty) return widget.child;
    return LayoutBuilder(
      builder: (context, constraints) {
        final revealWidth =
            constraints.maxWidth < 340 ? constraints.maxWidth * 0.76 : 248.0;
        final actionWidth = revealWidth / widget.actions.length;
        final opacity = (_offset.abs() / 12).clamp(0.0, 1.0).toDouble();

        return ClipRRect(
          borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
          child: Stack(
            alignment: Alignment.centerRight,
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: opacity == 0,
                  child: Opacity(
                    opacity: opacity,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        width: revealWidth,
                        child: Row(
                          children: widget.actions.map((action) {
                            return SizedBox(
                              width: actionWidth,
                              child: Material(
                                color: action.color,
                                child: InkWell(
                                  onTap: () {
                                    _close();
                                    action.onTap();
                                  },
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          action.icon,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          action.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(growable: false),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: (_) {
                  if (_offset == 0) _claimOpenSlot();
                  setState(() => _dragging = true);
                },
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    _offset = (_offset + details.delta.dx)
                        .clamp(-revealWidth, 0.0)
                        .toDouble();
                  });
                },
                onHorizontalDragEnd: (_) {
                  final shouldOpen = _offset.abs() >= revealWidth * 0.24;
                  if (shouldOpen) {
                    _claimOpenSlot();
                  } else if (identical(_openedState, this)) {
                    _openedState = null;
                  }
                  setState(() {
                    _dragging = false;
                    _offset = shouldOpen ? -revealWidth : 0;
                  });
                },
                onHorizontalDragCancel: _close,
                child: AnimatedContainer(
                  duration: _dragging ? Duration.zero : AppMotion.fast,
                  curve: Curves.easeOutCubic,
                  transform: Matrix4.translationValues(_offset, 0, 0),
                  child: widget.child,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
