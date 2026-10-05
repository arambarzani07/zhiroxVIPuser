import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zhirox/services/a11_camera_coordinator.dart';
import 'package:zhirox/services/a11_camera_service.dart';

class A11CameraSetupScreen extends StatefulWidget {
  const A11CameraSetupScreen({
    super.key,
    required this.onCompleted,
    this.onLater,
  });

  final VoidCallback onCompleted;
  final VoidCallback? onLater;

  @override
  State<A11CameraSetupScreen> createState() => _A11CameraSetupScreenState();
}

class _A11CameraSetupScreenState extends State<A11CameraSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _host = TextEditingController(text: '192.168.1.16');
  final _port = TextEditingController(text: '10554');
  final _username = TextEditingController(text: 'admin');
  final _password = TextEditingController();
  final _path = TextEditingController(text: '/tcp/av0_0');

  bool _loading = true;
  bool _testing = false;
  bool _obscurePassword = true;
  String? _status;
  bool _statusOk = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final config = await A11CameraService.instance.loadConfig();
      _host.text = config.host;
      _port.text = config.port.toString();
      _username.text = config.username;
      _password.text = config.password;
      _path.text = config.path;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _username.dispose();
    _password.dispose();
    _path.dispose();
    super.dispose();
  }

  Future<void> _testAndSave() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _testing = true;
      _status = 'پەیوەندی بە کامێرا تاقی دەکرێتەوە...';
      _statusOk = false;
    });

    try {
      final camera = A11CameraService.instance;
      await camera.saveConfig(
        enabled: true,
        host: _host.text.trim(),
        port: int.parse(_port.text.trim()),
        username: _username.text.trim(),
        password: _password.text,
        path: _path.text.trim(),
      );

      // The mini camera may allow only one stable RTSP session. saveConfig
      // starts the rolling recorder, so pause it while the one-second probe is
      // running. The coordinator restarts it immediately after activation.
      await camera.stopBuffer();
      final ok = await camera.testConnection();
      if (!ok) {
        if (mounted) {
          setState(() {
            _status = 'پەیوەندی RTSP سەرکەوتوو نەبوو. Wi-Fi، IP و پاسۆرد بپشکنە.';
            _statusOk = false;
          });
        }
        return;
      }

      final admin = Supabase.instance.client.auth.currentUser;
      if (admin == null) {
        throw StateError('admin_session_missing');
      }
      await camera.activateProvider(admin.id);
      if (!await camera.isProviderActive(admin.id)) {
        throw StateError('a11_provider_activation_failed');
      }

      await A11CameraCoordinator.instance.onCameraConfigChanged();
      if (!mounted) return;
      setState(() {
        _status = 'کامێرا پەیوەست بوو ✅  H.264/RTSP ئامادەیە';
        _statusOk = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (mounted) widget.onCompleted();
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = 'هەڵە لە پەیوەستکردن: ${error.toString()}';
          _statusOk = false;
        });
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      filled: true,
      fillColor: Theme.of(context).colorScheme.surfaceContainerLowest,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('پەیوەستکردنی کامێرای A11'),
          centerTitle: true,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.videocam_rounded, size: 48),
                    SizedBox(height: 10),
                    Text(
                      'ZHIROX Direct Camera',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'A11 ڕاستەوخۆ لە Wi-Fi ـەوە دەبەسترێتە ZHIROX. NVR، PC یان VPS پێویست نییە. ١٥ چرکە پێش + ١٥ چرکە دوای مامەڵە هەڵدەگیرێت.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _host,
                      textDirection: TextDirection.ltr,
                      decoration: _decoration('IP کامێرا', Icons.router),
                      validator: (value) => value == null || value.trim().isEmpty
                          ? 'IP بنووسە'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _port,
                      keyboardType: TextInputType.number,
                      textDirection: TextDirection.ltr,
                      decoration: _decoration('RTSP Port', Icons.numbers),
                      validator: (value) {
                        final port = int.tryParse(value ?? '');
                        if (port == null || port < 1 || port > 65535) {
                          return 'Port دروست بنووسە';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _username,
                      textDirection: TextDirection.ltr,
                      decoration: _decoration('Username', Icons.person_outline),
                      validator: (value) => value == null || value.trim().isEmpty
                          ? 'Username بنووسە'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscurePassword,
                      textDirection: TextDirection.ltr,
                      decoration: _decoration('Password', Icons.lock_outline).copyWith(
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                        ),
                      ),
                      validator: (value) => value == null || value.isEmpty
                          ? 'Password بنووسە'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _path,
                      textDirection: TextDirection.ltr,
                      decoration: _decoration('RTSP Path', Icons.link),
                      validator: (value) => value == null || value.trim().isEmpty
                          ? 'Path بنووسە'
                          : null,
                    ),
                  ],
                ),
              ),
              if (_status != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _statusOk
                        ? Colors.green.withValues(alpha: 0.12)
                        : Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _status!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _statusOk ? Colors.green.shade700 : Colors.orange.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  onPressed: _testing ? null : _testAndSave,
                  icon: _testing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering),
                  label: Text(
                    _testing ? 'تاقیکردنەوە...' : 'تاقیکردنەوە و چالاککردن',
                  ),
                ),
              ),
              if (widget.onLater != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _testing ? null : widget.onLater,
                  child: const Text('دواتر'),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                'پاسۆردەکە تەنها لە Secure Storage ـی ئەم مۆبایلە هەڵدەگیرێت و بۆ GitHub نانێردرێت.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
