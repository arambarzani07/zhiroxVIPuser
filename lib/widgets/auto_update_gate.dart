import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/screens/admin/intelligence_center_screen.dart';
import 'package:zhirox/services/app_update_service.dart';
import 'package:zhirox/utils/constants.dart';

class AutoUpdateGate extends StatefulWidget {
  const AutoUpdateGate({super.key, required this.child});

  final Widget child;

  @override
  State<AutoUpdateGate> createState() => _AutoUpdateGateState();
}

class _AutoUpdateGateState extends State<AutoUpdateGate>
    with WidgetsBindingObserver {
  AppUpdateInfo? _update;
  DateTime? _lastCheck;
  bool _checking = false;
  bool _opening = false;
  int? _dismissedBuild;
  String? _error;
  Timer? _periodicUpdateTimer;

  bool get _supportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkForUpdate());
    });
    _periodicUpdateTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (mounted && _supportedPlatform) unawaited(_checkForUpdate());
    });
  }

  @override
  void dispose() {
    _periodicUpdateTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_supportedPlatform) return;
    final last = _lastCheck;
    final mustRecheck = _update?.mandatory == true;
    if (mustRecheck ||
        last == null ||
        DateTime.now().difference(last) >= const Duration(minutes: 5)) {
      unawaited(_checkForUpdate());
    }
  }

  Future<void> _checkForUpdate() async {
    if (!_supportedPlatform ||
        AppUpdateService.currentBuild <= 0 ||
        _checking) {
      return;
    }

    _checking = true;
    try {
      final info = await AppUpdateService.checkForUpdate();
      if (!mounted) return;
      setState(() {
        _lastCheck = DateTime.now();
        _error = null;
        if (info == null ||
            (info.latestBuild == _dismissedBuild && !info.mandatory)) {
          _update = null;
        } else {
          _update = info;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _lastCheck = DateTime.now());
    } finally {
      _checking = false;
    }
  }

  Future<void> _openDownload() async {
    final info = _update;
    if (info == null || _opening) return;

    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final opened = await AppUpdateService.openDownload(info);
      if (!mounted) return;
      if (!opened) {
        setState(() => _error = 'نەتوانرا لینکی IPA لە Safari بکرێتەوە.');
      } else {
        // Re-check immediately when the user returns from Safari.
        _lastCheck = null;
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'نەتوانرا لینکی IPA لە Safari بکرێتەوە.');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _openIntelligenceCenter() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const IntelligenceCenterScreen()),
    );
  }

  void _dismiss() {
    final info = _update;
    if (info == null || info.mandatory) return;
    setState(() {
      _dismissedBuild = info.latestBuild;
      _update = null;
      _error = null;
    });
  }

  Widget _intelligenceButton() {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(12, 12, 12, 82),
      child: Align(
        alignment: Alignment.bottomRight,
        child: FloatingActionButton.small(
          heroTag: 'zhirox-intelligence-center',
          tooltip: 'ZHIROX Intelligence Center',
          onPressed: _openIntelligenceCenter,
          child: const Icon(Icons.auto_awesome_rounded),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canOpenIntelligence = auth.isLoggedIn &&
        auth.userRole == 'admin' &&
        !(auth.user?.getBoolValue('is_system_owner') ?? false);
    final info = _update;

    if (info == null) {
      if (!canOpenIntelligence) return widget.child;
      return Stack(
        fit: StackFit.expand,
        children: [widget.child, _intelligenceButton()],
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppDarkColors.card : Colors.white;
    final border =
        isDark ? AppDarkColors.cardBorder : const Color(0xFFE4E7EC);
    final primaryText =
        isDark ? AppDarkColors.textPrimary : const Color(0xFF101828);
    final secondaryText =
        isDark ? AppDarkColors.textSecondary : const Color(0xFF667085);
    final mutedSurface = isDark
        ? Colors.white.withValues(alpha: 0.045)
        : const Color(0xFFF8FAFC);

    final card = Material(
      color: surface,
      elevation: info.mandatory ? 14 : 8,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.36 : 0.12),
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 430),
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.system_update_alt_rounded,
                    color: AppColors.primary,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              info.isRollback
                                  ? 'گەڕاندنەوەی وەشان'
                                  : 'Auto Update Center',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: primaryText,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: (info.isRollback
                                      ? Colors.orange
                                      : AppColors.primary)
                                  .withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              info.isRollback ? 'پارێزراو' : 'نوێ',
                              style: TextStyle(
                                color: info.isRollback
                                    ? Colors.orange.shade700
                                    : AppColors.primary,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        info.isRollback
                            ? 'وەشانی نوێ ناسازگارە؛ گەڕانەوە پێویستە.'
                            : 'IPA ـی نوێ بۆ ZHIROX ${info.edition == 'owner' ? 'Owner' : 'User'} بەردەستە',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: secondaryText,
                          fontSize: 10.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 34,
                  height: 34,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    tooltip: 'پشکنینەوە',
                    onPressed: _checking ? null : _checkForUpdate,
                    icon: _checking
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded, size: 19),
                  ),
                ),
                if (!info.mandatory)
                  SizedBox(
                    width: 34,
                    height: 34,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      tooltip: 'دواتر',
                      onPressed: _dismiss,
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(
                  color: mutedSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: border.withValues(alpha: isDark ? 0.8 : 0.65),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildVersionCell(
                        context,
                        'ئێستا',
                        'Build ${AppUpdateService.currentBuild}',
                      ),
                    ),
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_forward_rounded,
                        size: 16,
                        color: AppColors.primary,
                      ),
                    ),
                    Expanded(
                      child: _buildVersionCell(
                        context,
                        info.isRollback ? 'پارێزراو' : 'نوێ',
                        'v${info.version}+${info.latestBuild}',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (info.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: mutedSurface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  info.notes,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: secondaryText,
                    fontSize: 10.5,
                    height: 1.45,
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 7),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: _opening ? null : _openDownload,
                icon: _opening
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.open_in_browser_rounded, size: 18),
                label: Text(
                  _opening
                      ? 'دەکرێتەوە...'
                      : info.isRollback
                          ? 'گەڕانەوە بۆ وەشانی پێشوو'
                          : 'دابەزاندنی IPA',
                ),
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            if (!info.mandatory) ...[
              const SizedBox(height: 3),
              TextButton(
                onPressed: _opening ? null : _dismiss,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                ),
                child: const Text('دواتر'),
              ),
            ],
            Text(
              'پشکنینی خۆکار هەر ٥ خولەک • دوای Safari دووبارە پشکنین دەکرێت.',
              textAlign: TextAlign.center,
              style: TextStyle(color: secondaryText, fontSize: 9),
            ),
          ],
        ),
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (info.mandatory)
          const ModalBarrier(
            dismissible: false,
            color: Color(0x66000000),
          ),
        SafeArea(
          minimum: const EdgeInsets.all(12),
          child: Align(
            alignment: info.mandatory ? Alignment.center : Alignment.topCenter,
            child: card,
          ),
        ),
        if (canOpenIntelligence && !info.mandatory) _intelligenceButton(),
      ],
    );
  }

  Widget _buildVersionCell(BuildContext context, String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isDark
                ? AppDarkColors.textSecondary
                : const Color(0xFF98A2B3),
            fontSize: 9.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          textDirection: TextDirection.ltr,
          style: TextStyle(
            color: isDark
                ? AppDarkColors.textPrimary
                : const Color(0xFF344054),
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}