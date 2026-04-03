#!/bin/bash
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: run-openclaw-masterofdrums-validation.sh

Runs the end-to-end OpenClaw validation flow against the dedicated
openclaw-mac-agent SSH surface:

  1. git-sync to an exact branch and commit
  2. env-check
  3. validate-analyzer
  4. run-pipeline
  5. poll get-run-status until completion

Required environment:
  TARGET_BRANCH              branch OpenClaw wants tested
  EXPECTED_COMMIT            exact commit SHA OpenClaw wants tested
  SOURCE_URI                 file:// URI for the audio input

Optional environment:
  MAC_HOST                   default: openclaw-agent@192.168.1.156
  MAC_SSH_KEY                default: ~/.ssh/openclaw_mac_agent
  MAC_AGENT_REPO             default: masterofdrums-pipeline
  PIPELINE_PROFILE           default: debug
  RUN_VALIDATE_ANALYZER      default: 1
  POLL_INTERVAL_SECONDS      default: 5
  POLL_TIMEOUT_SECONDS       default: 900

Exit codes:
  0  validation succeeded
  1  git-sync failed
  2  env-check failed
  3  validate-analyzer failed
  4  run-pipeline start failed
  5  run-pipeline completed with failure
  6  polling timed out
  7  wrapper/runtime error
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

MAC_HOST="${MAC_HOST:-openclaw-agent@192.168.1.156}"
MAC_SSH_KEY="${MAC_SSH_KEY:-$HOME/.ssh/openclaw_mac_agent}"
MAC_AGENT_REPO="${MAC_AGENT_REPO:-masterofdrums-pipeline}"
PIPELINE_PROFILE="${PIPELINE_PROFILE:-debug}"
RUN_VALIDATE_ANALYZER="${RUN_VALIDATE_ANALYZER:-1}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-5}"
POLL_TIMEOUT_SECONDS="${POLL_TIMEOUT_SECONDS:-900}"
TARGET_BRANCH="${TARGET_BRANCH:-}"
EXPECTED_COMMIT="${EXPECTED_COMMIT:-}"
SOURCE_URI="${SOURCE_URI:-}"

[[ -f "$MAC_SSH_KEY" ]] || {
  printf 'missing SSH private key: %s\n' "$MAC_SSH_KEY" >&2
  exit 7
}

[[ -n "$TARGET_BRANCH" ]] || {
  printf 'missing required TARGET_BRANCH\n' >&2
  exit 7
}

[[ -n "$EXPECTED_COMMIT" ]] || {
  printf 'missing required EXPECTED_COMMIT\n' >&2
  exit 7
}

[[ -n "$SOURCE_URI" ]] || {
  printf 'missing required SOURCE_URI\n' >&2
  exit 7
}

json_field() {
  local json_payload="$1"
  local field_path="$2"
  OPENCLAW_WRAPPER_JSON="$json_payload" python3 - <<'PY' "$field_path"
import json
import os
import sys

value = json.loads(os.environ["OPENCLAW_WRAPPER_JSON"])
for part in sys.argv[1].split("."):
    value = value[part]

if isinstance(value, bool):
    print("true" if value else "false")
else:
    print(value)
PY
}

json_compact() {
  local json_payload="$1"
  OPENCLAW_WRAPPER_JSON="$json_payload" python3 - <<'PY'
import json
import os

print(json.dumps(json.loads(os.environ["OPENCLAW_WRAPPER_JSON"]), separators=(",", ":")))
PY
}

run_remote_json() {
  local verb="$1"
  shift
  local remote_cmd="openclaw-mac-agent $(printf '%q' "$verb") --repo $(printf '%q' "$MAC_AGENT_REPO") --json"
  local arg
  for arg in "$@"; do
    remote_cmd+=" $(printf '%q' "$arg")"
  done
  ssh -i "$MAC_SSH_KEY" "$MAC_HOST" "$remote_cmd"
}

run_remote_json_capture() {
  local verb="$1"
  shift
  local payload=""
  local status=0
  set +e
  payload="$(run_remote_json "$verb" "$@")"
  status=$?
  set -e
  printf '%s' "$payload"
  return "$status"
}

print_stage() {
  local stage="$1"
  local json_payload="$2"
  printf '%s: ok=%s\n' "$stage" "$(json_field "$json_payload" "ok")" >&2
}

SYNC_STATUS=0
SYNC_JSON="$(run_remote_json_capture git-sync --branch "$TARGET_BRANCH" --expected-commit "$EXPECTED_COMMIT")" || SYNC_STATUS=$?
[[ -n "$SYNC_JSON" ]] || {
  printf 'git-sync returned no JSON output\n' >&2
  exit 7
}
SYNC_JSON="$(json_compact "$SYNC_JSON")"
print_stage git-sync "$SYNC_JSON"
if [[ "$SYNC_STATUS" -ne 0 || "$(json_field "$SYNC_JSON" "ok")" != "true" ]]; then
  printf '%s\n' "$SYNC_JSON"
  exit 1
fi

ENV_STATUS=0
ENV_JSON="$(run_remote_json_capture env-check)" || ENV_STATUS=$?
[[ -n "$ENV_JSON" ]] || {
  printf 'env-check returned no JSON output\n' >&2
  exit 7
}
ENV_JSON="$(json_compact "$ENV_JSON")"
print_stage env-check "$ENV_JSON"
if [[ "$ENV_STATUS" -ne 0 || "$(json_field "$ENV_JSON" "ok")" != "true" ]]; then
  printf '%s\n' "$ENV_JSON"
  exit 2
fi

ANALYZER_JSON='null'
if [[ "$RUN_VALIDATE_ANALYZER" == "1" ]]; then
  ANALYZER_STATUS=0
  ANALYZER_JSON="$(run_remote_json_capture validate-analyzer --source-uri "$SOURCE_URI")" || ANALYZER_STATUS=$?
  [[ -n "$ANALYZER_JSON" ]] || {
    printf 'validate-analyzer returned no JSON output\n' >&2
    exit 7
  }
  ANALYZER_JSON="$(json_compact "$ANALYZER_JSON")"
  print_stage validate-analyzer "$ANALYZER_JSON"
  if [[ "$ANALYZER_STATUS" -ne 0 || "$(json_field "$ANALYZER_JSON" "ok")" != "true" ]]; then
    printf '%s\n' "$ANALYZER_JSON"
    exit 3
  fi
fi

RUN_STATUS=0
RUN_JSON="$(run_remote_json_capture run-pipeline --profile "$PIPELINE_PROFILE" --source-uri "$SOURCE_URI")" || RUN_STATUS=$?
[[ -n "$RUN_JSON" ]] || {
  printf 'run-pipeline returned no JSON output\n' >&2
  exit 7
}
RUN_JSON="$(json_compact "$RUN_JSON")"
print_stage run-pipeline "$RUN_JSON"
if [[ "$RUN_STATUS" -ne 0 || "$(json_field "$RUN_JSON" "ok")" != "true" ]]; then
  printf '%s\n' "$RUN_JSON"
  exit 4
fi

RUN_ID="$(json_field "$RUN_JSON" "data.run.run_id")"
START_TIME="$(date +%s)"
FINAL_STATUS_JSON=""

while true; do
  NOW="$(date +%s)"
  ELAPSED=$((NOW - START_TIME))
  if (( ELAPSED > POLL_TIMEOUT_SECONDS )); then
    printf 'polling timed out after %ss for run %s\n' "$POLL_TIMEOUT_SECONDS" "$RUN_ID" >&2
    exit 6
  fi

  STATUS_PAYLOAD="$(run_remote_json get-run-status --run-id "$RUN_ID")"
  STATUS_PAYLOAD="$(json_compact "$STATUS_PAYLOAD")"
  RUN_STATE="$(json_field "$STATUS_PAYLOAD" "data.run.status")"
  printf 'get-run-status: run_id=%s status=%s elapsed=%ss\n' "$RUN_ID" "$RUN_STATE" "$ELAPSED" >&2

  if [[ "$RUN_STATE" == "completed" || "$RUN_STATE" == "failed" ]]; then
    FINAL_STATUS_JSON="$STATUS_PAYLOAD"
    break
  fi

  sleep "$POLL_INTERVAL_SECONDS"
done

RESULT_JSON="$(
  OPENCLAW_SYNC_JSON="$SYNC_JSON" \
  OPENCLAW_ENV_JSON="$ENV_JSON" \
  OPENCLAW_ANALYZER_JSON="$ANALYZER_JSON" \
  OPENCLAW_RUN_JSON="$RUN_JSON" \
  OPENCLAW_FINAL_STATUS_JSON="$FINAL_STATUS_JSON" \
  python3 - <<'PY'
import json
import os

sync = json.loads(os.environ["OPENCLAW_SYNC_JSON"])
env = json.loads(os.environ["OPENCLAW_ENV_JSON"])
analyzer_raw = os.environ["OPENCLAW_ANALYZER_JSON"]
analyzer = None if analyzer_raw == "null" else json.loads(analyzer_raw)
run_start = json.loads(os.environ["OPENCLAW_RUN_JSON"])
run_final = json.loads(os.environ["OPENCLAW_FINAL_STATUS_JSON"])

run_info = run_final["data"]["run"]
artifacts = run_info.get("artifacts", [])
base_chart = next((item["uri"] for item in artifacts if item.get("type") == "base_chart"), None)
normalized = next((item["uri"] for item in artifacts if item.get("type") == "normalized_analysis"), None)
audio_analysis = next((item["uri"] for item in artifacts if item.get("type") == "audio_analysis"), None)

status = "validation-passed" if run_info["status"] == "completed" and run_info.get("exit_code") == 0 else "validation-failed"

payload = {
    "status": status,
    "repo": run_final["data"]["repo"],
    "sync": sync["data"]["git"],
    "env_check": env["data"],
    "validate_analyzer": None if analyzer is None else analyzer["data"],
    "run_started": run_start["data"]["run"],
    "run_final": run_info,
    "artifacts": {
        "base_chart": base_chart,
        "normalized_analysis": normalized,
        "audio_analysis": audio_analysis,
        "all": artifacts,
    },
}
print(json.dumps(payload, separators=(",", ":")))
PY
)"

printf '%s\n' "$RESULT_JSON"

if [[ "$(json_field "$RESULT_JSON" "status")" != "validation-passed" ]]; then
  exit 5
fi
