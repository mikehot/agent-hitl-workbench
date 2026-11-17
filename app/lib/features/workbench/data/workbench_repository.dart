library;

import 'package:dio/dio.dart';

import '../../../core/network/api_result.dart';
import '../../../core/utils/json_cast.dart';
import '../models/workbench_models.dart';
import 'sandbox_engine.dart';

class WorkbenchRepository {
  final Dio _dio;
  final SandboxWorkbenchEngine _sandbox;

  WorkbenchRepository({Dio? dio, SandboxWorkbenchEngine? sandbox})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
            ),
          ),
      _sandbox = sandbox ?? SandboxWorkbenchEngine();

  Future<ApiResult<WorkbenchViewData>> loadSnapshot({
    required WorkbenchMode mode,
    required String baseUrl,
    String? preferredFixtureId,
    String? preferredThreadId,
    CancelToken? cancelToken,
  }) async {
    if (mode == WorkbenchMode.sandbox) {
      final fixtures = _sandbox.fixtures;
      final selectedFixtureId =
          preferredFixtureId ??
          (fixtures.isNotEmpty ? fixtures.first.fixtureId : '');
      final runs = _sandbox.runs;
      final activeThreadId =
          preferredThreadId ?? (runs.isNotEmpty ? runs.first.threadId : null);
      return ApiSuccess(
        WorkbenchViewData(
          mode: mode,
          backendBaseUrl: baseUrl,
          fixtures: fixtures,
          selectedFixtureId: selectedFixtureId,
          runs: runs,
          activeThreadId: activeThreadId,
          workOrders: _sandbox.workOrders,
          evalCases: _sandbox.evalCases,
          exportedJsonl: _sandbox.exportJsonl(),
        ),
      );
    }

    try {
      final root = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final resList = await Future.wait<Response<dynamic>>([
        _dio.get<dynamic>('$root/api/v1/fixtures', cancelToken: cancelToken),
        _dio.get<dynamic>('$root/api/v1/runs', cancelToken: cancelToken),
        _dio.get<dynamic>('$root/api/v1/work-orders', cancelToken: cancelToken),
        _dio.get<dynamic>('$root/api/v1/eval-cases', cancelToken: cancelToken),
        _dio.get<dynamic>(
          '$root/api/v1/eval-cases/export.jsonl',
          options: Options(responseType: ResponseType.plain),
          cancelToken: cancelToken,
        ),
      ]);

      final fixtures = asJsonList(resList[0].data, FixtureModel.fromJson);
      final runs = asJsonList(resList[1].data, RunSnapshotModel.fromJson);
      final workOrders = asJsonList(resList[2].data, WorkOrderModel.fromJson);
      final evalCases = asJsonList(resList[3].data, EvalCaseModel.fromJson);
      final jsonl = asString(resList[4].data) ?? '';

      final selectedFixtureId =
          preferredFixtureId ??
          (fixtures.isNotEmpty ? fixtures.first.fixtureId : '');
      final activeThreadId =
          preferredThreadId ?? (runs.isNotEmpty ? runs.first.threadId : null);

      return ApiSuccess(
        WorkbenchViewData(
          mode: mode,
          backendBaseUrl: baseUrl,
          fixtures: fixtures,
          selectedFixtureId: selectedFixtureId,
          runs: runs,
          activeThreadId: activeThreadId,
          workOrders: workOrders,
          evalCases: evalCases,
          exportedJsonl: jsonl,
        ),
      );
    } on DioException catch (e) {
      return ApiError(
        e,
        code: e.response?.statusCode,
        message: _extractDioError(e, baseUrl),
      );
    } catch (e) {
      return ApiError(e, message: e.toString());
    }
  }

  Future<ApiResult<RunSnapshotModel>> startRun({
    required WorkbenchMode mode,
    required String baseUrl,
    required String fixtureId,
    CancelToken? cancelToken,
  }) async {
    if (mode == WorkbenchMode.sandbox) {
      try {
        return ApiSuccess(_sandbox.startRun(fixtureId));
      } catch (e) {
        return ApiError(e, message: e.toString());
      }
    }

    try {
      final root = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final resp = await _dio.post<dynamic>(
        '$root/api/v1/runs',
        data: {'fixture_id': fixtureId},
        cancelToken: cancelToken,
      );
      final map = asJsonMap(resp.data);
      if (map == null) {
        return ApiError(const FormatException('Invalid run snapshot JSON'));
      }
      return ApiSuccess(RunSnapshotModel.fromJson(map));
    } on DioException catch (e) {
      return ApiError(
        e,
        code: e.response?.statusCode,
        message: _extractDioError(e, baseUrl),
      );
    } catch (e) {
      return ApiError(e, message: e.toString());
    }
  }

  Future<ApiResult<RunSnapshotModel>> resumeRun({
    required WorkbenchMode mode,
    required String baseUrl,
    required String threadId,
    required String action,
    ExtractedTicketModel? editedTicket,
    String reviewerNote = '',
    CancelToken? cancelToken,
  }) async {
    if (mode == WorkbenchMode.sandbox) {
      try {
        final snap = _sandbox.resumeRun(
          threadId: threadId,
          action: action,
          editedTicket: editedTicket,
          reviewerNote: reviewerNote,
        );
        return ApiSuccess(snap);
      } catch (e) {
        return ApiError(e, message: e.toString());
      }
    }

    try {
      final root = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final resp = await _dio.post<dynamic>(
        '$root/api/v1/runs/$threadId/resume',
        data: {
          'action': action,
          if (editedTicket != null) 'edited_ticket': editedTicket.toJson(),
          'reviewer_note': reviewerNote,
        },
        cancelToken: cancelToken,
      );
      final map = asJsonMap(resp.data);
      if (map == null) {
        return ApiError(const FormatException('Invalid resumed snapshot JSON'));
      }
      return ApiSuccess(RunSnapshotModel.fromJson(map));
    } on DioException catch (e) {
      return ApiError(
        e,
        code: e.response?.statusCode,
        message: _extractDioError(e, baseUrl),
      );
    } catch (e) {
      return ApiError(e, message: e.toString());
    }
  }

  void resetSandbox() {
    _sandbox.reset();
  }

  String _extractDioError(DioException e, String baseUrl) {
    final body = asJsonMap(e.response?.data);
    final detail = asString(body?['detail']);
    if (detail != null && detail.isNotEmpty) {
      return detail;
    }
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return '无法连接后端 $baseUrl（请先执行 uvicorn hitl_workbench.main:app --port 8095 或切回内置沙盒模式）';
    }
    return e.message ?? '网络请求失败';
  }
}
