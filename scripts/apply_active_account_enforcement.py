from pathlib import Path

ROOT = Path.cwd()
pb_path = ROOT / 'lib/services/pb_service.dart'
auth_path = ROOT / 'lib/providers/auth_provider.dart'

pb = pb_path.read_text(encoding='utf-8')
auth = auth_path.read_text(encoding='utf-8')

old_login = """      final user = await getUser(authUser.id);
      final role = user.getStringValue('role');

      if (role == 'customer' && !user.getBoolValue('approved')) {
        await client.auth.signOut();
        throw AppStrings.notApproved;
      }
      if (role == 'employee' && !user.getBoolValue('active')) {
        await client.auth.signOut();
        throw 'ئەم ئەکاونتە لەلایەن ئەدمینەوە ناچالاک کراوە';
      }
"""
new_login = """      final user = await getUser(authUser.id);
      final role = user.getStringValue('role');

      if (!user.getBoolValue('active')) {
        await client.auth.signOut();
        throw 'ئەم هەژمارە ناچالاک کراوە';
      }
      if (role == 'customer' && !user.getBoolValue('approved')) {
        await client.auth.signOut();
        throw AppStrings.notApproved;
      }
"""
if new_login not in pb:
    if old_login not in pb:
        raise SystemExit('PBService login active-account anchor not found')
    pb = pb.replace(old_login, new_login, 1)

old_realtime = """        if (role == 'employee' && (!active || !approved)) {
          wasDeactivated = true;
          await logout();
          return;
        }

        _user = updated;
"""
new_realtime = """        if (!active || (role == 'customer' && !approved)) {
          wasDeactivated = true;
          await logout();
          return;
        }

        _user = updated;
"""
if new_realtime not in auth:
    if old_realtime not in auth:
        raise SystemExit('AuthProvider realtime active-account anchor not found')
    auth = auth.replace(old_realtime, new_realtime, 1)

validate_anchor = """  Future<void> _validateSubscription() async {
    final current = _user;
    if (current == null) return;

    if (userRole == 'admin') {
"""
validate_replacement = """  Future<void> _validateSubscription() async {
    final current = _user;
    if (current == null) return;

    if (!current.getBoolValue('active')) {
      throw 'ئەم هەژمارە ناچالاک کراوە';
    }
    if (userRole == 'customer' && !current.getBoolValue('approved')) {
      throw 'ئەم هەژمارە هێشتا پەسەند نەکراوە';
    }

    if (userRole == 'admin') {
"""
if validate_replacement not in auth:
    if validate_anchor not in auth:
        raise SystemExit('AuthProvider validation anchor not found')
    auth = auth.replace(validate_anchor, validate_replacement, 1)

auth = auth.replace(
    "      if (userRole == 'employee') _subscribeToUserChanges();",
    "      _subscribeToUserChanges();",
)

pb_path.write_text(pb, encoding='utf-8')
auth_path.write_text(auth, encoding='utf-8')
print('Active-account enforcement applied.')
