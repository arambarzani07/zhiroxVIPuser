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

class CustomerPushOverviewItem {
  final String customerId;
  final String name;
  final String phone;
  final bool active;
  final int deviceCount;
  final int activeLinkCount;
  final String? latestStatus;
  final DateTime? latestAt;

  const CustomerPushOverviewItem({
    required this.customerId,
    required this.name,
    required this.phone,
    required this.active,
    required this.deviceCount,
    required this.activeLinkCount,
    this.latestStatus,
    this.latestAt,
  });

  factory CustomerPushOverviewItem.fromJson(Map<String, dynamic> json) {
    final customerId = json['customer_id'];
    final name = json['name'];
    final phone = json['phone'];
    final active = json['active'];
    final deviceCount = json['device_count'];
    final activeLinkCount = json['active_link_count'];
    final latestStatus = json['latest_status'];
    final latestAtRaw = json['latest_at'];
    final latestAt =
        latestAtRaw is String ? DateTime.tryParse(latestAtRaw) : null;

    if (customerId is! String ||
        !RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(customerId) ||
        name is! String ||
        phone is! String ||
        active is! bool ||
        deviceCount is! int ||
        deviceCount < 0 ||
        activeLinkCount is! int ||
        activeLinkCount < 0 ||
        (latestStatus != null && latestStatus is! String) ||
        (latestAtRaw != null && latestAt == null)) {
      throw const FormatException('Malformed customer push overview payload');
    }

    return CustomerPushOverviewItem(
      customerId: customerId,
      name: name,
      phone: phone,
      active: active,
      deviceCount: deviceCount,
      activeLinkCount: activeLinkCount,
      latestStatus: latestStatus as String?,
      latestAt: latestAt,
    );
  }
}

class CustomerPushOverviewSummary {
  final int all;
  final int active;
  final int inactive;
  final int failed;
  final int pending;

  const CustomerPushOverviewSummary({
    required this.all,
    required this.active,
    required this.inactive,
    required this.failed,
    required this.pending,
  });

  factory CustomerPushOverviewSummary.fromJson(Map<String, dynamic> json) {
    final all = json['all'];
    final active = json['active'];
    final inactive = json['inactive'];
    final failed = json['failed'];
    final pending = json['pending'];
    if (all is! int ||
        active is! int ||
        inactive is! int ||
        failed is! int ||
        pending is! int ||
        [all, active, inactive, failed, pending].any((value) => value < 0)) {
      throw const FormatException('Malformed customer push overview summary');
    }
    return CustomerPushOverviewSummary(
      all: all,
      active: active,
      inactive: inactive,
      failed: failed,
      pending: pending,
    );
  }
}

class CustomerPushOverviewPage {
  final List<CustomerPushOverviewItem> items;
  final int totalCount;
  final int offset;
  final int limit;
  final bool hasMore;
  final String filter;
  final CustomerPushOverviewSummary summary;

  const CustomerPushOverviewPage({
    required this.items,
    required this.totalCount,
    required this.offset,
    required this.limit,
    required this.hasMore,
    required this.filter,
    required this.summary,
  });

  factory CustomerPushOverviewPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final totalCount = json['total_count'];
    final offset = json['offset'];
    final limit = json['limit'];
    final hasMore = json['has_more'];
    final filter = json['filter'];
    final summaryRaw = json['summary'];

    if (rawItems is! List ||
        totalCount is! int ||
        totalCount < 0 ||
        offset is! int ||
        offset < 0 ||
        limit is! int ||
        limit <= 0 ||
        hasMore is! bool ||
        filter is! String ||
        summaryRaw is! Map) {
      throw const FormatException('Malformed customer push overview response');
    }

    final items = rawItems.map((item) {
      if (item is! Map) {
        throw const FormatException('Malformed customer push overview response');
      }
      return CustomerPushOverviewItem.fromJson(
        item.map((key, value) => MapEntry(key.toString(), value)),
      );
    }).toList(growable: false);

    return CustomerPushOverviewPage(
      items: items,
      totalCount: totalCount,
      offset: offset,
      limit: limit,
      hasMore: hasMore,
      filter: filter,
      summary: CustomerPushOverviewSummary.fromJson(
        summaryRaw.map((key, value) => MapEntry(key.toString(), value)),
      ),
    );
  }
}

class CustomerPushHistoryItem {
  final String id;
  final String eventType;
  final String status;
  final DateTime createdAt;
  final DateTime? completedAt;
  final int sentCount;
  final int failedCount;
  final int expiredCount;
  final int pendingCount;
  final int deviceCount;
  final int attemptCount;
  final String? lastError;
  final String? message;
  final num? amount;
  final String? currency;

  const CustomerPushHistoryItem({
    required this.id,
    required this.eventType,
    required this.status,
    required this.createdAt,
    this.completedAt,
    required this.sentCount,
    required this.failedCount,
    required this.expiredCount,
    required this.pendingCount,
    required this.deviceCount,
    required this.attemptCount,
    this.lastError,
    this.message,
    this.amount,
    this.currency,
  });

  bool get canRetry =>
      status == 'failed' || status == 'partial' || status == 'no_device';

  factory CustomerPushHistoryItem.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final eventType = json['event_type'];
    final status = json['status'];
    final createdAtRaw = json['created_at'];
    final completedAtRaw = json['completed_at'];
    final sentCount = json['sent_count'];
    final failedCount = json['failed_count'];
    final expiredCount = json['expired_count'];
    final pendingCount = json['pending_count'];
    final deviceCount = json['device_count'];
    final attemptCount = json['attempt_count'];
    final lastError = json['last_error'];
    final message = json['message'];
    final amount = json['amount'];
    final currency = json['currency'];

    final createdAt =
        createdAtRaw is String ? DateTime.tryParse(createdAtRaw) : null;
    final completedAt =
        completedAtRaw is String ? DateTime.tryParse(completedAtRaw) : null;
    if (id is! String ||
        !RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id) ||
        eventType is! String ||
        status is! String ||
        createdAt == null ||
        (completedAtRaw != null && completedAt == null) ||
        sentCount is! int ||
        failedCount is! int ||
        expiredCount is! int ||
        pendingCount is! int ||
        deviceCount is! int ||
        attemptCount is! int ||
        [
          sentCount,
          failedCount,
          expiredCount,
          pendingCount,
          deviceCount,
          attemptCount,
        ].any((value) => value < 0) ||
        (lastError != null && lastError is! String) ||
        (message != null && message is! String) ||
        (amount != null && amount is! num) ||
        (currency != null && currency is! String)) {
      throw const FormatException('Malformed customer push history payload');
    }

    return CustomerPushHistoryItem(
      id: id,
      eventType: eventType,
      status: status,
      createdAt: createdAt,
      completedAt: completedAt,
      sentCount: sentCount,
      failedCount: failedCount,
      expiredCount: expiredCount,
      pendingCount: pendingCount,
      deviceCount: deviceCount,
      attemptCount: attemptCount,
      lastError: lastError as String?,
      message: message as String?,
      amount: amount as num?,
      currency: currency as String?,
    );
  }
}

class CustomerPushRetryResult {
  final String outboxId;
  final int retryDevices;
  final bool alreadySent;

  const CustomerPushRetryResult({
    required this.outboxId,
    required this.retryDevices,
    required this.alreadySent,
  });

  factory CustomerPushRetryResult.fromJson(Map<String, dynamic> json) {
    final outboxId = json['outbox_id'];
    final retryDevices = json['retry_devices'];
    final alreadySent = json['already_sent'];
    if (outboxId is! String ||
        !RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(outboxId) ||
        retryDevices is! int ||
        retryDevices < 0 ||
        alreadySent is! bool) {
      throw const FormatException('Malformed customer push retry payload');
    }
    return CustomerPushRetryResult(
      outboxId: outboxId,
      retryDevices: retryDevices,
      alreadySent: alreadySent,
    );
  }
}

class CustomerPushSettings {
  final int overdueIntervalDays;

  const CustomerPushSettings({required this.overdueIntervalDays});

  factory CustomerPushSettings.fromJson(Map<String, dynamic> json) {
    final value = json['overdue_interval_days'];
    if (value is! int || value < 1 || value > 30) {
      throw const FormatException('Malformed customer push settings payload');
    }
    return CustomerPushSettings(overdueIntervalDays: value);
  }
}

class CustomerPushSendResult {
  final String campaignId;
  final int queuedCustomers;
  final int targetDevices;
  final String marketName;

  const CustomerPushSendResult({
    required this.campaignId,
    required this.queuedCustomers,
    required this.targetDevices,
    required this.marketName,
  });

  factory CustomerPushSendResult.fromJson(Map<String, dynamic> json) {
    final campaignId = json['campaign_id'];
    final queuedCustomers = json['queued_customers'];
    final targetDevices = json['target_devices'];
    final marketName = json['market_name'];
    final validCampaignId = campaignId is String &&
        RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(campaignId);

    if (!validCampaignId ||
        queuedCustomers is! int ||
        queuedCustomers < 0 ||
        targetDevices is! int ||
        targetDevices < 0 ||
        marketName is! String ||
        marketName.trim().isEmpty) {
      throw const FormatException('Malformed customer push send payload');
    }

    return CustomerPushSendResult(
      campaignId: campaignId,
      queuedCustomers: queuedCustomers,
      targetDevices: targetDevices,
      marketName: marketName.trim(),
    );
  }
}

abstract interface class CustomerPushGateway {
  Future<CustomerPushOverviewPage> loadOverview({
    String search = '',
    String filter = 'all',
    int limit = 60,
    int offset = 0,
  });

  Future<CustomerPushStatus> loadStatus(String customerId);

  Future<CustomerPushLink> createLink(String customerId);

  Future<List<CustomerPushHistoryItem>> loadHistory(
    String customerId, {
    int limit = 20,
  });

  Future<CustomerPushRetryResult> retryNotification(
    String customerId,
    String outboxId,
  );

  Future<int> revokeAll(String customerId);

  Future<CustomerPushSendResult> sendManual(
    String customerId,
    String message,
  );

  Future<CustomerPushSendResult> broadcastManual(String message);

  Future<CustomerPushSettings> loadSettings();

  Future<CustomerPushSettings> updateSettings({
    required int overdueIntervalDays,
  });
}

class CustomerPushService implements CustomerPushGateway {
  static const int manualMessageMaxLength = 240;

  final CustomerPushAdminInvoker? _invoker;

  const CustomerPushService({CustomerPushAdminInvoker? invoker})
      : _invoker = invoker;

  Future<Object?> _invokeAdmin(
    String action, {
    String? customerId,
    String? message,
    String? outboxId,
    String? search,
    String? filter,
    int? limit,
    int? offset,
    int? overdueIntervalDays,
  }) async {
    final body = <String, dynamic>{'action': action};
    if (customerId != null) body['customer_id'] = customerId;
    if (message != null) body['message'] = message;
    if (outboxId != null) body['outbox_id'] = outboxId;
    if (search != null) body['search'] = search;
    if (filter != null) body['filter'] = filter;
    if (limit != null) body['limit'] = limit;
    if (offset != null) body['offset'] = offset;
    if (overdueIntervalDays != null) {
      body['overdue_interval_days'] = overdueIntervalDays;
    }

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

  String _manualMessage(String message) {
    final normalized = message.trim();
    if (normalized.isEmpty || normalized.length > manualMessageMaxLength) {
      throw ArgumentError.value(
        message,
        'message',
        'Manual notification must contain 1-$manualMessageMaxLength characters',
      );
    }
    return normalized;
  }

  @override
  Future<CustomerPushOverviewPage> loadOverview({
    String search = '',
    String filter = 'all',
    int limit = 60,
    int offset = 0,
  }) async {
    const allowedFilters = {'all', 'active', 'inactive', 'failed', 'pending'};
    final normalizedFilter = filter.trim().toLowerCase();
    if (!allowedFilters.contains(normalizedFilter)) {
      throw ArgumentError.value(filter, 'filter', 'Unsupported push overview filter');
    }
    final data = await _invokeAdmin(
      'overview',
      search: search.trim(),
      filter: normalizedFilter,
      limit: limit.clamp(1, 100).toInt(),
      offset: offset < 0 ? 0 : offset,
    );
    return CustomerPushOverviewPage.fromJson(_requireMap(data));
  }

  @override
  Future<CustomerPushStatus> loadStatus(String customerId) async {
    final data = await _invokeAdmin('status', customerId: customerId);
    return CustomerPushStatus.fromJson(_requireMap(data));
  }

  @override
  Future<CustomerPushLink> createLink(String customerId) async {
    final data = await _invokeAdmin('create_link', customerId: customerId);
    return CustomerPushLink.fromJson(_requireMap(data));
  }

  @override
  Future<List<CustomerPushHistoryItem>> loadHistory(
    String customerId, {
    int limit = 20,
  }) async {
    final data = _requireMap(
      await _invokeAdmin(
        'history',
        customerId: customerId,
        limit: limit.clamp(1, 100).toInt(),
      ),
    );
    final items = data['items'];
    if (items is! List) {
      throw const FormatException('Malformed customer push history response');
    }
    return items.map((item) {
      if (item is! Map) {
        throw const FormatException('Malformed customer push history response');
      }
      return CustomerPushHistoryItem.fromJson(
        item.map((key, value) => MapEntry(key.toString(), value)),
      );
    }).toList(growable: false);
  }

  @override
  Future<CustomerPushRetryResult> retryNotification(
    String customerId,
    String outboxId,
  ) async {
    final data = await _invokeAdmin(
      'retry',
      customerId: customerId,
      outboxId: outboxId,
    );
    return CustomerPushRetryResult.fromJson(_requireMap(data));
  }

  @override
  Future<int> revokeAll(String customerId) async {
    final data = _requireMap(
      await _invokeAdmin('revoke_all', customerId: customerId),
    );
    final count = data['revoked_count'];
    if (count is! int || count < 0) {
      throw const FormatException('Malformed customer push revoke payload');
    }
    return count;
  }

  @override
  Future<CustomerPushSendResult> sendManual(
    String customerId,
    String message,
  ) async {
    final data = await _invokeAdmin(
      'send_manual',
      customerId: customerId,
      message: _manualMessage(message),
    );
    return CustomerPushSendResult.fromJson(_requireMap(data));
  }

  @override
  Future<CustomerPushSendResult> broadcastManual(String message) async {
    final data = await _invokeAdmin(
      'broadcast_manual',
      message: _manualMessage(message),
    );
    return CustomerPushSendResult.fromJson(_requireMap(data));
  }

  @override
  Future<CustomerPushSettings> loadSettings() async {
    final data = await _invokeAdmin('get_settings');
    return CustomerPushSettings.fromJson(_requireMap(data));
  }

  @override
  Future<CustomerPushSettings> updateSettings({
    required int overdueIntervalDays,
  }) async {
    if (overdueIntervalDays < 1 || overdueIntervalDays > 30) {
      throw ArgumentError.value(
        overdueIntervalDays,
        'overdueIntervalDays',
        'Must be between 1 and 30',
      );
    }
    final data = await _invokeAdmin(
      'update_settings',
      overdueIntervalDays: overdueIntervalDays,
    );
    return CustomerPushSettings.fromJson(_requireMap(data));
  }
}
