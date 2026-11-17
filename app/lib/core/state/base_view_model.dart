/// package: lib/core/state/base_view_model.dart
/// responsibility: MVVM 基类（Riverpod AutoDisposeNotifier）——请求编排 + 状态收敛 + effect。
///
/// Portable MVVM core kernel (decoupled request lifecycle & UI state).
/// 剥离了 SessionReloginCoordinator / AuthSessionExpiryHandler / ErrorMapper / providers.dart：
/// - 错误文案改成可覆写的 [mapError]（默认 message ?? e.toString()）。
/// - 会话失效处理留作可覆写的 [onNeedLogin] 钩子，默认 no-op。
/// 请求生命周期机制（取消 / 防重复 / dispose 哨兵）保持原样。
library;

import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/api_result.dart';
import 'ui_state.dart';

mixin ViewModelRequestSupport {
  /// VM 请求生命周期（取消、防重复、dispose 防写入）。不绑定具体 State 形态。

  final Map<String, CancelToken> _cancelMap = {};
  final Set<String> _runningKeys = {};

  bool _disposed = false;
  bool get isDisposed => _disposed;

  @protected
  void initViewModelLifecycle(Ref ref) {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      for (final ct in _cancelMap.values) {
        if (!ct.isCancelled) ct.cancel('disposed');
      }
      _cancelMap.clear();
      _runningKeys.clear();
      disposeViewModelResources();
    });
  }

  @protected
  void disposeViewModelResources() {}

  void cancelRequest(String requestKey, {String reason = 'manual cancel'}) {
    final ct = _cancelMap.remove(requestKey);
    if (ct != null && !ct.isCancelled) ct.cancel(reason);
    _runningKeys.remove(requestKey);
  }

  void cancelAllRequests({String reason = 'cancel all'}) {
    for (final ct in _cancelMap.values) {
      if (!ct.isCancelled) ct.cancel(reason);
    }
    _cancelMap.clear();
    _runningKeys.clear();
  }

  CancelToken _prepareCancelToken(
    String requestKey, {
    bool cancelPrevious = true,
  }) {
    if (cancelPrevious) {
      final old = _cancelMap[requestKey];
      if (old != null && !old.isCancelled) old.cancel('cancel previous');
    }
    final ct = CancelToken();
    _cancelMap[requestKey] = ct;
    return ct;
  }

  bool _tryEnter(String requestKey, {bool preventDuplicate = false}) {
    if (!preventDuplicate) return true;
    if (_runningKeys.contains(requestKey)) return false;
    _runningKeys.add(requestKey);
    return true;
  }

  void _leave(String requestKey) => _runningKeys.remove(requestKey);

  /// 互斥执行：同一 requestKey 在飞时重复调用直接丢弃返回 null（防按钮重复点击）。
  @protected
  Future<R?> runExclusive<R>({
    required String requestKey,
    required Future<R> Function() block,
  }) async {
    if (!_tryEnter(requestKey, preventDuplicate: true)) return null;
    try {
      return await block();
    } finally {
      _leave(requestKey);
    }
  }
}

mixin UiStateViewModelSupport<T> on ViewModelRequestSupport {
  /// UiState VM 共用能力（请求编排 + 状态收敛 + effect）。

  // ignore: deprecated_member_use
  AutoDisposeNotifierProviderRef<UiState<T>> get ref;
  UiState<T> get state;
  set state(UiState<T> value);

  final _effects = StreamController<UiEffect>.broadcast();
  Stream<UiEffect> get effects => _effects.stream;

  @protected
  void initBaseViewModelLifecycle() {
    initViewModelLifecycle(ref);
  }

  @override
  @protected
  void disposeViewModelResources() {
    _effects.close();
  }

  void emitEffect(UiEffect effect) {
    if (!_effects.isClosed) _effects.add(effect);
  }

  void showToast(String message) => emitEffect(ShowToast(message));

  /// 错误对象 -> 用户文案。子类可覆写以接入 ErrorMapper / 国际化 / 网络错误细分。
  @protected
  String mapError(Object error, {int? code, String? message}) {
    if (message != null && message.trim().isNotEmpty) return message;
    return error.toString();
  }

  /// 会话失效钩子。接入登录系统后覆写：跳登录页 / 清理 token 等。默认 no-op。
  @protected
  Future<void> onNeedLogin({String? message}) async {}

  /// 统一执行一次 Api 调用并落到 `UiState<T>`。
  Future<void> launchApiCall({
    required String requestKey,
    LoadingType loadingType = LoadingType.page,
    bool cancelPrevious = true,
    bool preventDuplicate = false,
    bool toastOnError = true,
    String? emptyMessage,
    required Future<ApiResult<T>> Function(CancelToken cancelToken) block,
  }) async {
    if (!_tryEnter(requestKey, preventDuplicate: preventDuplicate)) return;

    final previous = _extractData(state);
    final ct = _prepareCancelToken(requestKey, cancelPrevious: cancelPrevious);

    state = UiLoading(type: loadingType, previous: previous);

    try {
      final result = await block(ct);
      if (_disposed) return;
      if (ct.isCancelled) {
        state = UiIdle(data: previous);
        return;
      }

      switch (result) {
        case ApiSuccess<T>():
          state = UiSuccess(result.data);
          break;
        case ApiEmpty<T>():
          state = UiEmpty(
            message: result.message ?? emptyMessage ?? '暂无数据',
            previous: previous,
          );
          break;
        case ApiNeedLogin<T>():
          await onNeedLogin(message: result.message);
          state = UiError(
            Exception(result.message),
            message: result.message,
            previous: previous,
          );
          if (toastOnError) emitEffect(ShowToast(result.message));
          break;
        case ApiError<T>():
          final msg = mapError(
            result.exception,
            code: result.code,
            message: result.message,
          );
          state = UiError(
            result.exception,
            code: result.code,
            message: msg,
            previous: previous,
          );
          if (toastOnError) emitEffect(ShowToast(msg));
          break;
        default:
          state = UiIdle(data: previous);
          break;
      }
    } catch (e) {
      if (_disposed) return;
      if (ct.isCancelled) {
        state = UiIdle(data: previous);
        return;
      }
      final msg = mapError(e);
      state = UiError(e, message: msg, previous: previous);
      if (toastOnError) emitEffect(ShowToast(msg));
    } finally {
      _leave(requestKey);
      if (identical(_cancelMap[requestKey], ct)) {
        _cancelMap.remove(requestKey);
      }
    }
  }

  /// 仅用于"操作类请求"（按钮提交等），不一定改变整页 UiState。
  Future<void> launchAction({
    required String requestKey,
    bool cancelPrevious = true,
    bool preventDuplicate = true,
    bool toastOnError = true,
    bool toastOnSuccess = false,
    String? successMessage,
    required Future<ApiResult<void>> Function(CancelToken cancelToken) block,
    VoidCallback? onSuccess,
  }) async {
    if (!_tryEnter(requestKey, preventDuplicate: preventDuplicate)) return;

    final previous = _extractData(state);
    final ct = _prepareCancelToken(requestKey, cancelPrevious: cancelPrevious);

    state = UiLoading(type: LoadingType.dialog, previous: previous);

    try {
      final result = await block(ct);
      if (_disposed) return;
      if (ct.isCancelled) {
        state = UiIdle(data: previous);
        return;
      }

      switch (result) {
        case ApiSuccess<void>():
          state = UiIdle(data: previous);
          if (toastOnSuccess && successMessage != null) {
            emitEffect(ShowToast(successMessage));
          }
          onSuccess?.call();
          break;
        case ApiError<void>():
          final msg = mapError(
            result.exception,
            code: result.code,
            message: result.message,
          );
          state = UiIdle(data: previous);
          if (toastOnError) emitEffect(ShowToast(msg));
          break;
        case ApiNeedLogin<void>():
          await onNeedLogin(message: result.message);
          state = UiIdle(data: previous);
          if (toastOnError) emitEffect(ShowToast(result.message));
          break;
        default:
          state = UiIdle(data: previous);
          break;
      }
    } catch (e) {
      if (_disposed) return;
      state = UiIdle(data: previous);
      if (!ct.isCancelled && toastOnError) {
        emitEffect(ShowToast(mapError(e)));
      }
    } finally {
      _leave(requestKey);
      if (identical(_cancelMap[requestKey], ct)) {
        _cancelMap.remove(requestKey);
      }
    }
  }

  void setSuccess(T data) {
    if (_disposed) return;
    state = UiSuccess(data);
  }

  void setEmpty({String? message}) {
    if (_disposed) return;
    state = UiEmpty(message: message);
  }

  void setIdle({T? data}) {
    if (_disposed) return;
    state = UiIdle(data: data);
  }

  T? _extractData(UiState<T> s) {
    return switch (s) {
      UiSuccess<T>() => s.data,
      UiIdle<T>() => s.data,
      UiLoading<T>() => s.previous,
      UiEmpty<T>() => s.previous,
      UiError<T>() => s.previous,
    };
  }
}

/// 非 family MVVM 基类（统一请求编排 + 状态收敛 + effect）。
abstract class BaseViewModel<T> extends AutoDisposeNotifier<UiState<T>>
    with ViewModelRequestSupport, UiStateViewModelSupport<T> {
  @override
  UiState<T> build() {
    initBaseViewModelLifecycle();
    return const UiIdle();
  }
}
