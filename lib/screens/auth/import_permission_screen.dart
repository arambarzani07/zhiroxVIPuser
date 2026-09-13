import 'package:flutter/material.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';

class ImportPermissionScreen extends StatefulWidget {
  const ImportPermissionScreen({super.key});

  @override
  State<ImportPermissionScreen> createState() => _ImportPermissionScreenState();
}

class _ImportPermissionScreenState extends State<ImportPermissionScreen> {
  bool _loading = true;
  String? _error;
  final List<Map<String, dynamic>> _admins = [];
  final Set<String> _saving = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, dynamic>> _invoke(
    String action, {
    Map<String, dynamic> extra = const {},
  }) async {
    await PBService.ensureInitialized();
    final response = await PBService.client.functions.invoke(
      'import-permission-admin',
      body: {'action': action, ...extra},
    );
    if (response.data is! Map) throw Exception('invalid_response');
    final map = Map<String, dynamic>.from(response.data as Map);
    if (map['error'] != null) throw Exception('${map['error']}');
    return map;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _invoke('list');
      if (!mounted) return;
      final rows = (result['admins'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
      setState(() {
        _admins
          ..clear()
          ..addAll(rows);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'نەتوانرا لیستی بەڕێوەبەران باربکرێت.';
      });
    }
  }

  Future<void> _setPermission(Map<String, dynamic> admin, bool value) async {
    final id = '${admin['id'] ?? ''}';
    if (id.isEmpty || _saving.contains(id)) return;
    setState(() => _saving.add(id));
    try {
      await _invoke('set', extra: {'admin_id': id, 'allowed': value});
      if (!mounted) return;
      setState(() => admin['can_import_data'] = value);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('نەتوانرا مۆڵەتی Import بگۆڕدرێت.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('مۆڵەتی Import')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: const Text('دووبارە هەوڵ بدە')),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _admins.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Text(
                            'لێرە تەنها مۆڵەت دەدەیت. Import خۆی لە ئەپی بەڕێوەبەر (user-source) و لە tenant ـی هەمان مارکێت ئەنجام دەدرێت.',
                            style: TextStyle(height: 1.6),
                          ),
                        );
                      }
                      final admin = _admins[index - 1];
                      final id = '${admin['id'] ?? ''}';
                      final enabled = admin['can_import_data'] == true;
                      final saving = _saving.contains(id);
                      final active = admin['active'] == true;
                      final approved = admin['approved'] == true;
                      final marketName = '${admin['market_name'] ?? ''}'.trim();
                      final name = '${admin['name'] ?? ''}'.trim();
                      return Card(
                        color: isDark ? AppDarkColors.card : Colors.white,
                        child: SwitchListTile(
                          value: enabled,
                          onChanged: (!active || !approved || saving)
                              ? null
                              : (value) => _setPermission(admin, value),
                          secondary: CircleAvatar(
                            backgroundColor: enabled
                                ? AppColors.success.withValues(alpha: 0.12)
                                : AppColors.primary.withValues(alpha: 0.08),
                            child: Icon(
                              enabled ? Icons.move_to_inbox_rounded : Icons.lock_outline_rounded,
                              color: enabled ? AppColors.success : AppColors.primary,
                            ),
                          ),
                          title: Text(
                            marketName.isEmpty ? name : marketName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            enabled
                                ? 'Import کراوە — بەڕێوەبەر دەتوانێت داتای خۆی بگوازێتەوە'
                                : 'Import داخراوە',
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
