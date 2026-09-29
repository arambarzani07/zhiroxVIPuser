import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zhirox/services/advanced_customer_service.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:zhirox/widgets/app_design.dart';

class CustomerAdvancedCenterScreen extends StatefulWidget {
  const CustomerAdvancedCenterScreen({
    super.key,
    required this.customerId,
  });

  final String customerId;

  @override
  State<CustomerAdvancedCenterScreen> createState() =>
      _CustomerAdvancedCenterScreenState();
}

class _CustomerAdvancedCenterScreenState
    extends State<CustomerAdvancedCenterScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = const {};
  Map<String, dynamic> _assets = const {};
  List<Map<String, dynamic>> _groupCatalog = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Map<String, dynamic> _map(dynamic raw) =>
      raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

  List<Map<String, dynamic>> _maps(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  int _int(dynamic value) => (value as num?)?.toInt() ??
      int.tryParse('${value ?? 0}') ??
      0;

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait<dynamic>([
        AdvancedCustomerService.getCustomerCenter(widget.customerId),
        AdvancedCustomerService.getAssets(widget.customerId),
        AdvancedCustomerService.getGroups(),
      ]);
      if (!mounted) return;
      setState(() {
        _data = Map<String, dynamic>.from(values[0] as Map);
        _assets = Map<String, dynamic>.from(values[1] as Map);
        _groupCatalog = List<Map<String, dynamic>>.from(values[2] as List);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppHelpers.backendErrorMessage(
          e,
          fallback: 'نەتوانرا ناوەندی پێشکەوتووی کڕیار باربکرێت.',
        );
      });
    }
  }

  String _nextActionLabel(String key) {
    return switch (key) {
      'credit_blocked' => 'قەرزی نوێ ڕابگرە',
      'credit_frozen' => 'قوفڵی قەرز بپشکنە',
      'follow_up_overdue' => 'بەدواداچوونی قەرزی دواکەوتوو',
      'request_payment_plan' => 'پلانی پارەدانەوە پێشنیار بکە',
      'eligible_for_vip' => 'VIP هەڵبسەنگێنە',
      _ => 'پەیوەندی باش بپارێزە',
    };
  }

  Future<void> _editRules() async {
    final rules = _map(_data['rules']);
    final profile = _map(_data['profile']);
    var frozen = rules['credit_frozen'] == true;
    var watch = rules['watch_status']?.toString() ?? 'normal';
    var autoVip = rules['auto_vip_enabled'] == true;
    final grace = TextEditingController(text: '${_int(rules['grace_days'])}');
    final maxDays = TextEditingController(
      text: rules['max_debt_days'] == null ? '' : '${rules['max_debt_days']}',
    );
    final manager = TextEditingController(
      text: rules['manager_approval_amount'] == null
          ? ''
          : '${rules['manager_approval_amount']}',
    );
    final twoStep = TextEditingController(
      text: rules['two_step_approval_amount'] == null
          ? ''
          : '${rules['two_step_approval_amount']}',
    );
    final autoMonths = TextEditingController(
      text: '${_int(rules['auto_vip_months']) == 0 ? 6 : _int(rules['auto_vip_months'])}',
    );
    DateTime? vipExpiry = DateTime.tryParse(
      profile['vip_expires_at']?.toString() ?? '',
    );

    final save = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, update) => Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'یاسا و پاراستنی قەرز',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Credit Freeze'),
                  subtitle: const Text('قەرزی نوێ کاتیی قوفڵ بکە'),
                  value: frozen,
                  onChanged: (v) => update(() => frozen = v),
                ),
                DropdownButtonFormField<String>(
                  initialValue: watch,
                  decoration: const InputDecoration(labelText: 'دۆخی چاودێری'),
                  items: const [
                    DropdownMenuItem(value: 'normal', child: Text('ئاسایی')),
                    DropdownMenuItem(value: 'watchlist', child: Text('Watchlist')),
                    DropdownMenuItem(value: 'blacklist', child: Text('Blacklist')),
                  ],
                  onChanged: (v) => update(() => watch = v ?? 'normal'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: grace,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Grace Period / ڕۆژی مۆڵەت',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: maxDays,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'زۆرترین ماوەی قەرز بە ڕۆژ',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: manager,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'بڕی پێویست بە پەسەندی بەڕێوەبەر',
                    suffixText: 'د.ع',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: twoStep,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'بڕی پێویست بە پەسەندی دوو کەس',
                    suffixText: 'د.ع',
                  ),
                ),
                const SizedBox(height: 4),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Automatic VIP'),
                  subtitle: const Text('بەپێی مێژووی پارەدانەوە خۆکار VIP بکە'),
                  value: autoVip,
                  onChanged: (v) => update(() => autoVip = v),
                ),
                TextField(
                  controller: autoMonths,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'ماوەی VIP بە مانگ',
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: sheetContext,
                      initialDate: vipExpiry ?? now.add(const Duration(days: 180)),
                      firstDate: now,
                      lastDate: DateTime(now.year + 10),
                    );
                    if (picked != null) update(() => vipExpiry = picked);
                  },
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                    vipExpiry == null
                        ? 'VIP Expiry دیاری بکە'
                        : 'VIP تا ${DateFormat('yyyy/MM/dd').format(vipExpiry!)}',
                  ),
                ),
                if (vipExpiry != null)
                  TextButton(
                    onPressed: () => update(() => vipExpiry = null),
                    child: const Text('لابردنی VIP Expiry'),
                  ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.pop(sheetContext, true),
                  child: const Text('پاشەکەوتکردن'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (save != true || !mounted) {
      grace.dispose();
      maxDays.dispose();
      manager.dispose();
      twoStep.dispose();
      autoMonths.dispose();
      return;
    }

    try {
      await AdvancedCustomerService.saveRules(
        customerId: widget.customerId,
        creditFrozen: frozen,
        watchStatus: watch,
        graceDays: int.tryParse(grace.text) ?? 0,
        maxDebtDays: int.tryParse(maxDays.text),
        managerApprovalAmount: double.tryParse(manager.text),
        twoStepApprovalAmount: double.tryParse(twoStep.text),
        autoVipEnabled: autoVip,
        autoVipMonths: int.tryParse(autoMonths.text) ?? 6,
        vipExpiresAt: vipExpiry,
      );
      if (autoVip) {
        await AdvancedCustomerService.refreshAutoVip(widget.customerId);
      }
      if (mounted) {
        AppHelpers.showSnackBar(context, 'یاساکانی کڕیار پاشەکەوت کران');
        await _load();
      }
    } catch (e) {
      if (mounted) {
        AppHelpers.showSnackBar(
          context,
          AppHelpers.backendErrorMessage(e, fallback: 'پاشەکەوتکردن سەرکەوتوو نەبوو.'),
          isError: true,
        );
      }
    } finally {
      grace.dispose();
      maxDays.dispose();
      manager.dispose();
      twoStep.dispose();
      autoMonths.dispose();
    }
  }

  Future<void> _editGroups() async {
    final current = _maps(_data['groups']).map((e) => e['id']?.toString() ?? '').toSet();
    final selected = <String>{...current};
    final result = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, update) => Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.68,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('گروپەکانی کڕیار',
                          style: Theme.of(sheetContext).textTheme.titleLarge),
                    ),
                    IconButton(
                      tooltip: 'گروپی نوێ',
                      onPressed: () async {
                        final controller = TextEditingController();
                        final name = await showDialog<String>(
                          context: sheetContext,
                          builder: (d) => AlertDialog(
                            title: const Text('گروپی نوێ'),
                            content: TextField(
                              controller: controller,
                              decoration: const InputDecoration(labelText: 'ناوی گروپ'),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(d),
                                child: const Text('پاشگەزبوونەوە'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(d, controller.text.trim()),
                                child: const Text('زیادکردن'),
                              ),
                            ],
                          ),
                        );
                        controller.dispose();
                        if (name != null && name.isNotEmpty) {
                          await AdvancedCustomerService.createGroup(name);
                          final groups = await AdvancedCustomerService.getGroups();
                          update(() => _groupCatalog = groups);
                        }
                      },
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    children: _groupCatalog.map((g) {
                      final id = g['id']?.toString() ?? '';
                      return CheckboxListTile(
                        value: selected.contains(id),
                        title: Text(g['name']?.toString() ?? 'گروپ'),
                        subtitle: Text('${_int(g['member_count'])} کڕیار'),
                        onChanged: (v) => update(() {
                          if (v == true) {
                            selected.add(id);
                          } else {
                            selected.remove(id);
                          }
                        }),
                      );
                    }).toList(growable: false),
                  ),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(sheetContext, true),
                  child: const Text('پاشەکەوت'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result == true) {
      await AdvancedCustomerService.setGroups(widget.customerId, selected);
      if (mounted) await _load();
    }
  }

  Future<void> _editBusiness() async {
    final business = _map(_data['business']);
    final company = TextEditingController(text: business['company_name']?.toString() ?? '');
    final tax = TextEditingController(text: business['tax_number']?.toString() ?? '');
    final rep = TextEditingController(text: business['representative_name']?.toString() ?? '');
    final phone = TextEditingController(text: business['representative_phone']?.toString() ?? '');
    final invoice = TextEditingController(text: business['invoice_reference']?.toString() ?? '');
    final save = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Business Customer'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: company, decoration: const InputDecoration(labelText: 'ناوی کۆمپانیا')),
              TextField(controller: tax, decoration: const InputDecoration(labelText: 'ژمارەی باج')),
              TextField(controller: rep, decoration: const InputDecoration(labelText: 'نوێنەر')),
              TextField(controller: phone, decoration: const InputDecoration(labelText: 'مۆبایلی نوێنەر')),
              TextField(controller: invoice, decoration: const InputDecoration(labelText: 'ژمارە/سەرچاوەی فاکتور')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('پاشگەزبوونەوە')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('پاشەکەوت')),
        ],
      ),
    );
    if (save == true && company.text.trim().isNotEmpty) {
      await AdvancedCustomerService.saveBusinessProfile(
        customerId: widget.customerId,
        companyName: company.text,
        taxNumber: tax.text,
        representativeName: rep.text,
        representativePhone: phone.text,
        invoiceReference: invoice.text,
      );
      if (mounted) await _load();
    }
    company.dispose();
    tax.dispose();
    rep.dispose();
    phone.dispose();
    invoice.dispose();
  }

  Future<void> _addRelationship() async {
    final actorId = PBService.client.auth.currentUser?.id ?? '';
    if (actorId.isEmpty) return;
    final actor = await PBService.getUser(actorId);
    final actorRole = actor.getStringValue('role');
    final adminId =
        actorRole == 'admin' ? actor.id : actor.getStringValue('admin_id');
    final customers = await PBService.getUsers(
      role: 'customer',
      approved: true,
      adminId: adminId.isEmpty ? null : adminId,
    );
    if (!mounted) return;
    final options = customers.where((c) => c.id != widget.customerId).toList();
    if (options.isEmpty) return;
    String selectedId = options.first.id;
    final type = TextEditingController(text: 'خێزان/پەیوەندیدار');
    final note = TextEditingController();
    final save = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, update) => AlertDialog(
          title: const Text('پەیوەستکردنی کڕیار'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedId,
                  isExpanded: true,
                  items: options.map((RecordModel c) => DropdownMenuItem(
                    value: c.id,
                    child: Text(c.getStringValue('name'), overflow: TextOverflow.ellipsis),
                  )).toList(growable: false),
                  onChanged: (v) => update(() => selectedId = v ?? selectedId),
                ),
                TextField(controller: type, decoration: const InputDecoration(labelText: 'جۆری پەیوەندی')),
                TextField(controller: note, decoration: const InputDecoration(labelText: 'تێبینی')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('پاشگەزبوونەوە')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('زیادکردن')),
          ],
        ),
      ),
    );
    if (save == true) {
      await AdvancedCustomerService.addRelationship(
        customerId: widget.customerId,
        relatedCustomerId: selectedId,
        relationType: type.text,
        note: note.text,
      );
      if (mounted) await _load();
    }
    type.dispose();
    note.dispose();
  }

  Future<void> _openVaultAsset(String storagePath) async {
    final path = storagePath.trim();
    if (path.isEmpty) return;
    try {
      final signed = await AdvancedCustomerService.createVaultSignedUrl(path);
      final uri = Uri.tryParse(signed);
      if (uri == null ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw const FormatException('invalid customer vault url');
      }
    } catch (e) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          e,
          fallback: 'نەتوانرا فایلەکە بکرێتەوە.',
        ),
        isError: true,
      );
    }
  }

  Future<void> _addInternalNote() async {
    final controller = TextEditingController();
    final save = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('تێبینی ناوخۆیی'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          maxLength: 5000,
          decoration: const InputDecoration(hintText: 'تەنها کارمەند/ئادمین دەیبینێت'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('پاشگەزبوونەوە')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('پاشەکەوت')),
        ],
      ),
    );
    if (save == true && controller.text.trim().isNotEmpty) {
      await AdvancedCustomerService.addNote(
        customerId: widget.customerId,
        type: 'internal',
        body: controller.text,
      );
      if (mounted) await _load();
    }
    controller.dispose();
  }

  Future<void> _uploadMediaNote({required bool voice}) async {
    Uint8List? bytes;
    String fileName = '';
    String mime = voice ? 'audio/*' : 'image/jpeg';

    if (voice) {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        withData: true,
      );
      final file = result == null || result.files.isEmpty
          ? null
          : result.files.first;
      bytes = file?.bytes;
      fileName = file?.name ?? '';
    } else {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked != null) {
        bytes = await picked.readAsBytes();
        fileName = picked.name;
        mime = picked.mimeType ?? 'image/jpeg';
      }
    }
    if (bytes == null || fileName.isEmpty || !mounted) return;
    final path = await AdvancedCustomerService.uploadVaultBytes(
      customerId: widget.customerId,
      fileName: fileName,
      bytes: bytes,
      contentType: mime,
    );
    await AdvancedCustomerService.addNote(
      customerId: widget.customerId,
      type: voice ? 'voice' : 'photo',
      mediaPath: path,
      mimeType: mime,
    );
    if (mounted) await _load();
  }

  Future<void> _uploadDocument() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    final file = result == null || result.files.isEmpty
        ? null
        : result.files.first;
    if (file?.bytes == null || file == null || !mounted) return;
    final path = await AdvancedCustomerService.uploadVaultBytes(
      customerId: widget.customerId,
      fileName: file.name,
      bytes: file.bytes!,
    );
    await AdvancedCustomerService.addDocument(
      customerId: widget.customerId,
      kind: 'other',
      fileName: file.name,
      storagePath: path,
      sizeBytes: file.size,
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final profile = _map(_data['profile']);
    final rules = _map(_data['rules']);
    final groups = _maps(_data['groups']);
    final relationships = _maps(_data['relationships']);
    final mergeHistory = _maps(_data['merge_history']);
    final notes = _maps(_assets['notes']);
    final docs = _maps(_assets['documents']);

    return Scaffold(
      appBar: AppBar(
        title: Text(profile['name']?.toString().isNotEmpty == true
            ? profile['name'].toString()
            : 'ناوەندی پێشکەوتووی کڕیار'),
        actions: [
          IconButton(
            tooltip: 'نوێکردنەوە',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading && _data.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _data.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: FilledButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(_error!),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      _summaryCard(),
                      const SizedBox(height: 12),
                      _section(
                        title: 'یاسا و پاراستن',
                        icon: Icons.policy_outlined,
                        trailing: IconButton(
                          tooltip: 'دەستکاری',
                          onPressed: _editRules,
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        children: [
                          _line('Credit Freeze', rules['credit_frozen'] == true ? 'چالاک' : 'ناچالاک'),
                          _line('Watch Status', rules['watch_status']?.toString() ?? 'normal'),
                          _line('Grace Period', '${_int(rules['grace_days'])} ڕۆژ'),
                          _line('Automatic VIP', rules['auto_vip_enabled'] == true ? 'چالاک' : 'ناچالاک'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _section(
                        title: 'گروپ و پەیوەندی',
                        icon: Icons.hub_outlined,
                        trailing: Wrap(
                          spacing: 2,
                          children: [
                            IconButton(onPressed: _editGroups, icon: const Icon(Icons.group_add_outlined)),
                            IconButton(onPressed: _addRelationship, icon: const Icon(Icons.link_rounded)),
                          ],
                        ),
                        children: [
                          if (groups.isEmpty) const Text('هیچ گروپێک نییە'),
                          if (groups.isNotEmpty)
                            Wrap(
                              spacing: 7,
                              runSpacing: 7,
                              children: groups.map((g) => Chip(label: Text(g['name']?.toString() ?? 'گروپ'))).toList(),
                            ),
                          if (relationships.isNotEmpty) ...[
                            const Divider(height: 24),
                            ...relationships.map((r) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.people_alt_outlined),
                              title: Text(r['name']?.toString() ?? 'کڕیار'),
                              subtitle: Text('${r['relation_type'] ?? ''} ${r['note'] ?? ''}'),
                            )),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      _section(
                        title: 'Business Customer',
                        icon: Icons.business_outlined,
                        trailing: IconButton(onPressed: _editBusiness, icon: const Icon(Icons.edit_outlined)),
                        children: [
                          _line('کۆمپانیا', _map(_data['business'])['company_name']?.toString() ?? '—'),
                          _line('ژمارەی باج', _map(_data['business'])['tax_number']?.toString() ?? '—'),
                          _line('نوێنەر', _map(_data['business'])['representative_name']?.toString() ?? '—'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _section(
                        title: 'Notes & Document Vault',
                        icon: Icons.folder_copy_outlined,
                        children: [
                          Wrap(
                            spacing: 7,
                            runSpacing: 7,
                            children: [
                              OutlinedButton.icon(onPressed: _addInternalNote, icon: const Icon(Icons.note_add_outlined), label: const Text('تێبینی')),
                              OutlinedButton.icon(onPressed: () => _uploadMediaNote(voice: false), icon: const Icon(Icons.photo_outlined), label: const Text('وێنە')),
                              OutlinedButton.icon(onPressed: () => _uploadMediaNote(voice: true), icon: const Icon(Icons.mic_none_rounded), label: const Text('دەنگ')),
                              OutlinedButton.icon(onPressed: _uploadDocument, icon: const Icon(Icons.upload_file_outlined), label: const Text('فایل')),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text('${notes.length} تێبینی/میدیا • ${docs.length} بەڵگەنامە'),
                          ...notes.take(5).map((n) {
                            final mediaPath =
                                n['media_path']?.toString() ?? '';
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              onTap: mediaPath.isEmpty
                                  ? null
                                  : () => _openVaultAsset(mediaPath),
                              leading: Icon(switch (n['note_type']) {
                                'photo' => Icons.photo_outlined,
                                'voice' => Icons.mic_none_rounded,
                                _ => Icons.lock_outline_rounded,
                              }),
                              title: Text(
                                n['body']?.toString().trim().isNotEmpty == true
                                    ? n['body'].toString()
                                    : n['note_type']?.toString() ?? 'note',
                              ),
                              subtitle:
                                  Text(n['created_at']?.toString() ?? ''),
                              trailing: mediaPath.isEmpty
                                  ? null
                                  : const Icon(Icons.open_in_new_rounded),
                            );
                          }),
                          ...docs.take(5).map((d) {
                            final storagePath =
                                d['storage_path']?.toString() ?? '';
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              onTap: storagePath.isEmpty
                                  ? null
                                  : () => _openVaultAsset(storagePath),
                              leading:
                                  const Icon(Icons.description_outlined),
                              title:
                                  Text(d['file_name']?.toString() ?? 'فایل'),
                              subtitle: Text(d['kind']?.toString() ?? ''),
                              trailing: storagePath.isEmpty
                                  ? null
                                  : const Icon(Icons.open_in_new_rounded),
                            );
                          }),
                        ],
                      ),
                      if (mergeHistory.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _section(
                          title: 'Merge History',
                          icon: Icons.merge_type_rounded,
                          children: mergeHistory.map((m) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text('Canonical: ${m['canonical_id']}'),
                            subtitle: Text('Duplicate: ${m['duplicate_id']} • ${m['created_at']}'),
                          )).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _summaryCard() {
    final trust = _int(_data['trust_score']);
    final risk = _int(_data['risk_score']);
    final priority = _int(_data['collection_priority_score']);
    final summary = _data['smart_summary']?.toString() ?? '';
    final action = _nextActionLabel(_data['next_best_action']?.toString() ?? '');
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Smart Customer Summary',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 8),
          Text(summary, style: const TextStyle(height: 1.55)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _metric('Trust', trust, Icons.verified_user_outlined),
              _metric('Risk', risk, Icons.warning_amber_rounded),
              _metric('Priority', priority, Icons.priority_high_rounded),
            ],
          ),
          const SizedBox(height: 10),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.auto_awesome_rounded),
            title: const Text('Next Best Action'),
            subtitle: Text(action),
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, int value, IconData icon) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text('$label • $value/100'),
    );
  }

  Widget _section({
    required String title,
    required IconData icon,
    Widget? trailing,
    required List<Widget> children,
  }) {
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 10),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
