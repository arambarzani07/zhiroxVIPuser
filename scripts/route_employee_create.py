from pathlib import Path

p = Path('lib/services/pb_service.dart')
s = p.read_text()
old = """  static Future<RecordModel> _invokeCreateAccount(Map<String, dynamic> body) async {
    await ensureInitialized();
    try {
      final response = await client.functions.invoke(
        'account-admin',
        body: {'action': 'create_user', ...body},
      );
      final data = response.data;
      if (data is! Map || data['user'] is! Map) {
        throw _functionError(data);
      }
      return profileRecord(Map<String, dynamic>.from(data['user'] as Map));
    } on FunctionsException catch (e) {
      throw _functionError(e.details ?? e.reasonPhrase ?? e.status);
    }
  }
"""
new = """  static Future<RecordModel> _invokeCreateAccount(Map<String, dynamic> body) async {
    await ensureInitialized();
    try {
      final isEmployee = body['role']?.toString() == 'employee';
      final response = await client.functions.invoke(
        isEmployee ? 'employee-create' : 'account-admin',
        body: isEmployee ? body : {'action': 'create_user', ...body},
      );
      final data = response.data;
      if (data is! Map || data['user'] is! Map) {
        throw _functionError(data);
      }
      return profileRecord(Map<String, dynamic>.from(data['user'] as Map));
    } on FunctionsException catch (e) {
      throw _functionError(e.details ?? e.reasonPhrase ?? e.status);
    }
  }
"""
if old in s:
    s = s.replace(old, new, 1)
elif "isEmployee ? 'employee-create' : 'account-admin'" not in s:
    raise SystemExit('create account invocation block not found')
p.write_text(s)
