import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/services/official_receipt_service.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/services/receipt_settings_service.dart';
import 'package:zhirox/utils/helpers.dart';

/// Single source of truth for debt invoices and receipt viewing.
class FinancialDocumentActions {
  FinancialDocumentActions._();

  static String receiptUrl(
    RecordModel debt, {
    String? receiptPath,
  }) {
    final path = (receiptPath ?? debt.getStringValue('receipt_image')).trim();
    if (path.isEmpty) return '';
    return PBService.pb.getFileUrl(debt, path).toString();
  }

  static Future<void> generateDebtInvoice(
    BuildContext context,
    RecordModel debt,
  ) async {
    try {
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

      final settings = await ReceiptSettingsService.load(
        adminId: adminId,
        fallbackMarketName: marketName,
        fallbackPhone: adminPhone,
      );

      await OfficialReceiptService.generateDebtReceipt(
        debt: debt,
        marketName: marketName,
        adminName: adminName,
        fallbackPhone: adminPhone,
        settings: settings,
      );
    } catch (e) {
      if (!context.mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          e,
          fallback: 'نەتوانرا پسوولەی فەرمی دروست بکرێت. دووبارە هەوڵ بدە.',
        ),
        isError: true,
      );
    }
  }

  static Future<void> openReceiptViewer(
    BuildContext context,
    RecordModel debt, {
    String? receiptPath,
  }) async {
    final imageUrl = receiptUrl(debt, receiptPath: receiptPath);
    if (imageUrl.isEmpty || !context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (viewerContext) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text('وێنەی وەصڵ'),
          ),
          body: SafeArea(
            child: Center(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 5,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'نەتوانرا وێنەی وەصڵ بار بکرێت.',
                      style: TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
