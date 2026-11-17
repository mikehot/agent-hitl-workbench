/// package: lib/core/state/ui_state.dart
/// responsibility: 页面状态（page/dialog loading、success、empty、error）+ UiEffect（一次性事件）
///
/// Portable MVVM core kernel (zero external coupling).
library;

enum LoadingType { none, page, dialog }

/// 页面状态密封类。新页面状态优先直接使用 `UiState<T>`。
sealed class UiState<T> {
  const UiState();
}

/// 初始/空闲（可携带上一次数据）
class UiIdle<T> extends UiState<T> {
  final T? data;
  const UiIdle({this.data});
}

/// 加载中（page/dialog）
/// - dialog：不覆盖 content，做 overlay
/// - page：整页 loading
class UiLoading<T> extends UiState<T> {
  final LoadingType type;
  final T? previous;
  const UiLoading({this.type = LoadingType.page, this.previous});
}

/// 成功
class UiSuccess<T> extends UiState<T> {
  final T data;
  const UiSuccess(this.data);
}

/// 空数据
class UiEmpty<T> extends UiState<T> {
  final String? message;
  final T? previous;
  const UiEmpty({this.message, this.previous});
}

/// 失败（可携带 code/message + 上一次数据）
class UiError<T> extends UiState<T> {
  final Object error;
  final int? code;
  final String? message;
  final T? previous;

  const UiError(this.error, {this.code, this.message, this.previous});
}

/// 一次性事件（toast/dialog/导航等）
sealed class UiEffect {
  const UiEffect();
}

class ShowToast extends UiEffect {
  final String message;
  const ShowToast(this.message);
}

class ShowConfirmDialog extends UiEffect {
  final String title;
  final String content;
  const ShowConfirmDialog({required this.title, required this.content});
}

class PopPage extends UiEffect {
  const PopPage();
}
