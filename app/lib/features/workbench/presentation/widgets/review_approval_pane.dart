library;

import 'package:flutter/material.dart';

import '../../data/sandbox_engine.dart';
import '../../models/workbench_models.dart';

typedef SubmitDecisionCallback =
    void Function({
      required String threadId,
      required String action,
      ExtractedTicketModel? editedTicket,
      required String reviewerNote,
    });

class ReviewApprovalPane extends StatefulWidget {
  final WorkbenchViewData data;
  final SubmitDecisionCallback onSubmitDecision;
  final VoidCallback onOpenEvalSheet;

  const ReviewApprovalPane({
    super.key,
    required this.data,
    required this.onSubmitDecision,
    required this.onOpenEvalSheet,
  });

  @override
  State<ReviewApprovalPane> createState() => _ReviewApprovalPaneState();
}

class _ReviewApprovalPaneState extends State<ReviewApprovalPane> {
  String? _boundThreadId;
  late final TextEditingController _nameCtrl = TextEditingController();
  late final TextEditingController _addrCtrl = TextEditingController();
  late final TextEditingController _phoneCtrl = TextEditingController();
  late final TextEditingController _laborCtrl = TextEditingController();
  late final TextEditingController _partsCtrl = TextEditingController();
  late final TextEditingController _totalCtrl = TextEditingController();
  late final TextEditingController _rawNotesCtrl = TextEditingController();
  late final TextEditingController _reviewerNoteCtrl = TextEditingController();
  bool _signed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncFromActiveRun();
  }

  @override
  void didUpdateWidget(covariant ReviewApprovalPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFromActiveRun();
  }

  void _syncFromActiveRun() {
    final run = widget.data.activeRun;
    if (run == null || run.threadId == _boundThreadId) return;
    _boundThreadId = run.threadId;
    final t = run.finalTicket ?? run.extractedTicket;
    if (t == null) return;
    _nameCtrl.text = t.customerName;
    _addrCtrl.text = t.unitAddress;
    _phoneCtrl.text = t.contactPhone;
    _laborCtrl.text = (t.laborFeeCents / 100).toStringAsFixed(2);
    _partsCtrl.text = (t.partsFeeCents / 100).toStringAsFixed(2);
    _totalCtrl.text = (t.totalFeeCents / 100).toStringAsFixed(2);
    _rawNotesCtrl.text = t.rawNotes;
    _reviewerNoteCtrl.text = run.reviewerNote;
    _signed = t.customerSigned;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addrCtrl.dispose();
    _phoneCtrl.dispose();
    _laborCtrl.dispose();
    _partsCtrl.dispose();
    _totalCtrl.dispose();
    _rawNotesCtrl.dispose();
    _reviewerNoteCtrl.dispose();
    super.dispose();
  }

  int _parseYuanToCents(String raw) {
    final v = double.tryParse(raw.trim()) ?? 0.0;
    return (v * 100).round();
  }

  ExtractedTicketModel _buildDraft(ExtractedTicketModel base) {
    return base.copyWith(
      customerName: _nameCtrl.text.trim(),
      unitAddress: _addrCtrl.text.trim(),
      contactPhone: _phoneCtrl.text.trim(),
      laborFeeCents: _parseYuanToCents(_laborCtrl.text),
      partsFeeCents: _parseYuanToCents(_partsCtrl.text),
      totalFeeCents: _parseYuanToCents(_totalCtrl.text),
      customerSigned: _signed,
      rawNotes: _rawNotesCtrl.text.trim(),
    );
  }

  void _applySmartDemoFix(RunSnapshotModel run) {
    setState(() {
      if (run.docId == 'hitl-01') {
        final expectedCents =
            _parseYuanToCents(_laborCtrl.text) +
            _parseYuanToCents(_partsCtrl.text);
        _totalCtrl.text = (expectedCents / 100).toStringAsFixed(2);
        _reviewerNoteCtrl.text = '核对原件手写涂改处，实收总计应为 ¥200.00';
      } else if (run.docId == 'hitl-02') {
        _addrCtrl.text = '阳光城二期11栋302室';
        _reviewerNoteCtrl.text = '已回拨报修人电话确认精确房号为 11栋302室';
      } else if (run.docId == 'hitl-03') {
        _signed = true;
        _reviewerNoteCtrl.text = '已核实业主授权录音并补录电子签认';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final run = widget.data.activeRun;

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
            child: const Row(
              children: [
                Icon(
                  Icons.fact_check_outlined,
                  size: 18,
                  color: Color(0xFF1E293B),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '3. HITL 人工审批恢复 & Trace-to-Eval 飞轮',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: run == null
                ? const Center(
                    child: Text(
                      '暂无待处理会话',
                      style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                    ),
                  )
                : run.isInterrupted
                ? _buildInterruptedForm(run)
                : _buildClosedReceipt(run),
          ),
        ],
      ),
    );
  }

  Widget _buildInterruptedForm(RunSnapshotModel run) {
    final raw = run.extractedTicket!;
    final draft = _buildDraft(raw);
    final diffs = SandboxWorkbenchEngine.computeDiffs(raw, draft);
    final canQuickFix =
        run.docId == 'hitl-01' ||
        run.docId == 'hitl-02' ||
        run.docId == 'hitl-03';

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: Row(
            children: [
              const Icon(Icons.bolt, size: 18, color: Color(0xFFD97706)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  diffs.isEmpty
                      ? '状态机已暂停在 interrupt()。修正下方风险字段后点击 Approve 将触发 Command(resume=...) 并自动生成回归评测样本。'
                      : '已检测到 ${diffs.length} 处人工字段修正（${diffs.map((d) => d.field).join(", ")}）→ 审批通过后将自动写入 regression_cases.jsonl！',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF92400E),
                  ),
                ),
              ),
              if (canQuickFix) ...[
                const SizedBox(width: 8),
                ActionChip(
                  key: const Key('smart_fix_chip'),
                  label: const Text(
                    '一键填入核实修正值',
                    style: TextStyle(fontSize: 11),
                  ),
                  onPressed: () => _applySmartDemoFix(run),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _field(
                controller: _nameCtrl,
                label: '客户/报修人姓名',
                fieldKey: 'field_customer_name',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _field(
                controller: _phoneCtrl,
                label: '联系电话',
                fieldKey: 'field_contact_phone',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _field(
          controller: _addrCtrl,
          label: '精确单元房号 / 工位地址',
          fieldKey: 'field_unit_address',
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _field(
                controller: _laborCtrl,
                label: '人工费 (元)',
                fieldKey: 'field_labor_yuan',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _field(
                controller: _partsCtrl,
                label: '配件费 (元)',
                fieldKey: 'field_parts_yuan',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _field(
                controller: _totalCtrl,
                label: '实收总计 (元)',
                fieldKey: 'field_total_yuan',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text(
            '客户/验收人已有效签字确认 (customer_signed)',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          value: _signed,
          onChanged: (v) => setState(() => _signed = v),
        ),
        const SizedBox(height: 6),
        _field(
          controller: _rawNotesCtrl,
          label: '单据备注原文 (含注入语句时可清理或直接点驳回)',
          fieldKey: 'field_raw_notes',
          maxLines: 2,
        ),
        const SizedBox(height: 10),
        _field(
          controller: _reviewerNoteCtrl,
          label: '审批人审计备注 (写入工单审计与评测样本)',
          fieldKey: 'field_reviewer_note',
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('reject_run_button'),
                onPressed: () => widget.onSubmitDecision(
                  threadId: run.threadId,
                  action: 'reject',
                  reviewerNote: _reviewerNoteCtrl.text.trim(),
                ),
                icon: const Icon(Icons.block, size: 17),
                label: const Text('驳回拒收 (Reject)'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFB91C1C),
                  side: const BorderSide(color: Color(0xFFFCA5A5)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                key: const Key('approve_resume_button'),
                onPressed: () => widget.onSubmitDecision(
                  threadId: run.threadId,
                  action: 'approve',
                  editedTicket: _buildDraft(raw),
                  reviewerNote: _reviewerNoteCtrl.text.trim(),
                ),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('Approve & Command(resume)'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF15803D),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildClosedReceipt(RunSnapshotModel run) {
    final finalTicket = run.finalTicket ?? run.extractedTicket;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: run.isRejected
                ? const Color(0xFFFEF2F2)
                : const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: run.isRejected
                  ? const Color(0xFFFECACA)
                  : const Color(0xFFBBF7D0),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    run.isRejected ? Icons.cancel_outlined : Icons.verified,
                    color: run.isRejected
                        ? const Color(0xFFB91C1C)
                        : const Color(0xFF15803D),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      run.isRejected
                          ? '单据已被人工风控驳回（0 脏数据落库）'
                          : (run.idempotentReused
                                ? '命中 Idempotency-Key 幂等保护：已复用既有工单（0 重复建单）'
                                : '工单已通过幂等门禁安全落库'),
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: run.isRejected
                            ? const Color(0xFF991B1B)
                            : const Color(0xFF166534),
                      ),
                    ),
                  ),
                ],
              ),
              if (run.workOrderId != null) ...[
                const SizedBox(height: 8),
                SelectableText(
                  '工单编号 (work_order_id): ${run.workOrderId}'
                  '${run.idempotentReused ? "  [IDEMPOTENT_REUSED = true]" : ""}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (run.reviewerNote.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '审计备注：${run.reviewerNote}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF334155),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (run.evalCaseId != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.auto_mode_rounded,
                      size: 18,
                      color: Color(0xFF1D4ED8),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Trace-to-Eval 飞轮已捕获样本：${run.evalCaseId}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E40AF),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: widget.onOpenEvalSheet,
                      child: const Text('查看 JSONL'),
                    ),
                  ],
                ),
                const Text(
                  '本次人工修正已自动转化为结构化 expected_truth 对照样本，可直接用于下一次模型升级或提示词迭代的离线回归门禁。',
                  style: TextStyle(fontSize: 12, color: Color(0xFF1E3A8A)),
                ),
              ],
            ),
          ),
        ],
        if (finalTicket != null && !run.isRejected) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '最终入库结构化字段快照',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF334155),
                  ),
                ),
                const Divider(height: 14),
                Text(
                  '客户：${finalTicket.customerName} (${finalTicket.contactPhone})',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  '地址：${finalTicket.unitAddress}',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  '费用：人工 ¥${(finalTicket.laborFeeCents / 100).toStringAsFixed(2)} + '
                  '配件 ¥${(finalTicket.partsFeeCents / 100).toStringAsFixed(2)} = '
                  '总计 ¥${(finalTicket.totalFeeCents / 100).toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String fieldKey,
    int maxLines = 1,
  }) {
    return TextField(
      key: Key(fieldKey),
      controller: controller,
      maxLines: maxLines,
      onChanged: (_) => setState(() {}),
      style: const TextStyle(fontSize: 12.5),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
      ),
    );
  }
}
