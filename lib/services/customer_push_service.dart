import 'package:zhirox/services/pb_service.dart';

typedef CustomerPushAdminInvoker = Future<Object?> Function(
  Map<String, dynamic> body,
);

class CustomerPushStatus {
  final bool active;
  final int deviceCount;
  final int activeLinkCount;
  final String? latestStatus;
  final DateTime? latestAt;

  const CustomerPushStatus({
    required this.active,
    required this.deviceCount,
    this.activeLinkCount = 0,
    this.latestStatus,
    this.latestAt,
  });

  bool get hasActiveLink => activeLinkCount > 0;

  factory CustomerPushStatus.fromJson(Map<String, dynamic> json) {
    final active = json['active'];
    final deviceCount = json['device_count'];
    final activeLinkCount = json['active_link_count'];
    final latestStatus = json['latest_status'];
    final latestAtRaw = json['latest_at'];

    if (active is! bool ||
        deviceCount is! int ||
        deviceCount < 0 ||
        activeLinkCount is! int ||
        activeLinkCount < 0) {
      throw const FormatException('Malformed customer push status payload');
    }
    if (latestStatus != null && latestStatus is! String) {
      throw const FormatException('Malformed customer push status payload');
    }

    DateTime? latestAt;
    if (latestAtRaw != null) {
      if (latestAtRaw is! String) {
        throw const FormatException('Malformed customer push status payload');
      }
      latestAt = DateTime.tryParse(latestAtRaw);
      if (latestAt == null) {
        throw const FormatException('Malformed customer push status payload');
      }
    }

    return CustomerPushStatus(
      active: active,
      deviceCount: deviceCount,
      activeLinkCount: activeLinkCount,
      latestStatus: latestStatus as String?,
      latestAt: latestAt,
    );
  }
}

class CustomerPushLink {
  final Uri url;
  final DateTime? expiresAt;

  const CustomerPushLink({
    required this.url,
    this.expiresAt,
  });

  factory CustomerPushLink.fromJson(Map<String, dynamic> json) {
    final urlRaw = json['url'];
    final expiresRaw = json['expires_at'];
    if (urlRaw is! String || (expiresRaw != null && expiresRaw is! String)) {
      throw const FormatException('Malformed customer push link payload');
    }

    final url = Uri.tryParse(urlRaw);
    final expiresAt = expiresRaw is String ? DateTime.tryParse(expiresRaw) : null;
    final token = url?.queryParameters['token'] ?? '';
    final validToken = RegExp(r'^[0-9a-f]{64}$').hasMatch(token);
    if (url == null ||
        !url.hasScheme ||
        url.host.isEmpty ||
        (url.scheme != 'https' && url.scheme != 'http') ||
        !validToken ||
        (expiresRaw != null && expiresAt == null)) {
      throw const FormatException('Malformed customer push link payload');
    }

    return CustomerPushLink(url: url, expiresAt: expiresAt);
  }
}

abstract interface class CustomerPushGateway {
  Future<CustomerPushStatus> loadStatus(String customerId);

  Future<CustomerPushLink> createLink(String customerId);

  Future<int> revokeAll(String customerId);
}

class CustomerPushService implements CustomerPushGateway {
  final CustomerPushAdminInvoker? _invoker;

  const CustomerPushService({CustomerPushAdminInvoker? invoker})
      : _invoker = invoker;

  Future<Object?> _invokeAdmin(
    String action,
    String customerId,
  ) async {
    final body = <String, dynamic>{
      'action': action,
      'customer_id': customerId,
    };

    final injected = _invoker;
    if (injected != null) {
      return injected(body);
    }

    await PBService.ensureInitialized();
    final response = await PBService.client.functions.invoke(
      'customer-push-admin',
      body: body,
    );
    final data = response.data;
    if (data is Map && data['error'] != null) {
      throw StateError('Customer push request failed: ${data['error']}');
    }
    return data;
  }

  Map<String, dynamic> _requireMap(Object? value) {
    if (value is! Map) {
      throw const FormatException('Malformed customer push response');
    }
    return value.map(
      (key, item) => MapEntry(key.toString(), item),
    );
  }

  @override
  Future<CustomerPushStatus> loadStatus(String customerId) async {
    final data = await _invokeAdmin('status', customerId);
    return CustomerPushStatus.fromJson(_requireMap(data));
  }

  @override
  Future<CustomerPushLink> createLink(String customerId) async {
    final data = await _invokeAdmin('create_link', customerId);
    return CustomerPushLink.fromJson(_requireMap(data));
  }

  @override
  Future<int> revokeAll(String customerId) async {
    final data = _requireMap(await _invokeAdmin('revoke_all', customerId));
    final count = data['revoked_count'];
    if (count is! int || count < 0) {
      throw const FormatException('Malformed customer push revoke payload');
    }
    return count;
  }
}
