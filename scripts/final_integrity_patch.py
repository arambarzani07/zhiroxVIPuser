from pathlib import Path

path = Path('lib/services/pb_service.dart')
text = path.read_text()

helper = """  static bool _isRetryableAuthException(AuthException error) {
    final text = '${error.runtimeType} ${error.message}'.toLowerCase();
    return text.contains('retryable') ||
        text.contains('network') ||
        text.contains('socket') ||
        text.contains('fetch') ||
        text.contains('connection') ||
        text.contains('timeout') ||
        text.contains('temporarily unavailable') ||
        text.contains('bad gateway') ||
        text.contains('service unavailable') ||
        text.contains('gateway timeout') ||
        text.contains('internal server error') ||
        text.contains('too many requests');
  }

"""
if '_isRetryableAuthException' not in text:
    anchor = '  static RecordModel _profileRecord('
    if anchor not in text:
        raise SystemExit('profileRecord anchor not found')
    text = text.replace(anchor, helper + anchor, 1)

old_auth = """    } on AuthException catch (_) {
      throw Exception('وشەی نهێنی هەڵەیە');
    }
"""
new_auth = """    } on AuthException catch (e) {
      if (_isRetryableAuthException(e)) {
        throw SocketException('temporary authentication network failure');
      }
      throw Exception('وشەی نهێنی هەڵەیە');
    }
"""
if old_auth not in text and new_auth not in text:
    raise SystemExit('login auth catch not found')
text = text.replace(old_auth, new_auth, 1)

old_create = """    final created = await pb.collection('debts').create(body: body);
"""
new_create = """    RecordModel created;
    try {
      created = await pb.collection('debts').create(body: body);
    } catch (error) {
      if (receiptPath.isNotEmpty) {
        try {
          await client.storage.from('receipts').remove([receiptPath]);
        } catch (_) {}
      }
      rethrow;
    }
"""
if old_create not in text and new_create not in text:
    raise SystemExit('debt create line not found')
text = text.replace(old_create, new_create, 1)

old_delete = """  static Future<void> deleteDebt(String id) async {
    final payments = await pb.collection('payments').getList(
      filter: 'debt = \"${_sanitize(id)}\"',
      perPage: 500,
    );
    for (final payment in payments.items) {
      await pb.collection('payments').delete(payment.id);
    }
    await pb.collection('debts').delete(id);
  }
"""
new_delete = """  static Future<void> deleteDebt(String id) async {
    final debt = await getDebt(id);
    final receiptPath = debt.getStringValue('receipt_image');

    // payments.debt_id is ON DELETE CASCADE in Postgres, so one debt delete
    // keeps the financial delete atomic instead of deleting payments piecemeal.
    await pb.collection('debts').delete(id);

    if (receiptPath.isNotEmpty) {
      try {
        await client.storage.from('receipts').remove([receiptPath]);
      } catch (_) {
        // Database deletion already succeeded. A storage cleanup failure must
        // not turn a completed financial transaction into an app-level error.
      }
    }
  }
"""
if old_delete not in text and new_delete not in text:
    raise SystemExit('deleteDebt block not found')
text = text.replace(old_delete, new_delete, 1)

path.write_text(text)
