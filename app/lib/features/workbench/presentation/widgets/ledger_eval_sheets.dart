library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/workbench_models.dart';

void showWorkOrdersSheet(BuildContext context, List<WorkOrderModel> orders) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.9,
      builder: (_, scrollCtrl) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storage_rounded, size: 20),
                const SizedBox(width: 8),
                Text(
                  '幂等工单账本 (work_orders: ${orders.length} 笔)',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: orders.isEmpty
                  ? const Center(child: Text('暂无已落库工单'))
                  : ListView.separated(
                      controller: scrollCtrl,
                      itemCount: orders.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final wo = orders[i];
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    wo.workOrderId,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: wo.replayHits > 0
                                          ? const Color(0xFFFEF3C7)
                                          : const Color(0xFFDCFCE7),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '幂等重放拦截次数: ${wo.replayHits}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              SelectableText(
                                'Idempotency-Key: ${wo.idempotencyKey}  |  Fingerprint: ${wo.payloadFingerprint}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: Color(0xFF64748B),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${wo.ticket.customerName} · ${wo.ticket.unitAddress} · ¥${(wo.ticket.totalFeeCents / 100).toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 12.5),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}

void showEvalJsonlSheet(
  BuildContext context, {
  required List<EvalCaseModel> cases,
  required String jsonl,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      maxChildSize: 0.92,
      builder: (_, scrollCtrl) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.science_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Trace-to-Eval 回归评测集 (${cases.length} 条样本)',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (jsonl.isNotEmpty)
                  FilledButton.tonalIcon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: jsonl));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('已复制 regression_cases.jsonl 到剪贴板'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('复制 JSONL'),
                  ),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: cases.isEmpty
                  ? const Center(
                      child: Text(
                        '先对任意 HITL 挂起单据（如 hitl-01）修正字段并点 Approve，此处即自动生成回归评测样本。',
                      ),
                    )
                  : ListView(
                      controller: scrollCtrl,
                      children: [
                        ...cases.map(
                          (c) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFFBFDBFE),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${c.caseId} · doc=${c.docId} · guards=[${c.guardCodes.join(", ")}]',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  ...c.fieldDiffs.map(
                                    (d) => Text(
                                      'Diff ${d.field}: ${d.rawValue}  -->  ${d.correctedValue}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontFamily: 'monospace',
                                        color: Color(0xFF1E3A8A),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'regression_cases.jsonl 原始导出内容：',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SelectableText(
                            jsonl,
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: Color(0xFFE2E8F0),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
