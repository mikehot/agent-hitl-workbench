"""Phase 0 bootstrap test verifying LangGraph interrupt/resume + AsyncSqliteSaver."""

from pathlib import Path
from typing import TypedDict

from langgraph.checkpoint.sqlite.aio import AsyncSqliteSaver
from langgraph.graph import END, START, StateGraph
from langgraph.types import Command, interrupt

from hitl_workbench.config import Settings


class _MiniState(TypedDict, total=False):
    raw_amount: int
    approved_amount: int
    committed: bool


async def _review_gate(state: _MiniState) -> _MiniState:
    decision = interrupt({"proposed_amount": state["raw_amount"]})
    return {"approved_amount": int(decision["amount"])}


async def _commit_node(state: _MiniState) -> _MiniState:
    return {"committed": state["approved_amount"] > 0}


def test_default_settings_is_replay_mode() -> None:
    cfg = Settings()
    assert cfg.mode == "replay"
    assert cfg.llm_reasoning_effort == "none"


async def test_langgraph_sqlite_interrupt_and_resume_across_reopen(tmp_path: Path) -> None:
    db_file = tmp_path / "checkpoint.db"
    builder = StateGraph(_MiniState)
    builder.add_node("review_gate", _review_gate)
    builder.add_node("commit_node", _commit_node)
    builder.add_edge(START, "review_gate")
    builder.add_edge("review_gate", "commit_node")
    builder.add_edge("commit_node", END)

    thread_cfg = {"configurable": {"thread_id": "thread-p0-verify"}}

    # Run 1: graph hits interrupt() and persists checkpoint to SQLite
    async with AsyncSqliteSaver.from_conn_string(str(db_file)) as saver:
        graph = builder.compile(checkpointer=saver)
        paused = await graph.ainvoke({"raw_amount": 120}, thread_cfg)
        assert "__interrupt__" in paused
        assert paused["__interrupt__"][0].value == {"proposed_amount": 120}

    # Run 2: simulate process restart by opening a fresh SQLite connection and resuming
    async with AsyncSqliteSaver.from_conn_string(str(db_file)) as saver_reopened:
        graph_reopened = builder.compile(checkpointer=saver_reopened)
        resumed = await graph_reopened.ainvoke(
            Command(resume={"amount": 150}),
            thread_cfg,
        )
        assert resumed["approved_amount"] == 150
        assert resumed["committed"] is True
