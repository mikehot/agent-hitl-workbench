import 'package:agent_hitl_workbench_app/features/workbench/data/sandbox_engine.dart';
import 'package:agent_hitl_workbench_app/features/workbench/models/workbench_models.dart';
import 'package:agent_hitl_workbench_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SandboxWorkbenchEngine enforces idempotency and exports eval JSONL', () {
    final engine = SandboxWorkbenchEngine();

    // 1. Clean auto-approve + duplicate idempotency check
    final clean = engine.startRun('clean-01');
    expect(clean.isCompleted, isTrue);
    expect(clean.idempotentReused, isFalse);

    final dup = engine.startRun('trap-02');
    expect(dup.isCompleted, isTrue);
    expect(dup.idempotentReused, isTrue);
    expect(dup.workOrderId, equals(clean.workOrderId));
    expect(engine.workOrders.length, equals(1));
    expect(engine.workOrders.first.replayHits, equals(1));

    // 2. HITL interrupt -> invalid edit blocked -> valid edit resumes & exports JSONL
    final paused = engine.startRun('hitl-01');
    expect(paused.isInterrupted, isTrue);

    expect(
      () => engine.resumeRun(
        threadId: paused.threadId,
        action: 'approve',
        editedTicket: paused.extractedTicket,
      ),
      throwsA(isA<FormatException>()),
    );

    final fixed = paused.extractedTicket!.copyWith(totalFeeCents: 20000);
    final resumed = engine.resumeRun(
      threadId: paused.threadId,
      action: 'approve',
      editedTicket: fixed,
      reviewerNote: '修正涂改总价为200元',
    );
    expect(resumed.isCompleted, isTrue);
    expect(engine.evalCases.length, equals(1));
    expect(engine.exportJsonl(), contains('EVAL-SBX-'));
  });

  test(
    'FastAPI snake_case JSON payload parses cleanly into RunSnapshotModel',
    () {
      final snap = RunSnapshotModel.fromJson({
        'thread_id': 'run-live-001',
        'doc_id': 'hitl-01',
        'doc_title': '手写涂改单',
        'tenant_id': 'synthetic-prop-01',
        'status': 'completed',
        'work_order_id': 'WO-AB12CD34EF',
        'idempotent_reused': true,
        'eval_case_id': 'EVAL-99887766',
        'reviewer_note': '后端契约对齐检查',
        'updated_at': '2026-11-17T12:00:00Z',
        'guard_flags': [
          {
            'code': 'ARITHMETIC_MISMATCH',
            'severity': 'blocker',
            'field': 'total_fee_cents',
            'message': '算术不一致',
          },
        ],
        'node_trace': [
          {
            'node': 'idempotent_commit',
            'status': 'completed',
            'duration_ms': 2.5,
            'detail': '已复用工单',
            'timestamp': '2026-11-17T12:00:00Z',
          },
        ],
      });
      expect(snap.isCompleted, isTrue);
      expect(snap.idempotentReused, isTrue);
      expect(snap.workOrderId, equals('WO-AB12CD34EF'));
      expect(snap.guardFlags.single.code, equals('ARITHMETIC_MISMATCH'));
    },
  );

  testWidgets(
    '3-pane desktop workbench boots into HITL interrupt, applies smart fix, and exports JSONL',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const ProviderScope(child: AgentHitlWorkbenchApp()),
      );
      await tester.pumpAndSettle();

      // Verify initial seeded interrupted run (hitl-01) is visible across 3 panes
      expect(find.textContaining('ARITHMETIC_MISMATCH'), findsWidgets);
      expect(find.text('回归集 JSONL (0)'), findsOneWidget);
      expect(find.text('工单账本 (0)'), findsOneWidget);

      // Tap smart fix chip -> populates corrected total 200.00
      await tester.tap(find.byKey(const Key('smart_fix_chip')));
      await tester.pumpAndSettle();
      expect(find.textContaining('已检测到 1 处人工字段修正'), findsOneWidget);

      // Tap Approve & Command(resume)
      final approveBtn = find.byKey(const Key('approve_resume_button'));
      await tester.ensureVisible(approveBtn);
      await tester.tap(approveBtn);
      await tester.pumpAndSettle();

      // Work order count and Regression JSONL count both increment to 1
      expect(find.text('工单账本 (1)'), findsOneWidget);
      expect(find.text('回归集 JSONL (1)'), findsOneWidget);
      expect(find.textContaining('Trace-to-Eval 飞轮已捕获样本'), findsOneWidget);
    },
  );

  testWidgets(
    'Narrow mobile (<960px) renders adaptive 3-tab NavigationBar without overflow',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const ProviderScope(child: AgentHitlWorkbenchApp()),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.tap(find.text('2. 状态与门禁'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ARITHMETIC_MISMATCH'), findsWidgets);

      await tester.tap(find.text('3. 人工审批'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('approve_resume_button')), findsOneWidget);
    },
  );

  testWidgets(
    'Unsaved form edits survive responsive resize across 1440px <-> 412px breakpoints',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const ProviderScope(child: AgentHitlWorkbenchApp()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('smart_fix_chip')));
      await tester.pumpAndSettle();
      expect(find.textContaining('已检测到 1 处人工字段修正'), findsOneWidget);

      // Resize down to phone width (tab 0 active), then back to desktop 3-pane
      tester.view.physicalSize = const Size(412, 915);
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(1440, 900);
      await tester.pumpAndSettle();

      expect(find.textContaining('已检测到 1 处人工字段修正'), findsOneWidget);
    },
  );
}
