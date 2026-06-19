import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

class DebtProtectedDeleteScreen extends StatefulWidget {
  final RecordModel debt;
  const DebtProtectedDeleteScreen({super.key, required this.debt});

  @override
  State<DebtProtectedDeleteScreen> createState() => _DebtProtectedDeleteScreenState();
}

class _DebtProtectedDeleteScreenState extends State<DebtProtectedDeleteScreen> {
  final reasonCtrl = TextEditingController();
  bool saving = false;

  @override
  void dispose() {
    reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isManager) {
      AppHelpers.showSnackBar(context, AppUserMessages.needsManagerApproval, isError: true);
      return;
    }
    final ok = await AppHelpers.showConfirmDialog(
      context,
      title: 'سڕینەوەی پارێزراو',
      message: 'ئەم قەرزە لە لیستە چالاکەکان دەشاردرێتەوە و مێژووەکەی دەمێنێتەوە. دڵنیایت؟',
    );
    if (!ok || !mounted) return;
    setState(() => saving = true);
    try {
      await PBService.pb.collection('debts').update(widget.debt.id, body: {
        'is_deleted': true,
        'deleted_by': auth.userId,
        'deleted_at': DateTime.now().toIso8601String(),
        'delete_reason': reasonCtrl.text.trim(),
      });
      if (!mounted) return;
      AppHelpers.showSnackBar(context, 'قەرزی ماوە نوێکرایەوە');
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      AppHelpers.showSnackBar(context, AppUserMessages.protectedOffline);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppDarkColors.card : Colors.white;
    final subColor = isDark ? AppDarkColors.textSecondary : AppColors.textSecondary;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppDarkColors.background : const Color(0xFFF5F7FA),
        appBar: AppBar(title: const Text('سڕینەوەی پارێزراو')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('قەرز لە لیستە چالاکەکان دەشاردرێتەوە، بەڵام مێژووەکەی دەمێنێتەوە.', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(controller: reasonCtrl, minLines: 2, maxLines: 3, decoration: const InputDecoration(labelText: 'هۆکار')),
              const SizedBox(height: 10),
              Text('ئەم کردارە تەنها بە بڕیاری بەڕێوەبەر ئەنجام دەدرێت.', style: TextStyle(color: subColor, height: 1.5)),
            ]),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: saving ? null : save,
              icon: const Icon(Icons.shield_rounded),
              label: Text(saving ? 'نوێکردنەوە...' : 'سڕینەوەی پارێزراو قەبوڵ بکە'),
            ),
          ),
        ]),
      ),
    );
  }
}
