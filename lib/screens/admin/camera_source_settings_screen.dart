import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zhirox/services/a11_camera_coordinator.dart';
import 'package:zhirox/services/a11_camera_service.dart';

class CameraSourceSettingsScreen extends StatefulWidget {
  const CameraSourceSettingsScreen({super.key, this.onClose});
  final VoidCallback? onClose;

  @override
  State<CameraSourceSettingsScreen> createState() => _CameraSourceSettingsScreenState();
}

class _CameraSourceSettingsScreenState extends State<CameraSourceSettingsScreen> {
  final _host = TextEditingController(text: '192.168.1.16');
  final _port = TextEditingController(text: '10554');
  final _user = TextEditingController(text: 'admin');
  final _password = TextEditingController();
  final _path = TextEditingController(text: '/tcp/av0_0');
  bool _loading = true;
  bool _working = false;
  String? _marketId;
  String? _provider;
  String? _message;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _password.dispose();
    _path.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return;
      final profile = await client
          .from('profiles')
          .select('id,role,admin_id')
          .eq('id', user.id)
          .single();
      final marketId = profile['role'] == 'admin'
          ? profile['id']?.toString()
          : profile['admin_id']?.toString();
      if (marketId == null || marketId.isEmpty) return;
      final config = await A11CameraService.instance.loadConfig();
      final provider = await A11CameraService.instance.currentProvider(marketId);
      if (!mounted) return;
      setState(() {
        _marketId = marketId;
        _provider = provider;
        _host.text = config.host;
        _port.text = config.port.toString();
        _user.text = config.username;
        _path.text = config.path;
        _password.text = config.password;
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'نەتوانرا ڕێکخستنەکان بخوێندرێنەوە: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectHikvision() async {
    final marketId = _marketId;
    if (marketId == null || _working) return;
    setState(() { _working = true; _message = null; });
    try {
      await A11CameraService.instance.setProvider(marketId, 'local_gateway');
      if (mounted) setState(() {
        _provider = 'local_gateway';
        _message = 'Hikvision وەک سەرچاوەی سەرەکی هەڵبژێردرا ✅';
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'هەڵە: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _saveAndSelectA11() async {
    final marketId = _marketId;
    if (marketId == null || _working) return;
    final port = int.tryParse(_port.text.trim());
    if (_password.text.isEmpty || port == null) {
      setState(() => _message = 'پاسۆرد و Port بە دروستی بنووسە.');
      return;
    }
    setState(() { _working = true; _message = 'پەیوەندی A11 تاقی دەکرێتەوە…'; });
    try {
      await A11CameraService.instance.saveConfig(
        host: _host.text.trim(),
        port: port,
        username: _user.text.trim(),
        password: _password.text,
        path: _path.text.trim(),
      );
      final ok = await A11CameraService.instance.testConnection();
      if (!ok) throw StateError('RTSP connection failed');
      await A11CameraService.instance.setProvider(marketId, 'a11_local_rtsp');
      unawaited(A11CameraCoordinator.instance.start());
      if (mounted) setState(() {
        _provider = 'a11_local_rtsp';
        _message = 'A11 پەیوەست بوو و وەک سەرچاوەی سەرەکی هەڵبژێردرا ✅';
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'A11 چالاک نەکرا: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('سەرچاوەی ڤیدیۆ'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: widget.onClose ?? () => Navigator.maybePop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(18),
              children: [
                _sourceCard(
                  title: 'Hikvision',
                  subtitle: 'NVR / Local Gateway ـی ئێستا',
                  selected: _provider == 'local_gateway',
                  icon: Icons.videocam_outlined,
                  onTap: _selectHikvision,
                ),
                const SizedBox(height: 12),
                _sourceCard(
                  title: 'A11 Direct',
                  subtitle: 'RTSP ڕاستەوخۆ لە هەمان Wi‑Fi',
                  selected: _provider == 'a11_local_rtsp',
                  icon: Icons.camera_indoor_outlined,
                  onTap: null,
                ),
                const SizedBox(height: 18),
                const Text('ڕێکخستنی A11', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                const SizedBox(height: 12),
                TextField(controller: _host, decoration: const InputDecoration(labelText: 'IP / Host')),
                const SizedBox(height: 10),
                TextField(controller: _port, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Port')),
                const SizedBox(height: 10),
                TextField(controller: _user, decoration: const InputDecoration(labelText: 'Username')),
                const SizedBox(height: 10),
                TextField(
                  controller: _password,
                  obscureText: _obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(controller: _path, decoration: const InputDecoration(labelText: 'RTSP Path')),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _working ? null : _saveAndSelectA11,
                  icon: const Icon(Icons.link),
                  label: const Text('تاقیکردنەوە و هەڵبژاردنی A11'),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 14),
                  Text(_message!, textAlign: TextAlign.center),
                ],
                const SizedBox(height: 20),
                const Text(
                  'هەردوو سیستەمەکە دەمێنن. گۆڕینی سەرچاوە تەنها مامەڵە نوێکان دەگۆڕێت؛ ڤیدیۆ و داتای پێشوو ناسڕێتەوە.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, height: 1.6),
                ),
              ],
            ),
    );
  }

  Widget _sourceCard({
    required String title,
    required String subtitle,
    required bool selected,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        onTap: _working ? null : onTap,
        leading: Icon(icon, color: selected ? scheme.primary : null),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: selected
            ? Icon(Icons.check_circle, color: scheme.primary)
            : const Icon(Icons.radio_button_unchecked),
      ),
    );
  }
}
