import 'dart:convert';

/// Lightweight application-owned record used by the Zhirox UI.
/// All network I/O is handled by Supabase; this class only keeps the
/// field-access contract used by the existing screens during migration.
class RecordModel {
  RecordModel({
    Map<String, dynamic>? data,
    Map<String, List<RecordModel>>? expand,
  })  : data = Map<String, dynamic>.from(data ?? const {}),
        expand = Map<String, List<RecordModel>>.from(expand ?? const {});

  factory RecordModel.fromJson(Map<String, dynamic> json) {
    final raw = Map<String, dynamic>.from(json);
    final expansion = <String, List<RecordModel>>{};
    final rawExpand = raw.remove('expand');

    if (rawExpand is Map) {
      for (final entry in rawExpand.entries) {
        final value = entry.value;
        if (value is List) {
          expansion[entry.key.toString()] = value
              .whereType<Map>()
              .map((e) => RecordModel.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        } else if (value is Map) {
          expansion[entry.key.toString()] = [
            RecordModel.fromJson(Map<String, dynamic>.from(value)),
          ];
        }
      }
    }

    return RecordModel(data: raw, expand: expansion);
  }

  final Map<String, dynamic> data;
  final Map<String, List<RecordModel>> expand;

  String get id => getStringValue('id');
  String get created => getStringValue('created');
  String get updated => getStringValue('updated');
  String get collectionId => getStringValue('collectionId');
  String get collectionName => getStringValue('collectionName');

  String getStringValue(String key) {
    final value = data[key];
    if (value == null) return '';
    if (value is String) return value;
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Map || value is List) return jsonEncode(value);
    return value.toString();
  }

  bool getBoolValue(String key) {
    final value = data[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.toLowerCase().trim();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }
    return false;
  }

  double getDoubleValue(String key) {
    final value = data[key];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  int getIntValue(String key) {
    final value = data[key];
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Map<String, dynamic> toJson() {
    final out = Map<String, dynamic>.from(data);
    if (expand.isNotEmpty) {
      out['expand'] = expand.map(
        (key, value) => MapEntry(key, value.map((e) => e.toJson()).toList()),
      );
    }
    return out;
  }
}
