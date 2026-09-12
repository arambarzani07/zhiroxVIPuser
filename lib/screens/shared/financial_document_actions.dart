import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/services/official_receipt_service.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/services/pdf_service.dart';
import 'package:zhirox/services/receipt_settings_service.dart';
import 'package:zhirox/utils/helpers.dart';

class _ReceiptIdentity {
  final String adminId;
  final String marketName;
  final String adminName;
  final String adminPhone;

  const _ReceiptIdentity({
    required this.adminId,
    required this.marketName,
    required this.adminName,
    required this.adminPhone,
  });
}

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

  static Future<_ReceiptIdentity> _identity(BuildContext context) async {
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
    return _ReceiptIdentity(
      adminId: adminId,
      marketName: marketName,
      adminName: adminName,
      adminPhone: adminPhone,
    );
  }

  static Future<MarketReceiptSettings> _settings(
    _ReceiptIdentity identity,
  ) {
    return ReceiptSettingsService.load(
      adminId: identity.adminId,
      fallbackMarketName: identity.marketName,
      fallbackPhone: identity.adminPhone,
    );
  }

  static Future<void> _runOfficialAction(
    BuildContext context,
    RecordModel debt,
    String action,
  ) async {
    final identity = await _identity(context);
    final settings = await _settings(identity);

    switch (action) {
      case 'share_pdf':
        await OfficialReceiptService.shareDebtReceiptPdf(
          debt: debt,
          marketName: identity.marketName,
          adminName: identity.adminName,
          fallbackPhone: identity.adminPhone,
          settings: settings,
        );
        break;
      case 'share_image':
        await OfficialReceiptService.shareDebtReceiptImage(
          debt: debt,
          marketName: identity.marketName,
          adminName: identity.adminName,
          fallbackPhone: identity.adminPhone,
          settings: settings,
        );
        break;
      case 'print':
      default:
        await OfficialReceiptService.generateDebtReceipt(
          debt: debt,
          marketName: identity.marketName,
          adminName: identity.adminName,
          fallbackPhone: identity.adminPhone,
          settings: settings,
        );
        break;
    }
  }

  static Future<void> generateDebtInvoice(
    BuildContext context,
    RecordModel debt,
  ) async {
    try {
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
                  leading: Icon(Icons.receipt_long_outlined),
                  title: Text(
                    'پسوولەی فەرمی',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text('چاپ یان Share بە PDF / Image'),
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
              ],
            ),
          ),
        ),
      );
      if (action == null || !context.mounted) return;

      try {
        await _runOfficialAction(context, debt, action);
      } catch (_) {
        if (action == 'print') {
          final identity = await _identity(context);
          await PdfService.generateInvoice(
            debt: debt,
            marketName: identity.marketName,
            adminName: identity.adminName,
            adminPhone: identity.adminPhone,
          );
          return;
        }
        rethrow;
      }
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
