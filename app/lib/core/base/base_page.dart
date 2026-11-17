/// package: lib/core/base/base_page.dart
/// responsibility: 页面基类（对齐 Android BaseActivity）：统一 UiEffect、dialog-loading、
/// 状态自动 toast、状态机 -> content/empty/error 渲染。
///
/// Portable MVVM core kernel (decoupled base page & effect listener).
/// 原版绑死 LoadingDialog / ToastUtil / SessionReloginCoordinator / NetworkErrorHelper /
/// NoNetworkRetryView / StableAssetIcon。这里全部换成内联的最小实现（showDialog +
/// ScaffoldMessenger SnackBar + Icon 默认视图），新项目零额外依赖即可跑。
/// 接入自家 Toast / 设计稿空错图后，覆写 buildEmptyView / buildErrorView / 替换 toast 即可。
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/base_view_model.dart';
import '../state/ui_state.dart';

abstract class BasePage extends ConsumerStatefulWidget {
  const BasePage({super.key});
}

abstract class BasePageState<T extends BasePage, VM extends BaseViewModel<D>, D>
    extends ConsumerState<T> {
  AutoDisposeNotifierProvider<VM, UiState<D>> get viewModelProvider;

  bool get isDarkStatusBarText => true;
  Color get navigationBarColor => Colors.white;
  bool get isDarkNavigationBarIcons => true;

  bool get enablePullRefresh => false;
  Future<void> onRefresh() async {}

  bool get resizeToAvoidBottomInset => true;
  Color? get backgroundColor => null;
  Widget? get bottomNavigationBar => null;
  Widget? get floatingActionButton => null;

  void onRetry() {}

  Widget buildContent(BuildContext context, D? data);

  PreferredSizeWidget? buildAppBar(BuildContext context) => null;
  Widget? buildEmptyView(BuildContext context, String? message) => null;
  Widget? buildErrorView(BuildContext context, String? message) => null;

  bool get useShimmer => false;
  Widget? buildShimmer(BuildContext context) => null;

  bool get autoToastStateMessage => true;
  String? _lastAutoToastMessage;

  StreamSubscription<UiEffect>? _effectSub;
  bool _dialogShowing = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(_overlayStyle);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _listenEffects();
      initData();
    });
  }

  SystemUiOverlayStyle get _overlayStyle => SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: isDarkStatusBarText
        ? Brightness.dark
        : Brightness.light,
    statusBarBrightness: isDarkStatusBarText
        ? Brightness.light
        : Brightness.dark,
    systemNavigationBarColor: navigationBarColor,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: isDarkNavigationBarIcons
        ? Brightness.dark
        : Brightness.light,
  );

  void initData() {}

  void _listenEffects() {
    final vm = ref.read(viewModelProvider.notifier);
    _effectSub = vm.effects.listen(_handleEffect);
  }

  void _handleEffect(UiEffect effect) {
    if (!mounted) return;
    switch (effect) {
      case PopPage():
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        break;
      case ShowToast(:final message):
        _toast(message);
        break;
      case ShowConfirmDialog(:final title, :final content):
        _showConfirmDialog(title, content);
        break;
    }
  }

  /// 最小 toast：SnackBar。接入自家 ToastUtil 后替换这一处即可。
  void _toast(String message) {
    if (!mounted || message.trim().isEmpty) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showConfirmDialog(String title, String content) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showDialogLoading() {
    if (_dialogShowing || !mounted) return;
    _dialogShowing = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
  }

  void _dismissDialogLoading() {
    if (!_dialogShowing) return;
    _dialogShowing = false;
    if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  @override
  void dispose() {
    _effectSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(_overlayStyle);

    ref.listen<UiState<D>>(viewModelProvider, (previous, next) {
      if (!mounted) return;
      final shouldShow =
          next is UiLoading<D> && next.type == LoadingType.dialog;
      if (shouldShow) {
        _showDialogLoading();
      } else {
        _dismissDialogLoading();
      }
    });

    ref.listen<UiState<D>>(viewModelProvider, (previous, next) {
      if (!mounted || !autoToastStateMessage) return;
      final msg = _extractStateMessage(next);
      if (msg == null || msg.trim().isEmpty) return;
      if (msg == _lastAutoToastMessage) return;
      _lastAutoToastMessage = msg;
      _toast(msg);
    });

    final state = ref.watch(viewModelProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _overlayStyle,
      child: Scaffold(
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        backgroundColor: backgroundColor,
        appBar: buildAppBar(context),
        body: _buildBody(context, state),
        bottomNavigationBar: bottomNavigationBar,
        floatingActionButton: floatingActionButton,
      ),
    );
  }

  String? _extractStateMessage(UiState<D> s) {
    if (s is UiError<D>) return s.message;
    if (s is UiEmpty<D>) return s.message;
    return null;
  }

  Widget _buildBody(BuildContext context, UiState<D> state) {
    Widget content = _buildStateContent(context, state);
    if (enablePullRefresh) {
      content = RefreshIndicator(
        onRefresh: onRefresh,
        color: Theme.of(context).primaryColor,
        child: content,
      );
    }
    return content;
  }

  Widget _buildStateContent(BuildContext context, UiState<D> state) {
    return switch (state) {
      UiLoading<D>(type: LoadingType.page) =>
        useShimmer && buildShimmer(context) != null
            ? buildShimmer(context)!
            : const Center(child: CircularProgressIndicator()),
      UiLoading<D>(type: LoadingType.dialog, :final previous) => buildContent(
        context,
        previous,
      ),
      UiSuccess<D>(:final data) => buildContent(context, data),
      UiIdle<D>(:final data) => buildContent(context, data),
      UiEmpty<D>(:final message) =>
        buildEmptyView(context, message) ??
            _DefaultEmptyView(message: message, onRetry: onRetry),
      UiError<D>(:final message, :final previous) =>
        previous != null
            ? buildContent(context, previous)
            : (buildErrorView(context, message) ??
                  _DefaultErrorView(message: message, onRetry: onRetry)),
      _ => buildContent(context, null),
    };
  }
}

class _DefaultEmptyView extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;
  const _DefaultEmptyView({this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox, size: 80, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            message ?? '暂无数据',
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ],
      ),
    );
  }
}

class _DefaultErrorView extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;
  const _DefaultErrorView({this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
          const SizedBox(height: 16),
          Text(
            message ?? '加载失败',
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          if (onRetry != null)
            FilledButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
