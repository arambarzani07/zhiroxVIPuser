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

  bool get _supportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkForUpdate());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_supportedPlatform) return;
    final last = _lastCheck;
    if (last == null || DateTime.now().difference(last) >= const Duration(minutes: 10)) {
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
        if (info == null || info.latestBuild == _dismissedBuild) {
          _update = null;
        } else {
          _update = info;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _lastCheck = DateTime.now();
        _error = null;
      });
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
    final border = isDark ? AppDarkColors.cardBorder : const Color(0xFFE4E7EC);
    final primaryText =
        isDark ? AppDarkColors.textPrimary : const Color(0xFF101828);
    final secondaryText =
        isDark ? AppDarkColors.textSecondary : const Color(0xFF667085);

    final card = Material(
      color: surface,
      elevation: info.mandatory ? 16 : 10,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 460),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.system_update_alt_rounded,
                    color: AppColors.primary,
                    size: 23,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Auto Update Center',
                        style: TextStyle(
                          color: primaryText,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'IPA ـی نوێ بۆ ZHIROX ${info.edition == 'owner' ? 'Owner' : 'User'} بەردەستە',
                        style: TextStyle(
                          color: secondaryText,
                          fontSize: 11.5,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!info.mandatory)
                  IconButton(
                    tooltip: 'دواتر',
                    onPressed: _dismiss,
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(13),
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
                  Icon(Icons.arrow_back_rounded, size: 18, color: secondaryText),
                  Expanded(
                    child: _buildVersionCell(
                      context,
                      'نوێ',
                      'v${info.version}+${info.latestBuild}',
                    ),
                  ),
                ],
              ),
            ),
            if (info.notes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  info.notes,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: secondaryText,
                    fontSize: 11.5,
                    height: 1.6,
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                if (!info.mandatory) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _opening ? null : _dismiss,
                      child: const Text('دواتر'),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  flex: 2,
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
                    label: Text(_opening ? 'دەکرێتەوە...' : 'دابەزاندنی IPA'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'لینکەکە ڕاستەوخۆ لە Safari دەکرێتەوە.',
              textAlign: TextAlign.center,
              style: TextStyle(color: secondaryText, fontSize: 9.5),
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
