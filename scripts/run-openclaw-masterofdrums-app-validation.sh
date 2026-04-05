#!/bin/bash
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: run-openclaw-masterofdrums-app-validation.sh

Runs the OpenClaw app-validation flow against the dedicated
openclaw-mac-agent SSH surface:

  1. git-sync to an exact branch and commit
  2. env-check
  3. validate-masterofdrums-chart

Required environment:
  TARGET_BRANCH              branch OpenClaw wants tested
  EXPECTED_COMMIT            exact commit SHA OpenClaw wants tested
  CHART_ROOT                 named chart root from repos.json
  CHART_PATH                 chart path relative to CHART_ROOT

Required environment:
  MAC_AGENT_REPO             explicit repo id to validate via openclaw-mac-agent
                             valid options: masterofdrums, masterofdrums-pipeline

Optional environment:
  MAC_HOST                   default: openclaw-agent@192.168.1.156
  MAC_SSH_KEY                default: ~/.ssh/openclaw_mac_agent
  VALIDATION_MODE            default: import-timing
  AUDIO_ROOT                 named audio root from repos.json
  AUDIO_PATH                 audio path relative to AUDIO_ROOT
  EXPECTED_BPM               expected BPM
  EXPECTED_OFFSET_SECONDS    expected chart offset
  EXPECTED_TICKS_PER_BEAT    expected ticks per beat
  EXPECTED_TIME_SIGNATURE    expected time signature, e.g. 4/4
  EXPECTED_TIMING_SOURCE     expected timing source, e.g. generated

Exit codes:
  0  validation succeeded
  1  git-sync failed
  2  env-check failed
  3  validate-masterofdrums-chart failed
  7  wrapper/runtime error
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

VALID_MAC_AGENT_REPOS="masterofdrums, masterofdrums-pipeline"

MAC_HOST="${MAC_HOST:-openclaw-agent@192.168.1.156}"
MAC_SSH_KEY="${MAC_SSH_KEY:-$HOME/.ssh/openclaw_mac_agent}"
MAC_AGENT_REPO="${MAC_AGENT_REPO:-}"
TARGET_BRANCH="${TARGET_BRANCH:-}"
EXPECTED_COMMIT="${EXPECTED_COMMIT:-}"
CHART_ROOT="${CHART_ROOT:-}"
CHART_PATH="${CHART_PATH:-}"
VALIDATION_MODE="${VALIDATION_MODE:-import-timing}"
AUDIO_ROOT="${AUDIO_ROOT:-}"
AUDIO_PATH="${AUDIO_PATH:-}"
EXPECTED_BPM="${EXPECTED_BPM:-}"
EXPECTED_OFFSET_SECONDS="${EXPECTED_OFFSET_SECONDS:-}"
EXPECTED_TICKS_PER_BEAT="${EXPECTED_TICKS_PER_BEAT:-}"
EXPECTED_TIME_SIGNATURE="${EXPECTED_TIME_SIGNATURE:-}"
EXPECTED_TIMING_SOURCE="${EXPECTED_TIMING_SOURCE:-}"

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

[[ -n "$MAC_AGENT_REPO" ]] || {
  printf 'missing required MAC_AGENT_REPO\nvalid options: %s\n' "$VALID_MAC_AGENT_REPOS" >&2
  exit 7
}

case "$MAC_AGENT_REPO" in
  masterofdrums|masterofdrums-pipeline) ;;
  *)
    printf 'invalid MAC_AGENT_REPO: %s\nvalid options: %s\n' "$MAC_AGENT_REPO" "$VALID_MAC_AGENT_REPOS" >&2
    exit 7
    ;;
esac

[[ -n "$CHART_ROOT" ]] || {
  printf 'missing required CHART_ROOT\n' >&2
  exit 7
}

[[ -n "$CHART_PATH" ]] || {
  printf 'missing required CHART_PATH\n' >&2
  exit 7
}

if [[ -n "$AUDIO_ROOT" && -z "$AUDIO_PATH" ]]; then
  printf 'AUDIO_ROOT requires AUDIO_PATH\n' >&2
  exit 7
fi

if [[ -n "$AUDIO_PATH" && -z "$AUDIO_ROOT" ]]; then
  printf 'AUDIO_PATH requires AUDIO_ROOT\n' >&2
  exit 7
fi

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

VALIDATE_ARGS=(
  --branch "$TARGET_BRANCH"
  --expected-commit "$EXPECTED_COMMIT"
  --chart-root "$CHART_ROOT"
  --chart-path "$CHART_PATH"
  --validation-mode "$VALIDATION_MODE"
)

if [[ -n "$AUDIO_ROOT" ]]; then
  VALIDATE_ARGS+=(--audio-root "$AUDIO_ROOT" --audio-path "$AUDIO_PATH")
fi
if [[ -n "$EXPECTED_BPM" ]]; then
  VALIDATE_ARGS+=(--expected-bpm "$EXPECTED_BPM")
fi
if [[ -n "$EXPECTED_OFFSET_SECONDS" ]]; then
  VALIDATE_ARGS+=(--expected-offset-seconds "$EXPECTED_OFFSET_SECONDS")
fi
if [[ -n "$EXPECTED_TICKS_PER_BEAT" ]]; then
  VALIDATE_ARGS+=(--expected-ticks-per-beat "$EXPECTED_TICKS_PER_BEAT")
fi
if [[ -n "$EXPECTED_TIME_SIGNATURE" ]]; then
  VALIDATE_ARGS+=(--expected-time-signature "$EXPECTED_TIME_SIGNATURE")
fi
if [[ -n "$EXPECTED_TIMING_SOURCE" ]]; then
  VALIDATE_ARGS+=(--expected-timing-source "$EXPECTED_TIMING_SOURCE")
fi

VALIDATE_STATUS=0
VALIDATE_JSON="$(run_remote_json_capture validate-masterofdrums-chart "${VALIDATE_ARGS[@]}")" || VALIDATE_STATUS=$?
[[ -n "$VALIDATE_JSON" ]] || {
  printf 'validate-masterofdrums-chart returned no JSON output\n' >&2
  exit 7
}
VALIDATE_JSON="$(json_compact "$VALIDATE_JSON")"
print_stage validate-masterofdrums-chart "$VALIDATE_JSON"
if [[ "$VALIDATE_STATUS" -ne 0 || "$(json_field "$VALIDATE_JSON" "ok")" != "true" ]]; then
  printf '%s\n' "$VALIDATE_JSON"
  exit 3
fi

RESULT_JSON="$(
  OPENCLAW_SYNC_JSON="$SYNC_JSON" \
  OPENCLAW_ENV_JSON="$ENV_JSON" \
  OPENCLAW_VALIDATE_JSON="$VALIDATE_JSON" \
  python3 - <<'PY'
import json
import os

sync = json.loads(os.environ["OPENCLAW_SYNC_JSON"])
env = json.loads(os.environ["OPENCLAW_ENV_JSON"])
validate = json.loads(os.environ["OPENCLAW_VALIDATE_JSON"])

payload = {
    "status": "validation-passed" if validate["data"]["status"] == "pass" else "validation-failed",
    "repo": validate["data"]["repo"],
    "sync": sync["data"]["git"],
    "env_check": env["data"],
    "validation": validate["data"],
}
print(json.dumps(payload, separators=(",", ":")))
PY
)"

printf '%s\n' "$RESULT_JSON"

if [[ "$(json_field "$RESULT_JSON" "status")" != "validation-passed" ]]; then
  exit 3
fi
