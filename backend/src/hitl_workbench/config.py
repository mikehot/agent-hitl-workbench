"""Runtime configuration for Agent HITL Workbench."""

from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Environment-driven settings supporting replay sandbox and live model modes."""

    model_config = SettingsConfigDict(env_prefix="WORKBENCH_", extra="ignore")

    mode: Literal["replay", "live"] = "replay"
    sqlite_path: str = "data/workbench.db"
    llm_base_url: str = "http://127.0.0.1:1234/v1"
    llm_api_key: str = "local-dev"
    llm_model_id: str = "qwen/qwen3.8-27b"
    llm_reasoning_effort: str = "none"
    cors_origins: list[str] = ["*"]
