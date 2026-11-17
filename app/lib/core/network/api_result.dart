/// package: lib/core/network/api_result.dart
/// responsibility: 网络结果统一封装（Success/Error/Loading/Empty/NeedLogin）
///
/// Portable MVVM core kernel (zero external coupling).
library;

sealed class ApiResult<T> {
  const ApiResult();
}

class ApiSuccess<T> extends ApiResult<T> {
  final T data;
  const ApiSuccess(this.data);
}

class ApiError<T> extends ApiResult<T> {
  final Object exception;
  final int? code;
  final String? message;
  const ApiError(this.exception, {this.code, this.message});
}

class ApiLoading<T> extends ApiResult<T> {
  const ApiLoading();
}

class ApiEmpty<T> extends ApiResult<T> {
  final String? message;
  const ApiEmpty({this.message});
}

/// 需要登录（通常由 token 过期触发）。新项目接入登录系统前一般不会用到。
class ApiNeedLogin<T> extends ApiResult<T> {
  final String message;
  const ApiNeedLogin(this.message);
}

class NeedLoginException implements Exception {
  final String? message;
  const NeedLoginException([this.message]);

  @override
  String toString() => message ?? 'Need login';
}
