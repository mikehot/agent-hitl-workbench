"""Integration tests for LangGraph HITL checkpoint durability, side-effect isolation, and ledger."""

from pathlib import Path

import pytest

from hitl_workbench.config import Settings
from hitl_workbench.fixtures import get_fixture
from hitl_workbench.graph import InvalidHumanOverrideError, WorkbenchRuntime
from hitl_workbench.ledger import IdempotencyConflictError
from hitl_workbench.schemas import ResumeDecisionRequest


def _make_settings(tmp_path: Path) -> Settings:
    return Settings(mode="replay", sqlite_path=str(tmp_path / "workbench.db"))


async def test_clean_fixture_auto_commits_and_duplicate_reuses_idempotently(
    tmp_path: Path,
) -> None:
    rt = WorkbenchRuntime(_make_settings(tmp_path))
    await rt.start()
    try:
        snap1 = await rt.start_run(fixture_id="clean-01", thread_id="run-clean-1")
        assert snap1.status == "completed"
        assert snap1.work_order_id is not None
        assert snap1.idempotent_reused is False
        assert snap1.eval_case_id is None

        # trap-02 shares source_doc_key DOC-CUIZHU-1202-LOCK with clean-01
        snap2 = await rt.start_run(fixture_id="trap-02", thread_id="run-dup-2")
        assert snap2.status == "completed"
        assert snap2.work_order_id == snap1.work_order_id
        assert snap2.idempotent_reused is True

        orders = await rt.ledger.list_work_orders()
        assert len(orders) == 1
        assert orders[0].replay_hits == 1
    finally:
        await rt.close()


async def test_idempotency_conflict_raises_when_payload_tampered(tmp_path: Path) -> None:
    rt = WorkbenchRuntime(_make_settings(tmp_path))
    await rt.start()
    try:
        fx = get_fixture("clean-01")
        await rt.ledger.commit_work_order(
            thread_id="t1",
            doc_id=fx.fixture_id,
            tenant_id=fx.tenant_id,
            source_doc_key=fx.source_doc_key,
            ticket=fx.replay_extraction,
        )
        tampered = fx.replay_extraction.model_copy(
            update={"labor_fee_cents": 9_000, "total_fee_cents": 24_000}
        )
        with pytest.raises(IdempotencyConflictError):
            await rt.ledger.commit_work_order(
                thread_id="t2",
                doc_id=fx.fixture_id,
                tenant_id=fx.tenant_id,
                source_doc_key=fx.source_doc_key,
                ticket=tampered,
            )
    finally:
        await rt.close()


async def test_hitl_interrupt_survives_full_runtime_restart_and_exports_eval_case(
    tmp_path: Path,
) -> None:
    cfg = _make_settings(tmp_path)

    # Process 1: run hits deterministic guard and suspends to SQLite
    rt1 = WorkbenchRuntime(cfg)
    await rt1.start()
    paused = await rt1.start_run(fixture_id="hitl-01", thread_id="run-restart-01")
    assert paused.status == "interrupted"
    assert paused.interrupt_payload is not None
    assert await rt1.ledger.list_work_orders() == []
    await rt1.close()

    # Process 2: fresh runtime reopens SQLite and resumes from checkpoint
    rt2 = WorkbenchRuntime(cfg)
    await rt2.start()
    try:
        fixed_ticket = paused.extracted_ticket.model_copy(update={"total_fee_cents": 20_000})  # type: ignore[union-attr]
        resumed = await rt2.resume_run(
            "run-restart-01",
            ResumeDecisionRequest(
                action="approve",
                edited_ticket=fixed_ticket,
                reviewer_note="核对原件涂改处实为200.00元",
            ),
        )
        assert resumed.status == "completed"
        assert resumed.work_order_id is not None
        assert resumed.eval_case_id is not None

        orders = await rt2.ledger.list_work_orders()
        assert len(orders) == 1
        assert orders[0].ticket.total_fee_cents == 20_000

        eval_cases = await rt2.ledger.list_eval_cases()
        assert len(eval_cases) == 1
        assert eval_cases[0].field_diffs[0].field == "total_fee_cents"
        assert eval_cases[0].field_diffs[0].raw_value == 28_000
        assert eval_cases[0].field_diffs[0].corrected_value == 20_000
    finally:
        await rt2.close()


async def test_side_effect_isolation_proves_gate_reexecutes_while_commit_runs_once(
    tmp_path: Path,
) -> None:
    rt = WorkbenchRuntime(_make_settings(tmp_path))
    await rt.start()
    try:
        paused = await rt.start_run(fixture_id="hitl-01", thread_id="run-isolation")
        assert rt.gate_entry_count == 1
        assert rt.commit_execution_count == 0

        fixed = paused.extracted_ticket.model_copy(update={"total_fee_cents": 20_000})  # type: ignore[union-attr]
        await rt.resume_run(
            "run-isolation",
            ResumeDecisionRequest(action="approve", edited_ticket=fixed),
        )
        # LangGraph re-enters human_review_gate from top on resume, so gate_entry_count == 2,
        # while idempotent_commit executes strictly once!
        assert rt.gate_entry_count == 2
        assert rt.commit_execution_count == 1
    finally:
        await rt.close()


async def test_invalid_human_override_keeps_run_paused_until_valid_edit(tmp_path: Path) -> None:
    rt = WorkbenchRuntime(_make_settings(tmp_path))
    await rt.start()
    try:
        paused = await rt.start_run(fixture_id="hitl-01", thread_id="run-bad-edit")
        # Reviewer approves without fixing 8000 + 12000 != 28000
        with pytest.raises(InvalidHumanOverrideError):
            await rt.resume_run(
                "run-bad-edit",
                ResumeDecisionRequest(action="approve", edited_ticket=paused.extracted_ticket),
            )
        assert await rt.ledger.list_work_orders() == []

        # Reviewer fixes total_fee_cents -> succeeds cleanly
        fixed = paused.extracted_ticket.model_copy(update={"total_fee_cents": 20_000})  # type: ignore[union-attr]
        resumed = await rt.resume_run(
            "run-bad-edit",
            ResumeDecisionRequest(action="approve", edited_ticket=fixed),
        )
        assert resumed.status == "completed"
        assert len(await rt.ledger.list_work_orders()) == 1
    finally:
        await rt.close()


async def test_human_can_waive_unsigned_high_value_or_reject_injection_trap(
    tmp_path: Path,
) -> None:
    rt = WorkbenchRuntime(_make_settings(tmp_path))
    await rt.start()
    try:
        # Waive HIGH_VALUE_UNSIGNED on hitl-03 after phone confirmation
        p_unsigned = await rt.start_run(fixture_id="hitl-03", thread_id="run-waive")
        assert p_unsigned.status == "interrupted"
        approved = await rt.resume_run(
            "run-waive",
            ResumeDecisionRequest(
                action="approve",
                edited_ticket=p_unsigned.extracted_ticket,
                reviewer_note="已与业主电话录音确认授权先施工",
            ),
        )
        assert approved.status == "completed"

        # Reject prompt-injection trap-01
        p_trap = await rt.start_run(fixture_id="trap-01", thread_id="run-trap")
        assert p_trap.status == "interrupted"
        rejected = await rt.resume_run(
            "run-trap",
            ResumeDecisionRequest(action="reject", reviewer_note="恶意注入假单据"),
        )
        assert rejected.status == "rejected"
        assert rejected.work_order_id is None
        assert len(await rt.ledger.list_work_orders()) == 1
    finally:
        await rt.close()
