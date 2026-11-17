FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim

WORKDIR /app/backend

COPY backend/pyproject.toml backend/uv.lock ./
COPY backend/src ./src

RUN uv sync --frozen --no-dev

ENV WORKBENCH_MODE=replay
ENV WORKBENCH_SQLITE_PATH=/data/workbench.db
EXPOSE 8095

CMD ["uv", "run", "--no-dev", "uvicorn", "hitl_workbench.main:app", "--host", "0.0.0.0", "--port", "8095"]
