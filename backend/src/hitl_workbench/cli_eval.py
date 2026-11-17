"""CLI entrypoint to run offline Trace-to-Eval regression scoring on exported JSONL."""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from pathlib import Path

from hitl_workbench.config import Settings
from hitl_workbench.eval_runner import parse_eval_jsonl, run_regression_eval
from hitl_workbench.providers import build_extractor


async def _async_main(jsonl_path: Path, mode: str) -> int:
    text = jsonl_path.read_text(encoding="utf-8")
    cases = parse_eval_jsonl(text)
    cfg = Settings(mode="live" if mode == "live" else "replay")
    extractor = build_extractor(cfg)
    report = await run_regression_eval(cases, extractor)
    print(json.dumps(report.model_dump(), ensure_ascii=False, indent=2))
    return 1 if report.silent_wrong_writes > 0 else 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Replay exported regression_cases.jsonl and check zero silent wrong writes."
    )
    parser.add_argument("--jsonl", required=True, type=Path, help="Path to exported JSONL file.")
    parser.add_argument(
        "--mode",
        choices=("replay", "live"),
        default="replay",
        help="Extractor mode to evaluate (default: replay).",
    )
    args = parser.parse_args(argv)
    return asyncio.run(_async_main(args.jsonl, args.mode))


if __name__ == "__main__":
    sys.exit(main())
