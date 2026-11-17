"""Deterministic validation guardrails bounding probabilistic VLM/LLM extraction."""

from __future__ import annotations

import re

from hitl_workbench.schemas import ExtractedTicket, FieldDiff, GuardFlag

HIGH_VALUE_SIGNATURE_THRESHOLD_CENTS = 100_000  # CNY 1,000.00
AMOUNT_SANITY_CAP_CENTS = 2_000_000  # CNY 20,000.00
MIN_AUTO_APPROVE_CONFIDENCE = 0.85

_INJECTION_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"ignore\s+(all\s+)?previous\s+instructions", re.IGNORECASE),
    re.compile(r"disregard\s+(all\s+)?prior\s+rules", re.IGNORECASE),
    re.compile(r"system\s+prompt", re.IGNORECASE),
    re.compile(r"approve\s+.*without\s+human\s+review", re.IGNORECASE),
    re.compile(r"bypass\s+(guard|review|validation)", re.IGNORECASE),
    re.compile(r"忽略(以上|之前|所有)(指令|规则)"),
    re.compile(r"(跳过|绕过)(人工)?(复核|审批)"),
)

_AMBIGUOUS_ADDRESS_MARKERS: tuple[str, ...] = (
    "疑似",
    "待确认",
    "看不清",
    "??",
    "未知",
    "模糊",
)

_PHONE_RE = re.compile(r"^1[3-9]\d{9}$|^0\d{2,3}-?\d{7,8}$")


def evaluate_guards(ticket: ExtractedTicket) -> list[GuardFlag]:
    """Run deterministic rules over an ExtractedTicket and return all triggered flags."""
    flags: list[GuardFlag] = []

    # G1: Line-item & fee arithmetic closure
    if ticket.line_items:
        computed_parts = 0
        for idx, item in enumerate(ticket.line_items):
            expected_sub = item.qty * item.unit_price_cents
            if item.subtotal_cents != expected_sub:
                flags.append(
                    GuardFlag(
                        code="LINE_ITEM_SUBTOTAL_MISMATCH",
                        severity="blocker",
                        field=f"line_items[{idx}].subtotal_cents",
                        message=(
                            f"配件「{item.name}」数量({item.qty})×单价({item.unit_price_cents}分)"
                            f"={expected_sub}分，与小计({item.subtotal_cents}分)不一致。"
                        ),
                    )
                )
            computed_parts += item.subtotal_cents
        if computed_parts != ticket.parts_fee_cents:
            flags.append(
                GuardFlag(
                    code="PARTS_SUM_MISMATCH",
                    severity="blocker",
                    field="parts_fee_cents",
                    message=(
                        f"配件明细合计({computed_parts}分)与配件费字段"
                        f"({ticket.parts_fee_cents}分)不一致。"
                    ),
                )
            )

    expected_total = ticket.labor_fee_cents + ticket.parts_fee_cents
    if ticket.total_fee_cents != expected_total:
        flags.append(
            GuardFlag(
                code="ARITHMETIC_MISMATCH",
                severity="blocker",
                field="total_fee_cents",
                message=(
                    f"人工费({ticket.labor_fee_cents}分)+配件费({ticket.parts_fee_cents}分)"
                    f"={expected_total}分，不等于总计({ticket.total_fee_cents}分)。"
                ),
            )
        )

    # G2: Required fields & concrete unit address check
    if not ticket.customer_name.strip():
        flags.append(
            GuardFlag(
                code="MISSING_CUSTOMER_NAME",
                severity="blocker",
                field="customer_name",
                message="客户/报修人姓名为空。",
            )
        )

    addr = ticket.unit_address.strip()
    has_concrete_unit = any(tok in addr for tok in ("室", "号", "层", "车库", "机房", "仓"))
    if not addr or any(m in addr for m in _AMBIGUOUS_ADDRESS_MARKERS) or not has_concrete_unit:
        flags.append(
            GuardFlag(
                code="AMBIGUOUS_UNIT_ADDRESS",
                severity="blocker",
                field="unit_address",
                message=(
                    f"地址「{addr or '(空)'}」含模糊标记或缺少精确房号/工位，需人工核实防串单。"
                ),
            )
        )

    if not _PHONE_RE.match(ticket.contact_phone.strip()):
        flags.append(
            GuardFlag(
                code="INVALID_CONTACT_PHONE",
                severity="warning",
                field="contact_phone",
                message=f"联系电话「{ticket.contact_phone}」格式异常。",
            )
        )

    # G3: Signature gate on high-value tickets & vendor invoices
    if (
        ticket.total_fee_cents >= HIGH_VALUE_SIGNATURE_THRESHOLD_CENTS
        or ticket.doc_type == "vendor_invoice"
    ) and not ticket.customer_signed:
        flags.append(
            GuardFlag(
                code="HIGH_VALUE_UNSIGNED",
                severity="blocker",
                field="customer_signed",
                message=(
                    f"总金额({ticket.total_fee_cents / 100:.2f}元)达高价值/结算单门槛，"
                    "但未检测到有效签字确认。"
                ),
            )
        )

    # G4: Sanity cap
    if ticket.total_fee_cents > AMOUNT_SANITY_CAP_CENTS:
        flags.append(
            GuardFlag(
                code="AMOUNT_SANITY_CAP_EXCEEDED",
                severity="blocker",
                field="total_fee_cents",
                message=(
                    f"总金额({ticket.total_fee_cents / 100:.2f}元)超过单笔自动放行上限"
                    f"({AMOUNT_SANITY_CAP_CENTS / 100:.2f}元)。"
                ),
            )
        )

    # G5: Prompt-injection defense across free-text fields
    combined_text = "\n".join(
        [ticket.customer_name, ticket.unit_address, ticket.issue_summary, ticket.raw_notes]
    )
    for pattern in _INJECTION_PATTERNS:
        if pattern.search(combined_text):
            flags.append(
                GuardFlag(
                    code="PROMPT_INJECTION_SUSPECTED",
                    severity="blocker",
                    field="raw_notes",
                    message=(
                        f"检测到疑似提示词越权指令片段（规则: {pattern.pattern}），强制转人工。"
                    ),
                )
            )
            break

    # G6: Model confidence floor
    if ticket.confidence < MIN_AUTO_APPROVE_CONFIDENCE:
        flags.append(
            GuardFlag(
                code="LOW_CONFIDENCE",
                severity="blocker",
                field="confidence",
                message=(
                    f"抽取置信度({ticket.confidence:.2f})低于自动放行阈值"
                    f"({MIN_AUTO_APPROVE_CONFIDENCE:.2f})。"
                ),
            )
        )

    return flags


def has_blocker(flags: list[GuardFlag]) -> bool:
    return any(f.severity == "blocker" for f in flags)


def compute_ticket_diffs(
    raw: ExtractedTicket,
    corrected: ExtractedTicket,
) -> list[FieldDiff]:
    """Compute deterministic field-level diffs between model extraction and human approval."""
    raw_dump = raw.model_dump()
    corr_dump = corrected.model_dump()
    diffs: list[FieldDiff] = []
    for key, raw_val in raw_dump.items():
        corr_val = corr_dump[key]
        if raw_val != corr_val:
            diffs.append(FieldDiff(field=key, raw_value=raw_val, corrected_value=corr_val))
    return diffs
