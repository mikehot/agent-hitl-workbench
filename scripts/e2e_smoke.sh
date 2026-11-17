#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${SMOKE_PORT:-18097}"
BASE_URL="http://127.0.0.1:${PORT}"
TMP_DIR="$(mktemp -d -t hitl_e2e_XXXXXX)"
DB_PATH="${TMP_DIR}/workbench_e2e.db"
JSONL_PATH="${TMP_DIR}/regression_cases.jsonl"
SERVER_PID=""

cleanup() {
  if [[ -n "${SERVER_PID}" ]] && kill -0 "${SERVER_PID}" 2>/dev/null; then
    kill "${SERVER_PID}" 2>/dev/null || true
    wait "${SERVER_PID}" 2>/dev/null || true
  fi
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

start_server() {
  (
    cd "${ROOT_DIR}/backend"
    WORKBENCH_MODE=replay WORKBENCH_SQLITE_PATH="${DB_PATH}" \
      uv run uvicorn hitl_workbench.main:app --host 127.0.0.1 --port "${PORT}" --log-level warning
  ) &
  SERVER_PID=$!
  for _ in {1..30}; do
    if curl -sf "${BASE_URL}/healthz" >/dev/null; then
      return 0
    fi
    sleep 0.2
  done
  echo "ERROR: uvicorn failed to become ready on ${BASE_URL}" >&2
  return 1
}

echo "==> [1/6] Starting uvicorn process #1 (SQLite: ${DB_PATH})"
start_server
HZ="$(curl -sf "${BASE_URL}/healthz")"
echo "    healthz: ${HZ}"

echo "==> [2/6] Verifying clean auto-commit (clean-01) + cross-run idempotency (trap-02)"
SNAP_CLEAN="$(curl -sf -X POST "${BASE_URL}/api/v1/runs" -H 'Content-Type: application/json' -d '{"fixture_id":"clean-01","thread_id":"e2e-clean-1"}')"
SNAP_DUP="$(curl -sf -X POST "${BASE_URL}/api/v1/runs" -H 'Content-Type: application/json' -d '{"fixture_id":"trap-02","thread_id":"e2e-dup-2"}')"
python3 - "${SNAP_CLEAN}" "${SNAP_DUP}" <<'PY'
import json, sys
c = json.loads(sys.argv[1])
d = json.loads(sys.argv[2])
assert c["status"] == "completed" and c["idempotent_reused"] is False, c
assert d["status"] == "completed" and d["idempotent_reused"] is True, d
assert c["work_order_id"] == d["work_order_id"], (c["work_order_id"], d["work_order_id"])
print(f"    PASS: reused work_order_id={c['work_order_id']} with 0 duplicate inserts")
PY

echo "==> [3/6] Triggering LangGraph interrupt() on arithmetic mismatch (hitl-01)"
SNAP_HITL="$(curl -sf -X POST "${BASE_URL}/api/v1/runs" -H 'Content-Type: application/json' -d '{"fixture_id":"hitl-01","thread_id":"e2e-hitl-restart"}')"
python3 - "${SNAP_HITL}" <<'PY'
import json, sys
s = json.loads(sys.argv[1])
assert s["status"] == "interrupted", s
codes = [f["code"] for f in s["guard_flags"]]
assert "ARITHMETIC_MISMATCH" in codes, codes
print(f"    PASS: thread suspended at interrupt() with flags={codes}")
PY

echo "==> [4/6] Killing OS process #1 (PID ${SERVER_PID}) and restarting fresh process #2"
kill "${SERVER_PID}"
wait "${SERVER_PID}" 2>/dev/null || true
SERVER_PID=""
start_server

HTTP_BAD="$(curl -s -o /dev/null -w '%{http_code}' -X POST "${BASE_URL}/api/v1/runs/e2e-hitl-restart/resume" \
  -H 'Content-Type: application/json' \
  -d "$(python3 -c 'import json,sys; s=json.loads(sys.argv[1]); print(json.dumps({"action":"approve","edited_ticket":s["extracted_ticket"]}))' "${SNAP_HITL}")")"
if [[ "${HTTP_BAD}" != "422" ]]; then
  echo "ERROR: expected HTTP 422 on unfixed arithmetic override, got ${HTTP_BAD}" >&2
  exit 1
fi
echo "    PASS: invalid override rejected with HTTP 422 without corrupting SQLite checkpoint"

FIXED_BODY="$(python3 -c 'import json,sys; t=json.loads(sys.argv[1])["extracted_ticket"]; t["total_fee_cents"]=20000; print(json.dumps({"action":"approve","edited_ticket":t,"reviewer_note":"E2E OS-restart verified"}))' "${SNAP_HITL}")"
SNAP_RESUMED="$(curl -sf -X POST "${BASE_URL}/api/v1/runs/e2e-hitl-restart/resume" -H 'Content-Type: application/json' -d "${FIXED_BODY}")"
python3 - "${SNAP_RESUMED}" <<'PY'
import json, sys
r = json.loads(sys.argv[1])
assert r["status"] == "completed", r
assert r["work_order_id"] is not None and r["eval_case_id"] is not None, r
print(f"    PASS: resumed across OS restart -> wo={r['work_order_id']} eval={r['eval_case_id']}")
PY

echo "==> [5/6] Rejecting prompt-injection adversarial trap (trap-01)"
curl -sf -X POST "${BASE_URL}/api/v1/runs" -H 'Content-Type: application/json' -d '{"fixture_id":"trap-01","thread_id":"e2e-trap-1"}' >/dev/null
SNAP_REJ="$(curl -sf -X POST "${BASE_URL}/api/v1/runs/e2e-trap-1/resume" -H 'Content-Type: application/json' -d '{"action":"reject","reviewer_note":"Prompt injection blocked"}')"
python3 - "${SNAP_REJ}" "$(curl -sf "${BASE_URL}/api/v1/work-orders")" <<'PY'
import json, sys
rej = json.loads(sys.argv[1])
orders = json.loads(sys.argv[2])
assert rej["status"] == "rejected" and rej["work_order_id"] is None, rej
assert len(orders) == 2, f"Expected exactly 2 committed work orders, got {len(orders)}"
print(f"    PASS: injection trap rejected; ledger contains {len(orders)} verified work orders")
PY

echo "==> [6/6] Exporting regression_cases.jsonl and running CLI offline eval gate"
curl -sf "${BASE_URL}/api/v1/eval-cases/export.jsonl" > "${JSONL_PATH}"
EVAL_OUT="$(cd "${ROOT_DIR}/backend" && uv run python -m hitl_workbench.cli_eval --jsonl "${JSONL_PATH}" --mode replay)"
python3 - "${EVAL_OUT}" <<'PY'
import json, sys
rep = json.loads(sys.argv[1])
assert rep["total_cases"] == 1 and rep["silent_wrong_writes"] == 0 and rep["guard_intercepted"] == 1, rep
print("    PASS: CLI regression gate verified silent_wrong_writes == 0")
PY

echo "✅ E2E SMOKE PASSED ALL 6 GATES"
