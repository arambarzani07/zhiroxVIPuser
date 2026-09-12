import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/services/payment_receipt_service.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/services/receipt_settings_service.dart';
import 'package:zhirox/utils/helpers.dart';

class _PaymentReceiptIdentity {
  final String adminId;
  final String marketName;
  final String adminName;
  final String adminPhone;

  const _PaymentReceiptIdentity({
    required this.adminId,
    required this.marketName,
    required this.adminName,
    required this.adminPhone,
  });
}

class PaymentReceiptActions {
  PaymentReceiptActions._();

  static Future<_PaymentReceiptIdentity> _identity(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    var marketName = auth.marketName.trim();
    var adminPhone = auth.user?.getStringValue('phone').trim() ?? '';
    var adminName = auth.userName.trim();
    final adminId = auth.userRole == 'admin' ? auth.userId : auth.adminId;

    if ((marketName.isEmpty || adminPhone.isEmpty || adminName.isEmpty) &&
        adminId.isNotEmpty) {
      try {
        final admin = await PBService.getUser(adminId);
        if (marketName.isEmpty) {
          marketName = admin.getStringValue('market_name').trim();
        }
        if (adminPhone.isEmpty) {
          adminPhone = admin.getStringValue('phone').trim();
        }
        if (adminName.isEmpty) {
          adminName = admin.getStringValue('name').trim();
        }
      } catch (_) {}
    }

    if (marketName.isEmpty) marketName = 'Zhirox System';
    if (adminName.isEmpty) adminName = 'ZHIROX';
    return _PaymentReceiptIdentity(
      adminId: adminId,
      marketName: marketName,
      adminName: adminName,
      adminPhone: adminPhone,
    );
  }

  static Future<void> show(
    BuildContext context, {
    required RecordModel payment,
    required RecordModel debt,
  }) async {
    if (!context.mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                leading: Icon(Icons.payments_outlined),
                title: Text(
                  'پسوولەی پارەدانەوە',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text('Payment Template • چاپ یان Share بە PDF / Image'),
              ),
              ListTile(
                leading: const Icon(Icons.print_outlined),
                title: const Text('چاپ / PDF'),
                onTap: () => Navigator.pop(sheetContext, 'print'),
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: const Text('Share PDF'),
                onTap: () => Navigator.pop(sheetContext, 'share_pdf'),
              ),
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('Share Image'),
                onTap: () => Navigator.pop(sheetContext, 'share_image'),
              ),
              ListTile(
                leading: const Icon(Icons.close_rounded),
                title: const Text('دواتر'),
                onTap: () => Navigator.pop(sheetContext),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !context.mounted) return;

    try {
      final identity = await _identity(context);
      final settings = await ReceiptSettingsService.load(
        adminId: identity.adminId,
        fallbackMarketName: identity.marketName,
        fallbackPhone: identity.adminPhone,
      );

      switch (action) {
        case 'share_pdf':
          await PaymentReceiptService.sharePaymentReceiptPdf(
            payment: payment,
            debt: debt,
            marketName: identity.marketName,
            adminName: identity.adminName,
            fallbackPhone: identity.adminPhone,
            settings: settings,
          );
          break;
        case 'share_image':
          await PaymentReceiptService.sharePaymentReceiptImage(
            payment: payment,
            debt: debt,
            marketName: identity.marketName,
            adminName: identity.adminName,
            fallbackPhone: identity.adminPhone,
            settings: settings,
          );
          break;
        case 'print':
        default:
          await PaymentReceiptService.generatePaymentReceipt(
            payment: payment,
            debt: debt,
            marketName: identity.marketName,
            adminName: identity.adminName,
            fallbackPhone: identity.adminPhone,
            settings: settings,
          );
          break;
      }
    } catch (e) {
      if (!context.mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          e,
          fallback: 'نەتوانرا پسوولەی پارەدانەوە دروست بکرێت.',
        ),
        isError: true,
      );
    }
  }
}
