// lib/core/utils/json_cast.dart
// 职责: JSON 类型安全转换。data 层 fromJson 一律走这里，禁止裸 cast
// （`json['x'] as String?` 在后端返回错类型时会 crash）。
//
// Portable MVVM core kernel (zero external coupling).

String? asString(dynamic v) {
  if (v == null) return null;
  if (v is String) return v;
  if (v is num || v is bool) return v.toString();
  return v.toString();
}

int? asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

double? asDouble(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

bool? asBool(dynamic v) {
  if (v == null) return null;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
  }
  return null;
}

Map<String, dynamic>? asJsonMap(dynamic v) {
  if (v == null) return null;
  if (v is Map<String, dynamic>) return v;
  if (v is Map) {
    if (v.keys.any((key) => key is! String)) return null;
    return Map<String, dynamic>.from(v);
  }
  return null;
}

Map<String, dynamic> asJsonMapOrEmpty(dynamic v) {
  return asJsonMap(v) ?? const <String, dynamic>{};
}

T? asJsonObject<T>(dynamic v, T Function(Map<String, dynamic> json) fromJson) {
  final map = asJsonMap(v);
  if (map == null) return null;
  return fromJson(map);
}

/// 解析对象数组：跳过 null / 非 Map 元素，避免 `e as Map` 在脏数据上 crash。
List<T> asJsonList<T>(
  dynamic v,
  T Function(Map<String, dynamic> json) fromJson,
) {
  if (v is! List) return const [];
  return v
      .whereType<Map>()
      .map((e) => fromJson(Map<String, dynamic>.from(e)))
      .toList();
}
