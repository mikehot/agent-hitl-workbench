library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/base/base_page.dart';
import '../../../core/state/ui_state.dart';
import '../models/workbench_models.dart';
import 'widgets/fixture_document_pane.dart';
import 'widgets/ledger_eval_sheets.dart';
import 'widgets/review_approval_pane.dart';
import 'widgets/trace_diagnostics_pane.dart';
import 'workbench_view_model.dart';

class WorkbenchPage extends BasePage {
  const WorkbenchPage({super.key});

  @override
  ConsumerState<WorkbenchPage> createState() => _WorkbenchPageState();
}

class _WorkbenchPageState
    extends
        BasePageState<WorkbenchPage, WorkbenchViewModel, WorkbenchViewData> {
  int _mobileTabIndex = 0;
  final GlobalKey _reviewPaneKey = GlobalKey();

  @override
  AutoDisposeNotifierProvider<WorkbenchViewModel, UiState<WorkbenchViewData>>
  get viewModelProvider => workbenchViewModelProvider;

  @override
  Color? get backgroundColor => const Color(0xFFF1F5F9);

  @override
  void initData() {
    ref.read(workbenchViewModelProvider.notifier).initialize();
  }

  @override
  void onRetry() {
    ref.read(workbenchViewModelProvider.notifier).initialize();
  }

  @override
  PreferredSizeWidget? buildAppBar(BuildContext context) {
    final uiState = ref.watch(workbenchViewModelProvider);
    final data = switch (uiState) {
      UiSuccess<WorkbenchViewData>(:final data) => data,
      UiError<WorkbenchViewData>(:final previous) => previous,
      UiLoading<WorkbenchViewData>(:final previous) => previous,
      _ => null,
    };

    final isCompactBar = MediaQuery.sizeOf(context).width < 760;

    return AppBar(
      elevation: 0,
      backgroundColor: const Color(0xFF0F172A),
      foregroundColor: Colors.white,
      titleSpacing: 16,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Agent HITL Workbench',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          if (!isCompactBar)
            const Text(
              'LangGraph Stateful Interrupt · Idempotent Ledger · Trace-to-Eval',
              style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
            ),
        ],
      ),
      actions: [
        if (data != null && !isCompactBar) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: OutlinedButton.icon(
              key: const Key('mode_switcher_button'),
              onPressed: () => _showModeDialog(context, data),
              icon: Icon(
                data.mode == WorkbenchMode.sandbox
                    ? Icons.offline_bolt_outlined
                    : Icons.cloud_sync_outlined,
                size: 16,
                color: data.mode == WorkbenchMode.sandbox
                    ? const Color(0xFF38BDF8)
                    : const Color(0xFF4ADE80),
              ),
              label: Text(
                data.mode == WorkbenchMode.sandbox
                    ? '沙盒回放 (Zero-Token)'
                    : '实时后端 (FastAPI)',
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF334155)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            key: const Key('open_work_orders_button'),
            onPressed: () => showWorkOrdersSheet(context, data.workOrders),
            icon: const Icon(
              Icons.receipt_outlined,
              size: 16,
              color: Color(0xFFE2E8F0),
            ),
            label: Text(
              '工单账本 (${data.workOrders.length})',
              style: const TextStyle(fontSize: 12, color: Colors.white),
            ),
          ),
          TextButton.icon(
            key: const Key('open_eval_jsonl_button'),
            onPressed: () => showEvalJsonlSheet(
              context,
              cases: data.evalCases,
              jsonl: data.exportedJsonl,
            ),
            icon: const Icon(
              Icons.science_outlined,
              size: 16,
              color: Color(0xFF93C5FD),
            ),
            label: Text(
              '回归集 JSONL (${data.evalCases.length})',
              style: const TextStyle(fontSize: 12, color: Color(0xFF93C5FD)),
            ),
          ),
          const SizedBox(width: 8),
        ] else if (data != null) ...[
          IconButton(
            key: const Key('mode_switcher_button'),
            tooltip: '切换运行模式',
            onPressed: () => _showModeDialog(context, data),
            icon: Icon(
              data.mode == WorkbenchMode.sandbox
                  ? Icons.offline_bolt_outlined
                  : Icons.cloud_sync_outlined,
              color: const Color(0xFF38BDF8),
            ),
          ),
          IconButton(
            key: const Key('open_work_orders_button'),
            tooltip: '工单账本 (${data.workOrders.length})',
            onPressed: () => showWorkOrdersSheet(context, data.workOrders),
            icon: Badge.count(
              count: data.workOrders.length,
              isLabelVisible: data.workOrders.isNotEmpty,
              child: const Icon(Icons.receipt_outlined),
            ),
          ),
          IconButton(
            key: const Key('open_eval_jsonl_button'),
            tooltip: '回归集 JSONL (${data.evalCases.length})',
            onPressed: () => showEvalJsonlSheet(
              context,
              cases: data.evalCases,
              jsonl: data.exportedJsonl,
            ),
            icon: Badge.count(
              count: data.evalCases.length,
              isLabelVisible: data.evalCases.isNotEmpty,
              child: const Icon(Icons.science_outlined),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget buildContent(BuildContext context, WorkbenchViewData? data) {
    if (data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final vm = ref.read(workbenchViewModelProvider.notifier);

    final leftPane = FixtureDocumentPane(
      data: data,
      onSelectFixture: vm.selectFixture,
      onRunFixture: () {
        vm.runSelectedFixture();
        if (_mobileTabIndex == 0) {
          setState(() => _mobileTabIndex = 1);
        }
      },
    );

    final centerPane = TraceDiagnosticsPane(
      data: data,
      onSelectRun: vm.selectRun,
    );

    final rightPane = ReviewApprovalPane(
      key: _reviewPaneKey,
      data: data,
      onSubmitDecision:
          ({
            required threadId,
            required action,
            editedTicket,
            required reviewerNote,
          }) {
            vm.submitReviewDecision(
              threadId: threadId,
              action: action,
              editedTicket: editedTicket,
              reviewerNote: reviewerNote,
            );
          },
      onOpenEvalSheet: () => showEvalJsonlSheet(
        context,
        cases: data.evalCases,
        jsonl: data.exportedJsonl,
      ),
    );

    return LayoutBuilder(
      builder: (ctx, constraints) {
        if (constraints.maxWidth >= 960) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 384, child: leftPane),
                const SizedBox(width: 12),
                Expanded(flex: 5, child: centerPane),
                const SizedBox(width: 12),
                Expanded(flex: 5, child: rightPane),
              ],
            ),
          );
        }

        final panes = [leftPane, centerPane, rightPane];
        return Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: IndexedStack(index: _mobileTabIndex, children: panes),
              ),
            ),
            NavigationBar(
              selectedIndex: _mobileTabIndex,
              onDestinationSelected: (idx) =>
                  setState(() => _mobileTabIndex = idx),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.description_outlined),
                  label: '1. 单据输入',
                ),
                NavigationDestination(
                  icon: Icon(Icons.account_tree_outlined),
                  label: '2. 状态与门禁',
                ),
                NavigationDestination(
                  icon: Icon(Icons.fact_check_outlined),
                  label: '3. 人工审批',
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _showModeDialog(BuildContext context, WorkbenchViewData data) {
    final urlCtrl = TextEditingController(text: data.backendBaseUrl);
    final vm = ref.read(workbenchViewModelProvider.notifier);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('切换运行数据源模式'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '• 沙盒回放模式：纯客户端确定性状态机，免启动后端即可在浏览器完整体验 interrupt -> 改字 -> resume -> 导出 JSONL。\n'
                '• 实时后端模式：连接本地或远端 Python FastAPI + LangGraph + SQLite 服务。',
                style: TextStyle(fontSize: 12.5, height: 1.45),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlCtrl,
                decoration: const InputDecoration(
                  labelText: 'FastAPI 后端地址',
                  hintText: 'http://127.0.0.1:8095',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (data.mode == WorkbenchMode.sandbox)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                vm.resetSandboxData();
              },
              child: const Text('重置沙盒账本'),
            ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              vm.switchMode(
                mode: WorkbenchMode.sandbox,
                customBaseUrl: urlCtrl.text,
              );
            },
            child: const Text('使用内置沙盒'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              vm.switchMode(
                mode: WorkbenchMode.liveBackend,
                customBaseUrl: urlCtrl.text,
              );
            },
            child: const Text('连接实时 FastAPI'),
          ),
        ],
      ),
    );
  }
}
