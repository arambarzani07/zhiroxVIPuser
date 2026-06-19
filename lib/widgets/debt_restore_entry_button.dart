import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/screens/shared/debt_restore_screen.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

class DebtRestoreEntryButton extends StatelessWidget {
  final Future<void> Function()? onReturn;
  const DebtRestoreEntryButton({super.key, this.onReturn});

  Future<void> open(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isManager) {
      AppHelpers.showSnackBar(context, AppUserMessages.needsManagerApproval, isError: true);
      return;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const DebtRestoreScreen()));
    if (onReturn != null) await onReturn!();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: OutlinedButton.icon(
        onPressed: () => open(context),
        icon: const Icon(Icons.restore_rounded, color: AppColors.primary),
        label: const Text('گەڕاندنەوەی کردار'),
      ),
    );
  }
}
