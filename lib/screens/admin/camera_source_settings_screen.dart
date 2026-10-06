import 'package:flutter/material.dart';
import 'package:zhirox/services/camera_source_service.dart';

class CameraSourceSettingsScreen extends StatefulWidget {
  const CameraSourceSettingsScreen({
    super.key,
    required this.onClose,
    required this.onConfigureA11,
  });

  final VoidCallback onClose;
  final VoidCallback onConfigureA11;

  @override
  State<CameraSourceSettingsScreen> createState() =>
      _CameraSourceSettingsScreenState();
}

class _CameraSourceSettingsScreenState
    extends State<CameraSourceSettingsScreen> {
  CameraSourceState? _state;
  bool _loading = true;
  bool _changing = false;
  String? _message;
  bool _messageOk = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final state = await CameraSourceService.instance.loadState();
      if (!mounted) return;
      setState(() {
        _state = state;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = 'هەڵە لە خوێندنەوەی ڕێکخستنەکان: $error';
        _messageOk = false;
      });
    }
  }

  Future<void> _select(String provider) async {
    if (_changing) return;
    setState(() {
      _changing = true;
      _message = null;
    });

    try {
      if (provider == CameraSourceService.hikvision) {
        await CameraSourceService.instance.selectHikvision();
      } else {
        await CameraSourceService.instance.selectA11();
      }
      final next = await CameraSourceService.instance.loadState();
      if (!mounted) return;
      setState(() {
        _state = next;
        _message = provider == CameraSourceService.hikvision
            ? 'Hikvision وەک سەرچاوەی سەرەکی هەڵبژێردرا ✅'
            : 'A11 Direct وەک سەرچاوەی سەرەکی هەڵبژێردرا ✅';
        _messageOk = true;
      });
    } catch (error) {
      if (!mounted) return;
      final text = error.toString();
      setState(() {
        _messageOk = false;
        _message = text.contains('a11_not_configured')
            ? 'A11 هێشتا ڕێکنەخراوە. سەرەتا ڕێکخستنی A11 بکە.'
            : text.contains('a11_rtsp_unreachable')
                ? 'A11 لە RTSP وەڵام نادات. Wi-Fi و کامێرا بپشکنە.'
                : 'گۆڕینی سەرچاوە سەرکەوتوو نەبوو: $error';
      });
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  Widget _sourceCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: selected ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: selected
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, size: 30, color: scheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (selected)
                          const Icon(Icons.check_circle, color: Colors.green),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(subtitle),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('سەرچاوەی ڤیدیۆ'),
          leading: IconButton(
            onPressed: widget.onClose,
            icon: const Icon(Icons.close),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  const Text(
                    'هەردوو سیستەمەکە لە ZHIROX دەمێنن. تەنها دیاری دەکەیت مامەڵە نوێکان لە کام سەرچاوە ڤیدیۆ وەربگرن.',
                    style: TextStyle(fontSize: 15, height: 1.6),
                  ),
                  const SizedBox(height: 18),
                  _sourceCard(
                    title: 'Hikvision',
                    subtitle:
                        'NVR / Local Gateway. هەموو ڕێکخستن و ڤیدیۆ کۆنەکان دەمێنن.',
                    icon: Icons.videocam_rounded,
                    selected: state?.isHikvision ?? false,
                    onTap: _changing
                        ? null
                        : () => _select(CameraSourceService.hikvision),
                  ),
                  const SizedBox(height: 12),
                  _sourceCard(
                    title: 'A11 Direct',
                    subtitle: state?.a11Configured == true
                        ? 'RTSP ڕاستەوخۆ لە Wi-Fi ـەوە؛ بێ NVR و بێ PC.'
                        : 'A11 هێشتا ڕێکنەخراوە.',
                    icon: Icons.camera_indoor_rounded,
                    selected: state?.isA11 ?? false,
                    onTap: _changing
                        ? null
                        : state?.a11Configured == true
                            ? () => _select(CameraSourceService.a11)
                            : widget.onConfigureA11,
                  ),
                  if (state?.a11Configured != true) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _changing ? null : widget.onConfigureA11,
                      icon: const Icon(Icons.settings_input_antenna),
                      label: const Text('ڕێکخستنی A11'),
                    ),
                  ],
                  if (_changing) ...[
                    const SizedBox(height: 18),
                    const Center(child: CircularProgressIndicator()),
                  ],
                  if (_message != null) ...[
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _messageOk
                            ? Colors.green.withValues(alpha: 0.12)
                            : Colors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        _message!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _messageOk
                              ? Colors.green.shade800
                              : Colors.orange.shade900,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  const Text(
                    'گۆڕینی سەرچاوە هیچ MP4، evidence، مامەڵە یان داتای کۆن ناسڕێتەوە.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
      ),
    );
  }
}
