library;

import 'package:flutter/material.dart';

import '../../models/workbench_models.dart';

class TraceDiagnosticsPane extends StatelessWidget {
  final WorkbenchViewData data;
  final ValueChanged<String> onSelectRun;

  const TraceDiagnosticsPane({
    super.key,
    required this.data,
    required this.onSelectRun,
  });

  @override
  Widget build(BuildContext context) {
    final run = data.activeRun;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.account_tree_outlined,
                  size: 18,
                  color: Color(0xFF1E293B),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '2. LangGraph 持久化状态流 & 规则门禁诊断',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
                if (run != null) _RunStatusPill(status: run.status),
              ],
            ),
          ),
          if (data.runs.length > 1)
            Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: data.runs.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (ctx, i) {
                  final item = data.runs[i];
                  final isCurrent = item.threadId == data.activeThreadId;
                  return Center(
                    child: ChoiceChip(
                      selected: isCurrent,
                      label: Text(
                        '${item.docId} · ${item.status}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      onSelected: (_) => onSelectRun(item.threadId),
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                },
              ),
            ),
          Expanded(
            child: run == null
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        '点击左侧「投递状态机」运行选中单据，查看节点耗时与门禁拦截轨迹。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      _ThreadMetaBanner(run: run),
                      const SizedBox(height: 14),
                      const Text(
                        '节点执行时间轴 (StateGraph Execution Trace)',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF334155),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...run.nodeTrace.map((ev) => _NodeTraceTile(event: ev)),
                      const SizedBox(height: 14),
                      Text(
                        '确定性门禁判定 (${run.guardFlags.length} 项触发)',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF334155),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (run.guardFlags.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFBBF7D0)),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.verified_outlined,
                                size: 18,
                                color: Color(0xFF15803D),
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '全部 6 项确定性护栏（算术闭合/精确地址/签字门禁/防注入/上限/置信度）均通过。',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF166534),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        ...run.guardFlags.map((f) => _GuardFlagCard(flag: f)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _RunStatusPill extends StatelessWidget {
  final String status;
  const _RunStatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status) {
      'interrupted' => (
        'INTERRUPTED (等待人工)',
        const Color(0xFFFFEDD5),
        const Color(0xFFC2410C),
      ),
      'rejected' => (
        'REJECTED (已驳回)',
        const Color(0xFFFEE2E2),
        const Color(0xFFB91C1C),
      ),
      _ => (
        'COMPLETED (已闭环)',
        const Color(0xFFDCFCE7),
        const Color(0xFF15803D),
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

class _ThreadMetaBanner extends StatelessWidget {
  final RunSnapshotModel run;
  const _ThreadMetaBanner({required this.run});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            'thread_id: ${run.threadId}   |   doc_id: ${run.docId}',
            style: const TextStyle(
              fontSize: 11.5,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '副作用隔离保证：human_review_gate 在 interrupt() 前零写库；唤醒后由下游 idempotent_commit 唯一落库。',
            style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}

class _NodeTraceTile extends StatelessWidget {
  final NodeTraceModel event;
  const _NodeTraceTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (event.status) {
      'interrupted' => (Icons.pause_circle_filled, const Color(0xFFEA580C)),
      'skipped' => (Icons.skip_next_rounded, const Color(0xFF94A3B8)),
      _ => (Icons.check_circle, const Color(0xFF16A34A)),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          event.node,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      Text(
                        '${event.durationMs.toStringAsFixed(1)} ms',
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    event.detail,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF334155),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuardFlagCard extends StatelessWidget {
  final GuardFlagModel flag;
  const _GuardFlagCard({required this.flag});

  @override
  Widget build(BuildContext context) {
    final isBlocker = flag.isBlocker;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isBlocker ? const Color(0xFFFFF7ED) : const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isBlocker
                ? const Color(0xFFFED7AA)
                : const Color(0xFFBFDBFE),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isBlocker ? Icons.gpp_maybe_outlined : Icons.info_outline,
                  size: 16,
                  color: isBlocker
                      ? const Color(0xFFC2410C)
                      : const Color(0xFF1D4ED8),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    flag.code,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                      color: isBlocker
                          ? const Color(0xFF9A3412)
                          : const Color(0xFF1E40AF),
                    ),
                  ),
                ),
                if (flag.field != null)
                  Text(
                    'field: ${flag.field}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Color(0xFF64748B),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              flag.message,
              style: const TextStyle(fontSize: 12, color: Color(0xFF334155)),
            ),
          ],
        ),
      ),
    );
  }
}
