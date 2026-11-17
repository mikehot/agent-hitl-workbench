library;

import 'package:flutter/material.dart';

import '../../models/workbench_models.dart';

class FixtureDocumentPane extends StatelessWidget {
  final WorkbenchViewData data;
  final ValueChanged<String> onSelectFixture;
  final VoidCallback onRunFixture;

  const FixtureDocumentPane({
    super.key,
    required this.data,
    required this.onSelectFixture,
    required this.onRunFixture,
  });

  @override
  Widget build(BuildContext context) {
    final selected = data.selectedFixture;
    final previewTicket =
        selected?.previewTicket ??
        (data.activeRun?.docId == selected?.fixtureId
            ? data.activeRun?.extractedTicket
            : null);

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
                  Icons.description_outlined,
                  size: 18,
                  color: Color(0xFF1E293B),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '1. 合成单据输入队列 (8 套样本)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
                FilledButton.icon(
                  key: const Key('run_pipeline_button'),
                  onPressed: onRunFixture,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('投递状态机'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                ...data.fixtures.map(
                  (fx) => _FixtureTile(
                    fixture: fx,
                    selected: fx.fixtureId == data.selectedFixtureId,
                    onTap: () => onSelectFixture(fx.fixtureId),
                  ),
                ),
                if (selected != null) ...[
                  const SizedBox(height: 12),
                  _PaperTicketSheet(fixture: selected, ticket: previewTicket),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FixtureTile extends StatelessWidget {
  final FixtureModel fixture;
  final bool selected;
  final VoidCallback onTap;

  const _FixtureTile({
    required this.fixture,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final (badgeText, badgeBg, badgeFg) = switch (fixture.category) {
      'clean_auto' => (
        'AUTO PASS',
        const Color(0xFFDCFCE7),
        const Color(0xFF15803D),
      ),
      'hitl_review' => (
        'HITL INTERRUPT',
        const Color(0xFFFFEDD5),
        const Color(0xFFC2410C),
      ),
      _ => ('TRAP / IDEM', const Color(0xFFFEE2E2), const Color(0xFFB91C1C)),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        key: Key('fixture_tile_${fixture.fixtureId}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? const Color(0xFF2563EB)
                  : const Color(0xFFE2E8F0),
              width: selected ? 1.6 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      badgeText,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: badgeFg,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    fixture.fixtureId,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                fixture.title,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                fixture.description,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF475569),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaperTicketSheet extends StatelessWidget {
  final FixtureModel fixture;
  final ExtractedTicketModel? ticket;

  const _PaperTicketSheet({required this.fixture, required this.ticket});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.receipt_long,
                size: 16,
                color: Color(0xFF334155),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '单据原件仿真 (${fixture.docType})',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF334155),
                  ),
                ),
              ),
              const Text(
                'SYNTHETIC',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF94A3B8),
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const Divider(height: 16),
          SelectableText(
            fixture.documentText,
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              color: Color(0xFF1E293B),
              fontFamily: 'monospace',
            ),
          ),
          if (ticket != null && ticket!.lineItems.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              '配件明细行：',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 4),
            ...ticket!.lineItems.map(
              (item) => Text(
                '• ${item.name} × ${item.qty}  单价 ¥${(item.unitPriceCents / 100).toStringAsFixed(2)}  小计 ¥${(item.subtotalCents / 100).toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF334155),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
