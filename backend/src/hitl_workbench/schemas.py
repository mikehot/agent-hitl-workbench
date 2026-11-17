"""Pydantic v2 domain and API contracts for Agent HITL Workbench."""

from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, Field

DocType = Literal["repair_ticket", "inspection_sheet", "vendor_invoice"]
PriorityLevel = Literal["LOW", "NORMAL", "HIGH"]
RunStatus = Literal["completed", "interrupted", "rejected"]


class LineItem(BaseModel):
    name: str = Field(min_length=1)
    qty: int = Field(ge=1, le=100)
    unit_price_cents: int = Field(ge=0)
    subtotal_cents: int = Field(ge=0)


class ExtractedTicket(BaseModel):
    doc_type: DocType
    customer_name: str
    unit_address: str
    contact_phone: str
    issue_summary: str
    priority: PriorityLevel = "NORMAL"
    labor_fee_cents: int = Field(ge=0, default=0)
    parts_fee_cents: int = Field(ge=0, default=0)
    total_fee_cents: int = Field(ge=0, default=0)
    customer_signed: bool = False
    confidence: float = Field(ge=0.0, le=1.0, default=0.9)
    line_items: list[LineItem] = Field(default_factory=list)
    raw_notes: str = ""


class GuardFlag(BaseModel):
    code: str
    severity: Literal["warning", "blocker"]
    field: str | None = None
    message: str


class NodeTraceEvent(BaseModel):
    node: str
    status: Literal["completed", "interrupted", "skipped"]
    duration_ms: float
    detail: str
    timestamp: str


class InterruptPayload(BaseModel):
    reason: str
    doc_id: str
    doc_title: str
    guard_flags: list[GuardFlag]
    proposed_ticket: ExtractedTicket


class StartRunRequest(BaseModel):
    fixture_id: str
    thread_id: str | None = None
    tenant_id: str | None = None


class ResumeDecisionRequest(BaseModel):
    action: Literal["approve", "reject"]
    edited_ticket: ExtractedTicket | None = None
    reviewer_note: str = ""


class FieldDiff(BaseModel):
    field: str
    raw_value: Any
    corrected_value: Any


class WorkOrderRecord(BaseModel):
    work_order_id: str
    thread_id: str
    doc_id: str
    tenant_id: str
    idempotency_key: str
    payload_fingerprint: str
    ticket: ExtractedTicket
    replay_hits: int = 0
    created_at: str


class EvalRegressionCase(BaseModel):
    case_id: str
    thread_id: str
    doc_id: str
    doc_type: DocType
    guard_codes: list[str]
    field_diffs: list[FieldDiff]
    raw_extraction: ExtractedTicket
    expected_truth: ExtractedTicket
    reviewer_note: str = ""
    created_at: str


class RunSnapshot(BaseModel):
    thread_id: str
    doc_id: str
    doc_title: str
    tenant_id: str
    status: RunStatus
    extracted_ticket: ExtractedTicket | None = None
    final_ticket: ExtractedTicket | None = None
    guard_flags: list[GuardFlag] = Field(default_factory=list)
    interrupt_payload: InterruptPayload | None = None
    work_order_id: str | None = None
    idempotent_reused: bool = False
    eval_case_id: str | None = None
    reviewer_note: str = ""
    node_trace: list[NodeTraceEvent] = Field(default_factory=list)
    updated_at: str


class FixtureSummary(BaseModel):
    fixture_id: str
    title: str
    category: Literal["clean_auto", "hitl_review", "adversarial_trap"]
    doc_type: DocType
    tenant_id: str
    description: str
    document_svg: str
    document_text: str
