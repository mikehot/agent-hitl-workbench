"""Uvicorn entrypoint (`uv run uvicorn hitl_workbench.main:app --port 8095`)."""

from hitl_workbench.api import create_app

app = create_app()
