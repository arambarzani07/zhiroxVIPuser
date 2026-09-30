import 'package:flutter/material.dart';
import 'package:zhirox/screens/auth/owner_plan_market_control_screen.dart';
import 'package:zhirox/services/owner_permission_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/widgets/app_design.dart';

class OwnerMarketPermissionMatrixScreen extends StatefulWidget {
  const OwnerMarketPermissionMatrixScreen({super.key});

  @override
  State<OwnerMarketPermissionMatrixScreen> createState() =>
      _OwnerMarketPermissionMatrixScreenState();
}

class _OwnerMarketPermissionMatrixScreenState
    extends State<OwnerMarketPermissionMatrixScreen> {
  List<OwnerMarketSummary> _markets = const [];
  OwnerMarketPermissionMatrix? _matrix;
  String? _selectedMarketId;
  final Map<String, String> _draftModes = <String, String>{};
  String _query = '';
  bool _editableOnly = true;
  bool _loadingMarkets = true;
  bool _loadingMatrix = false;
  bool _saving = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadMarkets();
  }

  Map<String, String> get _changes {
    final matrix = _matrix;
    if (matrix == null) return const <String, String>{};
    final out = <String, String>{};
    for (final permission in matrix.permissions) {
      if (!permission.applicable) continue;
      final next = _draftModes[permission.key] ?? permission.mode;
      if (next != permission.mode) out[permission.key] = next;
    }
    return out;
  }

  Future<void> _loadMarkets() async {
    setState(() {
      _loadingMarkets = true;
      _error = null;
    });
    try {
      final markets = await OwnerPermissionService.fetchMarkets();
      if (!mounted) return;
      setState(() {
        _markets = markets;
        _selectedMarketId = markets.isEmpty ? null : markets.first.id;
        _loadingMarkets = false;
      });
      if (markets.isNotEmpty) await _loadMatrix(markets.first.id);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingMarkets = false;
        _error = error;
      });
    }
  }

  Future<void> _loadMatrix(String adminId) async {
    setState(() {
      _loadingMatrix = true;
      _error = null;
      _selectedMarketId = adminId;
    });
    try {
      final matrix = await OwnerPermissionService.fetchMarketMatrix(adminId);
      if (!mounted) return;
      setState(() {
        _matrix = matrix;
        _draftModes
          ..clear()
          ..addEntries(
            matrix.permissions
                .where((permission) => permission.applicable)
                .map((permission) => MapEntry(permission.key, permission.mode)),
          );
        _loadingMatrix = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingMatrix = false;
        _error = error;
      });
    }
  }

  Future<void> _selectMarket(String id) async {
    if (id == _selectedMarketId) return;
    if (_changes.isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('گۆڕانکاری هەڵنەگیراوە'),
          content: const Text(
            'گۆڕانکارییەکانی ئەم مارکێتە هێشتا پاشەکەوت نەکراون. لەبەریان بگریت؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('نەخێر'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('بەڵێ'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    await _loadMatrix(id);
  }

  void _setMode(OwnerMarketPermissionEntry permission, String mode) {
    if (!permission.applicable || _saving) return;
    setState(() => _draftModes[permission.key] = mode);
  }

  void _setAllEditable(String mode) {
    final matrix = _matrix;
    if (matrix == null || _saving) return;
    setState(() {
      for (final permission in matrix.permissions) {
        if (permission.applicable) _draftModes[permission.key] = mode;
      }
    });
  }

  Future<void> _save() async {
    final matrix = _matrix;
    final adminId = _selectedMarketId;
    final changes = _changes;
    if (matrix == null || adminId == null || changes.isEmpty || _saving) return;

    final changedKeys = changes.keys.toSet();
    final needsReason = matrix.permissions.any(
      (permission) =>
          changedKeys.contains(permission.key) &&
          (permission.requiresReason || permission.riskLevel >= 3),
    );
    String reason = '';
    if (needsReason) {
      final result = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _ReasonDialog(),
      );
      if (result == null || !mounted) return;
      reason = result;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await OwnerPermissionService.saveMarketMatrix(
        adminId: adminId,
        changes: changes,
        reason: reason,
      );
      if (!mounted) return;
      setState(() {
        _matrix = updated;
        _draftModes
          ..clear()
          ..addEntries(
            updated.permissions
                .where((permission) => permission.applicable)
                .map((permission) => MapEntry(permission.key, permission.mode)),
          );
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${changes.length} گۆڕانکاری پاشەکەوت کرا')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final matrix = _matrix;
    final changes = _changes;

    return Scaffold(
      appBar: AppBar(
        title: const Text('دەسەڵات بەپێی مارکێت'),
        actions: [
          IconButton(
            tooltip: 'پلان و سنوور',
            onPressed: _saving
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const OwnerPlanMarketControlScreen(),
                      ),
                    ),
            icon: const Icon(Icons.layers_rounded),
          ),
          IconButton(
            tooltip: 'نوێکردنەوە',
            onPressed: _loadingMatrix || _selectedMarketId == null
                ? null
                : () => _loadMatrix(_selectedMarketId!),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      bottomNavigationBar: matrix == null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton.icon(
                onPressed: changes.isEmpty || _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(
                  changes.isEmpty
                      ? 'هیچ گۆڕانکارییەک نییە'
                      : 'پاشەکەوتکردنی ${changes.length} گۆڕانکاری',
                ),
              ),
            ),
      body: _loadingMarkets
          ? const Center(child: CircularProgressIndicator())
          : _markets.isEmpty
              ? const Center(child: Text('هیچ مارکێتێک بەردەست نییە'))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedMarketId,
                        decoration: const InputDecoration(
                          labelText: 'مارکێت هەڵبژێرە',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.storefront_rounded),
                        ),
                        items: _markets
                            .map(
                              (market) => DropdownMenuItem<String>(
                                value: market.id,
                                child: Text(
                                  '${market.displayName} — ${market.adminName}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: _saving
                            ? null
                            : (value) {
                                if (value != null) _selectMarket(value);
                              },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _saving
                              ? null
                              : () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const OwnerPlanMarketControlScreen(),
                                    ),
                                  ),
                          icon: const Icon(Icons.layers_rounded),
                          label: const Text(
                            'پلان + سنووری کارمەند / کڕیار / ئامێر',
                          ),
                        ),
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Material(
                          color: Theme.of(context)
                              .colorScheme
                              .errorContainer
                              .withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(12),
                          child: ListTile(
                            leading: const Icon(Icons.error_outline_rounded),
                            title: const Text('هەڵەیەک ڕوویدا'),
                            subtitle: Text(_error.toString()),
                          ),
                        ),
                      ),
                    if (_loadingMatrix)
                      const Expanded(
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (matrix != null)
                      Expanded(child: _buildMatrix(context, matrix)),
                  ],
                ),
    );
  }

  Widget _buildMatrix(
    BuildContext context,
    OwnerMarketPermissionMatrix matrix,
  ) {
    final query = _query.trim().toLowerCase();
    final filtered = matrix.permissions.where((permission) {
      if (_editableOnly && !permission.applicable) return false;
      if (query.isEmpty) return true;
      return permission.label.toLowerCase().contains(query) ||
          permission.key.toLowerCase().contains(query) ||
          permission.groupLabel.toLowerCase().contains(query);
    }).toList(growable: false);

    final groups = <String, List<OwnerMarketPermissionEntry>>{};
    for (final permission in filtered) {
      groups.putIfAbsent(permission.groupLabel, () => []).add(permission);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
      children: [
        AppSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: AppColors.primarySoft,
                    child: Icon(Icons.rule_folder_rounded, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          matrix.market.displayName,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '${matrix.count} کۆی دەسەڵات • ${matrix.editableCount} بۆ مارکێت/بەڕێوەبەر',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Inherit = یاسای گشتی • Allow = ڕێگەپێدان بۆ ئەم مارکێتە • Deny = قەدەغەکردن تەنها بۆ ئەم مارکێتە.',
                style: TextStyle(height: 1.5),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _saving ? null : () => _setAllEditable('inherit'),
                    child: const Text('هەمووی Inherit'),
                  ),
                  OutlinedButton(
                    onPressed: _saving ? null : () => _setAllEditable('allow'),
                    child: const Text('Allow هەموو'),
                  ),
                  OutlinedButton(
                    onPressed: _saving ? null : () => _setAllEditable('deny'),
                    child: const Text('Deny هەموو'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            hintText: 'گەڕان بە ناو یان permission key',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _editableOnly,
          onChanged: (value) => setState(() => _editableOnly = value),
          title: const Text('تەنها دەسەڵاتەکانی مارکێت پیشان بدە'),
          subtitle: const Text('platform-only ـەکان قوفڵن'),
        ),
        if (filtered.isEmpty)
          const AppSurface(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('هیچ دەسەڵاتێک نەدۆزرایەوە')),
            ),
          )
        else
          ...groups.entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppSurface(
                padding: EdgeInsets.zero,
                child: ExpansionTile(
                  title: Text(
                    entry.key,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text('${entry.value.length} دەسەڵات'),
                  children: [
                    for (var i = 0; i < entry.value.length; i++) ...[
                      _PermissionTile(
                        permission: entry.value[i],
                        mode: _draftModes[entry.value[i].key] ??
                            entry.value[i].mode,
                        changed: (_draftModes[entry.value[i].key] ??
                                entry.value[i].mode) !=
                            entry.value[i].mode,
                        enabled: !_saving,
                        onChanged: (mode) => _setMode(entry.value[i], mode),
                      ),
                      if (i != entry.value.length - 1) const Divider(height: 1),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.permission,
    required this.mode,
    required this.changed,
    required this.enabled,
    required this.onChanged,
  });

  final OwnerMarketPermissionEntry permission;
  final String mode;
  final bool changed;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: _riskColor(permission.riskLevel, context)
            .withValues(alpha: 0.12),
        child: Text(
          '${permission.riskLevel}',
          style: TextStyle(
            color: _riskColor(permission.riskLevel, context),
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              permission.label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (changed)
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.orange,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
      subtitle: Text(
        permission.applicable
            ? '${permission.scopeType == 'admin' ? 'بەڕێوەبەر' : 'مارکێت'} • ${permission.key}'
            : 'Platform-only • ${permission.key}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: permission.applicable
          ? DropdownButton<String>(
              value: mode,
              onChanged: enabled
                  ? (value) {
                      if (value != null) onChanged(value);
                    }
                  : null,
              items: const [
                DropdownMenuItem(value: 'inherit', child: Text('Inherit')),
                DropdownMenuItem(value: 'allow', child: Text('Allow')),
                DropdownMenuItem(value: 'deny', child: Text('Deny')),
              ],
            )
          : const Chip(label: Text('پلاتفۆرم')),
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog();

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.length < 4) {
      setState(() => _error = 'هۆکارەکە لانیکەم ٤ پیت بێت');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('هۆکاری گۆڕانکاری'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 2,
        maxLines: 4,
        decoration: InputDecoration(
          hintText: 'بۆچی ئەم دەسەڵاتە دەگۆڕیت؟',
          errorText: _error,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('پاشگەزبوونەوە'),
        ),
        FilledButton(onPressed: _submit, child: const Text('بەردەوام')),
      ],
    );
  }
}

Color _riskColor(int level, BuildContext context) {
  switch (level) {
    case 1:
      return Colors.green;
    case 2:
      return Colors.blue;
    case 3:
      return Colors.orange;
    case 4:
      return Theme.of(context).colorScheme.error;
    default:
      return Theme.of(context).colorScheme.onSurfaceVariant;
  }
}
