/// package: lib/core/network/base_repository.dart
/// responsibility: 仓库基类——统一信封解析（code/msg/data）+ Success/Empty/Error 映射。
///
/// Portable MVVM core kernel (decoupled, injectable auth-expiry hook).
/// 原版绑死了 TokenStore / AuthEventBus / SessionReloginCoordinator / AppConstants。
/// 这里把鉴权过期处理抽成可注入钩子 [onAuthExpired] + [authExpiredCodes]，
/// 默认不启用。等你的项目接入登录系统后，再在构造时传入钩子即可。
library;

import 'package:dio/dio.dart';
import 'api_result.dart';

/// 后端统一信封的字段约定。按你的 API 实际字段名调整。
class ApiEnvelopeConfig {
  final String codeField;
  final List<String> messageFields;
  final String dataField;
  final int successCode;

  const ApiEnvelopeConfig({
    this.codeField = 'code',
    this.messageFields = const ['msg', 'message', 'error'],
    this.dataField = 'data',
    this.successCode = 0,
  });
}

abstract class BaseRepository {
  final Dio dio;
  final ApiEnvelopeConfig envelope;

  /// 会话失效钩子：命中 [authExpiredCodes] 时调用，返回展示给用户的文案。
  /// 接入登录系统前传 null（不处理）。
  final Future<String> Function(String? message)? onAuthExpired;

  /// 表示"需要重新登录"的业务 code 集合。默认空。
  final Set<int> authExpiredCodes;

  BaseRepository(
    this.dio, {
    this.envelope = const ApiEnvelopeConfig(),
    this.onAuthExpired,
    this.authExpiredCodes = const {},
  });

  /// 统一请求封装：调用 -> 解信封 -> 映射到 `ApiResult<R>`。
  /// - parser: 把 data 字段转成 R（data 层用 json_cast，禁止裸 cast）
  /// - R 为 void 时无需解析 data
  Future<ApiResult<R>> request<R>({
    required Future<Response<Map<String, dynamic>>> Function(
      CancelToken cancelToken,
    )
    call,
    required R Function(Object? json) parser,
    CancelToken? cancelToken,
    bool treatNullDataAsEmpty = true,
    String? emptyMessage,
  }) async {
    final ct = cancelToken ?? CancelToken();

    try {
      final resp = await call(ct);
      final map = resp.data;
      if (map == null) return ApiError(Exception('Response body is null'));

      final code = _asInt(map[envelope.codeField]);
      final msg = _firstMessage(map);

      if (onAuthExpired != null &&
          code != null &&
          authExpiredCodes.contains(code)) {
        final message = await onAuthExpired!(msg);
        return ApiNeedLogin(message);
      }

      // 业务失败
      if (code != null && code != envelope.successCode) {
        return ApiError(Exception(msg ?? '业务错误'), code: code, message: msg);
      }

      // R 为 void/dynamic/Object? 时无需解析 data
      if (_isVoidLike<R>()) {
        return ApiSuccess<R>(null as R);
      }

      final dataRaw = map[envelope.dataField];
      if (dataRaw == null) {
        if (treatNullDataAsEmpty) {
          return ApiEmpty(
            message: emptyMessage ?? (msg?.isNotEmpty == true ? msg : '暂无数据'),
          );
        }
        return ApiError(Exception('data is null'), code: code, message: msg);
      }

      late final R data;
      try {
        data = parser(dataRaw);
      } catch (e) {
        return ApiError(e, code: code, message: msg);
      }

      if (data == null) {
        if (treatNullDataAsEmpty) {
          return ApiEmpty(
            message: emptyMessage ?? (msg?.isNotEmpty == true ? msg : '暂无数据'),
          );
        }
        return ApiError(Exception('data is null'), code: code, message: msg);
      }

      return ApiSuccess<R>(data);
    } catch (e) {
      return ApiError(e);
    }
  }

  /// 仅当 R 是顶类型（void/dynamic/Object?）时 `Object? <: R` 成立。
  bool _isVoidLike<R>() => <Object?>[] is List<R>;

  String? _firstMessage(Map<String, dynamic> map) {
    for (final f in envelope.messageFields) {
      final s = _asString(map[f]);
      if (s != null) return s;
    }
    return null;
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value == null) return null;
    return int.tryParse(value.toString());
  }

  String? _asString(dynamic value) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? null : text;
  }
}
