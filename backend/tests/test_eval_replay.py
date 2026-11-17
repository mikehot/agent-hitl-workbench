"""Tests for the Trace-to-Eval JSONL parser and offline regression replay scorer."""

from pathlib import Path

from hitl_workbench.cli_eval import main as cli_eval_main
from hitl_workbench.config import Settings
from hitl_workbench.eval_runner import parse_eval_jsonl, run_regression_eval
from hitl_workbench.fixtures import SyntheticFixture, get_fixture
from hitl_workbench.graph import WorkbenchRuntime
from hitl_workbench.providers import ReplayTicketExtractor
from hitl_workbench.schemas import ExtractedTicket, ResumeDecisionRequest


class _UpgradedExtractor:
    """Simulates an upgraded model/prompt that reads hitl-01 total_fee_cents=20000 accurately."""

    async def extract(self, fixture: SyntheticFixture) -> ExtractedTicket:
        if fixture.fixture_id == "hitl-01":
            return fixture.replay_extraction.model_copy(update={"total_fee_cents": 20_000})
        return fixture.replay_extraction.model_copy(deep=True)


class _SilentBugExtractor:
    """Simulates a model that misreads customer_name while keeping math consistent (silent bug)."""

    async def extract(self, fixture: SyntheticFixture) -> ExtractedTicket:
        return fixture.replay_extraction.model_copy(
            update={"customer_name": "误读姓名", "total_fee_cents": 20_000}
        )


async def _produce_hitl_01_eval_jsonl(tmp_path: Path) -> str:
    rt = WorkbenchRuntime(Settings(mode="replay", sqlite_path=str(tmp_path / "eval.db")))
    await rt.start()
    try:
        paused = await rt.start_run(fixture_id="hitl-01", thread_id="eval-seed-1")
        fixed = paused.extracted_ticket.model_copy(update={"total_fee_cents": 20_000})  # type: ignore[union-attr]
        await rt.resume_run(
            "eval-seed-1",
            ResumeDecisionRequest(action="approve", edited_ticket=fixed),
        )
        return await rt.ledger.export_eval_jsonl()
    finally:
        await rt.close()


async def test_parse_empty_jsonl_returns_empty_list() -> None:
    report = await run_regression_eval(parse_eval_jsonl("  \n "), ReplayTicketExtractor())
    assert report.total_cases == 0
    assert report.silent_wrong_writes == 0


async def test_baseline_replay_extractor_is_intercepted_zero_silent_wrong(tmp_path: Path) -> None:
    jsonl = await _produce_hitl_01_eval_jsonl(tmp_path)
    cases = parse_eval_jsonl(jsonl)
    assert len(cases) == 1

    report = await run_regression_eval(cases, ReplayTicketExtractor())
    assert report.total_cases == 1
    assert report.exact_matches == 0
    assert report.guard_intercepted == 1
    assert report.silent_wrong_writes == 0
    assert report.results[0].mismatched_fields == ["total_fee_cents"]


async def test_upgraded_extractor_achieves_exact_match_on_exported_case(tmp_path: Path) -> None:
    jsonl = await _produce_hitl_01_eval_jsonl(tmp_path)
    cases = parse_eval_jsonl(jsonl)

    report = await run_regression_eval(cases, _UpgradedExtractor())
    assert report.exact_matches == 1
    assert report.guard_intercepted == 0
    assert report.silent_wrong_writes == 0


async def test_silent_bug_extractor_flagged_as_silent_wrong_write(tmp_path: Path) -> None:
    jsonl = await _produce_hitl_01_eval_jsonl(tmp_path)
    cases = parse_eval_jsonl(jsonl)

    report = await run_regression_eval(cases, _SilentBugExtractor())
    assert report.exact_matches == 0
    assert report.guard_intercepted == 0
    assert report.silent_wrong_writes == 1
    assert "customer_name" in report.results[0].mismatched_fields


def test_all_eight_fixtures_have_non_empty_svg_and_valid_schema() -> None:
    for fid in (
        "clean-01",
        "clean-02",
        "clean-03",
        "hitl-01",
        "hitl-02",
        "hitl-03",
        "trap-01",
        "trap-02",
    ):
        summary = get_fixture(fid).to_summary()
        assert "<svg" in summary.document_svg
        assert summary.fixture_id == fid


async def test_cli_eval_entrypoint_passes_with_exit_code_zero(tmp_path: Path) -> None:
    jsonl = await _produce_hitl_01_eval_jsonl(tmp_path)
    out_file = tmp_path / "exported.jsonl"
    out_file.write_text(jsonl, encoding="utf-8")
    # Run synchronous CLI helper inside worker thread so asyncio.run() has a clean loop
    import asyncio

    rc = await asyncio.to_thread(cli_eval_main, ["--jsonl", str(out_file), "--mode", "replay"])
    assert rc == 0
