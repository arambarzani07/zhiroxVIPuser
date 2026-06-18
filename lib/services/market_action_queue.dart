import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhirox/services/connectivity_service.dart';
import 'package:zhirox/services/pb_service.dart';

class MarketActionQueue {
  static const String _storageKey = 'zhirox_protected_market_actions_v1';
  static final MarketActionQueue instance = MarketActionQueue._();

  MarketActionQueue._();

  StreamSubscription<bool>? _connectionSub;
  bool _isFlushing = false;

  Future<void> init() async {
    _connectionSub ??= ConnectivityService.instance.statusStream.listen((online) {
      if (online) flush();
    });
    if (ConnectivityService.instance.isOnline) {
      await flush();
    }
  }

  Future<int> pendingCount() async {
    final actions = await _readActions();
    return actions.length;
  }

  Future<void> saveDebtAction({
    required String customerId,
    required String description,
    required double amount,
    required String dueDate,
    required String createdBy,
    String? adminId,
    String currency = 'IQD',
    double dollarRate = 0,
    double amountUsd = 0,
    List<Map<String, dynamic>>? items,
    String? createdByName,
    String? marketName,
    String? customCreatedDate,
  }) async {
    await _enqueue({
      'kind': 'debt',
      'created_at': DateTime.now().toIso8601String(),
      'body': {
        'customerId': customerId,
        'description': description,
        'amount': amount,
        'dueDate': dueDate,
        'createdBy': createdBy,
        'adminId': adminId,
        'currency': currency,
        'dollarRate': dollarRate,
        'amountUsd': amountUsd,
        'items': items ?? const <Map<String, dynamic>>[],
        'createdByName': createdByName,
        'marketName': marketName,
        'customCreatedDate': customCreatedDate,
      },
    });
  }

  Future<void> savePaymentAction({
    required String debtId,
    required double amount,
    String? note,
    required String createdBy,
    String? createdByName,
    String? adminId,
  }) async {
    await _enqueue({
      'kind': 'payment',
      'created_at': DateTime.now().toIso8601String(),
      'body': {
        'debtId': debtId,
        'amount': amount,
        'note': note,
        'createdBy': createdBy,
        'createdByName': createdByName,
        'adminId': adminId,
      },
    });
  }

  Future<void> saveUserUpdateAction({
    required String userId,
    required Map<String, dynamic> data,
  }) async {
    await _enqueue({
      'kind': 'user_update',
      'created_at': DateTime.now().toIso8601String(),
      'body': {
        'userId': userId,
        'data': data,
      },
    });
  }

  Future<void> flush() async {
    if (_isFlushing || !ConnectivityService.instance.isOnline) return;
    _isFlushing = true;
    try {
      final actions = await _readActions();
      if (actions.isEmpty) return;

      final remaining = <Map<String, dynamic>>[];
      for (final action in actions) {
        try {
          await _run(action);
        } catch (_) {
          remaining.add(action);
        }
      }
      await _writeActions(remaining);
    } finally {
      _isFlushing = false;
    }
  }

  Future<void> _enqueue(Map<String, dynamic> action) async {
    final actions = await _readActions();
    actions.add(action);
    await _writeActions(actions);
  }

  Future<void> _run(Map<String, dynamic> action) async {
    final kind = action['kind'] as String? ?? '';
    final body = Map<String, dynamic>.from(action['body'] as Map? ?? const {});

    switch (kind) {
      case 'debt':
        await PBService.createDebt(
          customerId: body['customerId'] as String? ?? '',
          description: body['description'] as String? ?? '',
          amount: _asDouble(body['amount']),
          dueDate: body['dueDate'] as String? ?? '',
          createdBy: body['createdBy'] as String? ?? '',
          adminId: body['adminId'] as String?,
          currency: body['currency'] as String? ?? 'IQD',
          dollarRate: _asDouble(body['dollarRate']),
          amountUsd: _asDouble(body['amountUsd']),
          items: _asItems(body['items']),
          createdByName: body['createdByName'] as String?,
          marketName: body['marketName'] as String?,
          customCreatedDate: body['customCreatedDate'] as String?,
        );
        break;
      case 'payment':
        await PBService.createPayment(
          debtId: body['debtId'] as String? ?? '',
          amount: _asDouble(body['amount']),
          note: body['note'] as String?,
          createdBy: body['createdBy'] as String? ?? '',
          createdByName: body['createdByName'] as String?,
          adminId: body['adminId'] as String?,
        );
        break;
      case 'user_update':
        await PBService.updateUser(
          body['userId'] as String? ?? '',
          Map<String, dynamic>.from(body['data'] as Map? ?? const {}),
        );
        break;
    }
  }

  Future<List<Map<String, dynamic>>> _readActions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    } catch (error) {
      debugPrint('Protected action queue reset');
      await prefs.remove(_storageKey);
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> _writeActions(List<Map<String, dynamic>> actions) async {
    final prefs = await SharedPreferences.getInstance();
    if (actions.isEmpty) {
      await prefs.remove(_storageKey);
      return;
    }
    await prefs.setString(_storageKey, jsonEncode(actions));
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  List<Map<String, dynamic>> _asItems(dynamic value) {
    if (value is List) {
      return value.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    }
    return const <Map<String, dynamic>>[];
  }
}
