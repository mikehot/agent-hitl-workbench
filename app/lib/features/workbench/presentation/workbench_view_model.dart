library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_result.dart';
import '../../../core/state/base_view_model.dart';
import '../../../core/state/ui_state.dart';
import '../data/workbench_repository.dart';
import '../models/workbench_models.dart';

final workbenchRepositoryProvider = Provider<WorkbenchRepository>((ref) {
  return WorkbenchRepository();
});

final workbenchViewModelProvider =
    AutoDisposeNotifierProvider<WorkbenchViewModel, UiState<WorkbenchViewData>>(
      WorkbenchViewModel.new,
    );

class WorkbenchViewModel extends BaseViewModel<WorkbenchViewData> {
  static const String defaultBackendUrl = 'http://127.0.0.1:8095';

  WorkbenchMode _mode = WorkbenchMode.sandbox;
  String _baseUrl = defaultBackendUrl;

  WorkbenchRepository get _repo => ref.read(workbenchRepositoryProvider);

  WorkbenchViewData? get _currentData => switch (state) {
    UiSuccess<WorkbenchViewData>(:final data) => data,
    UiIdle<WorkbenchViewData>(:final data) => data,
    UiLoading<WorkbenchViewData>(:final previous) => previous,
    UiError<WorkbenchViewData>(:final previous) => previous,
    _ => null,
  };

  Future<void> initialize() async {
    await launchApiCall(
      requestKey: 'init',
      loadingType: LoadingType.page,
      block: (ct) async {
        // Seed one interrupted HITL run on initial sandbox boot so first-time visitors
        // immediately see the full 3-pane interrupt state without even clicking Run!
        if (_mode == WorkbenchMode.sandbox) {
          final snapRes = await _repo.loadSnapshot(
            mode: _mode,
            baseUrl: _baseUrl,
            cancelToken: ct,
          );
          if (snapRes is ApiSuccess<WorkbenchViewData> &&
              snapRes.data.runs.isEmpty) {
            final seeded = await _repo.startRun(
              mode: _mode,
              baseUrl: _baseUrl,
              fixtureId: 'hitl-01',
              cancelToken: ct,
            );
            if (seeded is ApiSuccess<RunSnapshotModel>) {
              return _repo.loadSnapshot(
                mode: _mode,
                baseUrl: _baseUrl,
                preferredFixtureId: 'hitl-01',
                preferredThreadId: seeded.data.threadId,
                cancelToken: ct,
              );
            }
          }
          return snapRes;
        }
        return _repo.loadSnapshot(
          mode: _mode,
          baseUrl: _baseUrl,
          cancelToken: ct,
        );
      },
    );
  }

  void selectFixture(String fixtureId) {
    final cur = _currentData;
    if (cur == null) return;
    state = UiSuccess(cur.copyWith(selectedFixtureId: fixtureId));
  }

  void selectRun(String threadId) {
    final cur = _currentData;
    if (cur == null) return;
    final matched = cur.runs.where((r) => r.threadId == threadId).firstOrNull;
    state = UiSuccess(
      cur.copyWith(
        activeThreadId: threadId,
        selectedFixtureId: matched?.docId ?? cur.selectedFixtureId,
      ),
    );
  }

  Future<void> runSelectedFixture() async {
    final cur = _currentData;
    if (cur == null) return;
    await launchApiCall(
      requestKey: 'start_run',
      loadingType: LoadingType.none,
      preventDuplicate: true,
      block: (ct) async {
        final runRes = await _repo.startRun(
          mode: cur.mode,
          baseUrl: cur.backendBaseUrl,
          fixtureId: cur.selectedFixtureId,
          cancelToken: ct,
        );
        return switch (runRes) {
          ApiSuccess<RunSnapshotModel>(:final data) => _repo.loadSnapshot(
            mode: cur.mode,
            baseUrl: cur.backendBaseUrl,
            preferredFixtureId: cur.selectedFixtureId,
            preferredThreadId: data.threadId,
            cancelToken: ct,
          ),
          ApiError<RunSnapshotModel>(
            :final exception,
            :final code,
            :final message,
          ) =>
            ApiError(exception, code: code, message: message),
          _ => ApiError(Exception('启动状态机失败')),
        };
      },
    );
  }

  Future<void> submitReviewDecision({
    required String threadId,
    required String action,
    ExtractedTicketModel? editedTicket,
    required String reviewerNote,
  }) async {
    final cur = _currentData;
    if (cur == null) return;
    await launchApiCall(
      requestKey: 'resume_run',
      loadingType: LoadingType.none,
      preventDuplicate: true,
      block: (ct) async {
        final res = await _repo.resumeRun(
          mode: cur.mode,
          baseUrl: cur.backendBaseUrl,
          threadId: threadId,
          action: action,
          editedTicket: editedTicket,
          reviewerNote: reviewerNote,
          cancelToken: ct,
        );
        return switch (res) {
          ApiSuccess<RunSnapshotModel>(:final data) => () async {
            emitEffect(
              ShowToast(
                data.isRejected
                    ? '单据已人工驳回，未写入工单表'
                    : 'Command(resume) 成功：工单 ${data.workOrderId} 已落库${data.evalCaseId != null ? "，已生成评测样本 ${data.evalCaseId}" : ""}',
              ),
            );
            return _repo.loadSnapshot(
              mode: cur.mode,
              baseUrl: cur.backendBaseUrl,
              preferredFixtureId: cur.selectedFixtureId,
              preferredThreadId: data.threadId,
              cancelToken: ct,
            );
          }(),
          ApiError<RunSnapshotModel>(
            :final exception,
            :final code,
            :final message,
          ) =>
            ApiError(exception, code: code, message: message),
          _ => ApiError(Exception('恢复状态机执行失败')),
        };
      },
    );
  }

  Future<void> switchMode({
    required WorkbenchMode mode,
    String? customBaseUrl,
  }) async {
    final prevMode = _mode;
    final prevUrl = _baseUrl;
    _mode = mode;
    if (customBaseUrl != null && customBaseUrl.trim().isNotEmpty) {
      _baseUrl = customBaseUrl.trim();
    }

    final res = await _repo.loadSnapshot(mode: _mode, baseUrl: _baseUrl);
    if (res is ApiSuccess<WorkbenchViewData>) {
      state = UiSuccess(res.data);
      emitEffect(
        ShowToast(
          mode == WorkbenchMode.sandbox
              ? '已切换至内置确定性沙盒（零网络/零Token）'
              : '已连接实时 FastAPI + LangGraph 后端 ($_baseUrl)',
        ),
      );
    } else if (res is ApiError<WorkbenchViewData>) {
      _mode = prevMode;
      _baseUrl = prevUrl;
      emitEffect(ShowToast(res.message ?? '连接后端失败，已保持原模式'));
    }
  }

  Future<void> resetSandboxData() async {
    if (_mode != WorkbenchMode.sandbox) return;
    _repo.resetSandbox();
    await initialize();
    emitEffect(const ShowToast('沙盒工单账本与回归集已重置'));
  }
}
