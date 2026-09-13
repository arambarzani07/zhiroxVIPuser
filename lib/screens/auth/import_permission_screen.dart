import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await PBService.getAdminsPage(page: 1, perPage: 100);
      if (!mounted) return;
      setState(() {
        _admins
          ..clear()
          ..addAll((result['admins'] as List).cast<Map<String, dynamic>>());
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

  Future<void> _setPermission(RecordModel admin, bool value) async {
    if (_saving.contains(admin.id)) return;
    setState(() => _saving.add(admin.id));
    try {
      await PBService.ensureInitialized();
      final result = await PBService.client.rpc(
        'owner_set_admin_import_permission',
        params: {'p_admin_id': admin.id, 'p_allowed': value},
      );
      if (result != true) throw Exception('update_failed');
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('نەتوانرا مۆڵەتی Import بگۆڕدرێت.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving.remove(admin.id));
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
                      final row = _admins[index - 1];
                      final admin = row['admin'] as RecordModel;
                      final enabled = admin.getBoolValue('can_import_data');
                      final saving = _saving.contains(admin.id);
                      final active = admin.getBoolValue('active');
                      final approved = admin.getBoolValue('approved');
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
                            admin.getStringValue('market_name').isEmpty
                                ? admin.getStringValue('name')
                                : admin.getStringValue('market_name'),
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
