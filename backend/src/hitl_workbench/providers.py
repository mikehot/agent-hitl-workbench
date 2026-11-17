"""Pluggable extraction providers: deterministic replay vs OpenAI-compatible VLM/LLM."""

from __future__ import annotations

import re
from typing import Protocol

import httpx

from hitl_workbench.config import Settings
from hitl_workbench.fixtures import SyntheticFixture
from hitl_workbench.schemas import ExtractedTicket

_FENCE_RE = re.compile(r"^```(?:json)?\s*|\s*```$", re.IGNORECASE)

_SYSTEM_PROMPT = (
    "You extract structured field-service ticket JSON from synthetic Chinese maintenance forms. "
    "All monetary amounts must be integer cents (e.g. 80.00 yuan = 8000). "
    "Never invent values for blank fields; transcribe notes verbatim."
)


class TicketExtractor(Protocol):
    async def extract(self, fixture: SyntheticFixture) -> ExtractedTicket: ...


class ReplayTicketExtractor:
    """Zero-network deterministic extractor backed by curated synthetic fixtures."""

    async def extract(self, fixture: SyntheticFixture) -> ExtractedTicket:
        return fixture.replay_extraction.model_copy(deep=True)


class OpenAICompatibleTicketExtractor:
    """Live extractor for LM Studio (Qwen/Gemma with reasoning_effort='none') or cloud endpoints."""

    def __init__(self, settings: Settings, client: httpx.AsyncClient | None = None) -> None:
        self._settings = settings
        self._client = client

    async def extract(self, fixture: SyntheticFixture) -> ExtractedTicket:
        schema = ExtractedTicket.model_json_schema()
        payload = {
            "model": self._settings.llm_model_id,
            "temperature": 0,
            "reasoning_effort": self._settings.llm_reasoning_effort,
            "response_format": {
                "type": "json_schema",
                "json_schema": {
                    "name": "extracted_ticket",
                    "strict": True,
                    "schema": schema,
                },
            },
            "messages": [
                {"role": "system", "content": _SYSTEM_PROMPT},
                {"role": "user", "content": fixture.document_text},
            ],
        }
        headers = {"Authorization": f"Bearer {self._settings.llm_api_key}"}
        url = f"{self._settings.llm_base_url.rstrip('/')}/chat/completions"

        if self._client is not None:
            resp = await self._client.post(url, json=payload, headers=headers, timeout=60.0)
        else:
            async with httpx.AsyncClient() as temp_client:
                resp = await temp_client.post(url, json=payload, headers=headers, timeout=60.0)
        resp.raise_for_status()
        raw_content: str = resp.json()["choices"][0]["message"]["content"]
        cleaned = _FENCE_RE.sub("", raw_content.strip())
        return ExtractedTicket.model_validate_json(cleaned)


def build_extractor(settings: Settings) -> TicketExtractor:
    if settings.mode == "live":
        return OpenAICompatibleTicketExtractor(settings)
    return ReplayTicketExtractor()
