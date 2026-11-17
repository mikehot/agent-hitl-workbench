"""Offline replay evaluator over human-curated Trace-to-Eval JSONL regression cases."""

from __future__ import annotations

from pydantic import BaseModel

from hitl_workbench.fixtures import get_fixture
from hitl_workbench.guards import compute_ticket_diffs, evaluate_guards, has_blocker
from hitl_workbench.providers import TicketExtractor
from hitl_workbench.schemas import EvalRegressionCase


class CaseEvalResult(BaseModel):
    case_id: str
    doc_id: str
    exact_match: bool
    guard_caught_discrepancy: bool
    silent_wrong_write: bool
    mismatched_fields: list[str]


class RegressionEvalReport(BaseModel):
    total_cases: int
    exact_matches: int
    guard_intercepted: int
    silent_wrong_writes: int
    results: list[CaseEvalResult]


def parse_eval_jsonl(jsonl_text: str) -> list[EvalRegressionCase]:
    return [
        EvalRegressionCase.model_validate_json(line)
        for line in jsonl_text.splitlines()
        if line.strip()
    ]


async def run_regression_eval(
    cases: list[EvalRegressionCase],
    extractor: TicketExtractor,
) -> RegressionEvalReport:
    """Replay exported human-reviewed cases against an extractor and count silent wrong writes."""
    results: list[CaseEvalResult] = []
    exact = 0
    intercepted = 0
    silent_wrong = 0

    for case in cases:
        fx = get_fixture(case.doc_id)
        pred = await extractor.extract(fx)
        # Compare substantive business fields (excluding model self-reported confidence)
        pred_cmp = pred.model_copy(update={"confidence": case.expected_truth.confidence})
        diffs = compute_ticket_diffs(pred_cmp, case.expected_truth)
        flags = evaluate_guards(pred)
        blocked = has_blocker(flags)

        is_exact = len(diffs) == 0
        is_silent_wrong = (not is_exact) and (not blocked)
        if is_exact:
            exact += 1
        elif blocked:
            intercepted += 1
        else:
            silent_wrong += 1

        results.append(
            CaseEvalResult(
                case_id=case.case_id,
                doc_id=case.doc_id,
                exact_match=is_exact,
                guard_caught_discrepancy=blocked and not is_exact,
                silent_wrong_write=is_silent_wrong,
                mismatched_fields=[d.field for d in diffs],
            )
        )

    return RegressionEvalReport(
        total_cases=len(cases),
        exact_matches=exact,
        guard_intercepted=intercepted,
        silent_wrong_writes=silent_wrong,
        results=results,
    )
