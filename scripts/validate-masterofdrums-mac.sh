#!/bin/bash
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: validate-masterofdrums-mac.sh [mac-host]

Runs the mac_worker validation flow for the masterofdrums-pipeline profile.
This wrapper is intended to be called from Linux/OpenClaw.

Environment overrides:
  MAC_HOST                    default: openclaw-agent@192.168.1.156
  MAC_SSH_KEY                 default: ~/.ssh/id_ed25519
  MAC_WORKER_PROFILE          default: masterofdrums-pipeline
  MAC_ARTIFACT_OUT            default: ./mac-validation-artifacts
  MAC_COPY_ARTIFACTS          default: 0
  MAC_STRICT_TESTS            default: 0

Exit codes:
  0  doctor/build passed and tests passed or transitional mode tolerated test failures
  1  doctor failed
  2  build failed
  3  test failed in strict mode
  4  wrapper/runtime error
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

MAC_HOST="${1:-${MAC_HOST:-openclaw-agent@192.168.1.156}}"
MAC_SSH_KEY="${MAC_SSH_KEY:-$HOME/.ssh/id_ed25519}"
MAC_WORKER_PROFILE="${MAC_WORKER_PROFILE:-masterofdrums-pipeline}"
MAC_ARTIFACT_OUT="${MAC_ARTIFACT_OUT:-./mac-validation-artifacts}"
MAC_COPY_ARTIFACTS="${MAC_COPY_ARTIFACTS:-0}"
MAC_STRICT_TESTS="${MAC_STRICT_TESTS:-0}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

[[ -f "$MAC_SSH_KEY" ]] || {
  printf 'missing SSH private key: %s\n' "$MAC_SSH_KEY" >&2
  exit 4
}

mkdir -p "$MAC_ARTIFACT_OUT"

case "$MAC_COPY_ARTIFACTS" in
  0|1) ;;
  *)
    printf 'MAC_COPY_ARTIFACTS must be 0 or 1\n' >&2
    exit 4
    ;;
esac

run_remote_json() {
  local command_name="$1"
  shift
  ssh -i "$MAC_SSH_KEY" "$MAC_HOST" "mac_worker $command_name --project-profile $MAC_WORKER_PROFILE --json $*"
}

run_remote_json_capture() {
  local command_name="$1"
  shift
  local json_payload=""
  local status=0

  set +e
  json_payload="$(run_remote_json "$command_name" "$@")"
  status=$?
  set -e

  printf '%s' "$json_payload"
  return "$status"
}

json_field() {
  local json_payload="$1"
  local field_path="$2"
  MAC_WRAPPER_JSON="$json_payload" python3 - <<'PY' "$field_path"
import json
import os
import sys

value = json.loads(os.environ["MAC_WRAPPER_JSON"])
for part in sys.argv[1].split("."):
    value = value[part]

if isinstance(value, bool):
    print("true" if value else "false")
else:
    print(value)
PY
}

copy_job_artifacts() {
  local job_id="$1"
  if [[ "$MAC_COPY_ARTIFACTS" != "1" ]]; then
    return 0
  fi
  "$SCRIPT_DIR/collect-mac-artifacts.sh" "$MAC_HOST" "$job_id" "$MAC_ARTIFACT_OUT" >/dev/null
}

print_result_summary() {
  local stage="$1"
  local json_payload="$2"
  local ok job_id
  ok="$(json_field "$json_payload" "ok")"
  job_id="$(json_field "$json_payload" "jobId")"
  printf '%s: ok=%s jobId=%s\n' "$stage" "$ok" "$job_id"
}

print_artifact_note() {
  if [[ "$MAC_COPY_ARTIFACTS" == "1" ]]; then
    printf 'artifacts: copy enabled -> %s\n' "$MAC_ARTIFACT_OUT"
  else
    printf 'artifacts: copy skipped (forced-command SSH key cannot rsync); use jobId/artifact paths from JSON or rerun with MAC_COPY_ARTIFACTS=1 only if you have a separate non-gated artifact path\n'
  fi
}

DOCTOR_STATUS_CODE=0
DOCTOR_JSON="$(run_remote_json_capture doctor)" || DOCTOR_STATUS_CODE=$?
[[ -n "$DOCTOR_JSON" ]] || {
  printf 'doctor returned no JSON output\n' >&2
  exit 4
}
print_result_summary doctor "$DOCTOR_JSON"
if [[ "$DOCTOR_STATUS_CODE" -ne 0 || "$(json_field "$DOCTOR_JSON" "ok")" != "true" ]]; then
  printf '%s\n' "$DOCTOR_JSON"
  exit 1
fi

BUILD_STATUS_CODE=0
BUILD_JSON="$(run_remote_json_capture build)" || BUILD_STATUS_CODE=$?
[[ -n "$BUILD_JSON" ]] || {
  printf 'build returned no JSON output\n' >&2
  exit 4
}
print_result_summary build "$BUILD_JSON"
BUILD_JOB_ID="$(json_field "$BUILD_JSON" "jobId")"
copy_job_artifacts "$BUILD_JOB_ID"
if [[ "$BUILD_STATUS_CODE" -ne 0 || "$(json_field "$BUILD_JSON" "ok")" != "true" ]]; then
  printf '%s\n' "$BUILD_JSON"
  exit 2
fi

TEST_STATUS_CODE=0
TEST_JSON="$(run_remote_json_capture test)" || TEST_STATUS_CODE=$?
[[ -n "$TEST_JSON" ]] || {
  printf 'test returned no JSON output\n' >&2
  exit 4
}
print_result_summary test "$TEST_JSON"
TEST_JOB_ID="$(json_field "$TEST_JSON" "jobId")"
copy_job_artifacts "$TEST_JOB_ID"

DOCTOR_STATUS="$(json_field "$DOCTOR_JSON" "ok")"
BUILD_STATUS="$(json_field "$BUILD_JSON" "ok")"
TEST_STATUS="$(json_field "$TEST_JSON" "ok")"

SUMMARY_JSON="$(MAC_WRAPPER_DOCTOR="$DOCTOR_JSON" MAC_WRAPPER_BUILD="$BUILD_JSON" MAC_WRAPPER_TEST="$TEST_JSON" python3 - <<'PY'
import json
import os

doctor = json.loads(os.environ["MAC_WRAPPER_DOCTOR"])
build = json.loads(os.environ["MAC_WRAPPER_BUILD"])
test = json.loads(os.environ["MAC_WRAPPER_TEST"])

if doctor["ok"] and build["ok"] and test["ok"]:
    status = "mac-validation-passed"
elif doctor["ok"] and build["ok"] and not test["ok"]:
    status = "mac-build-passed-tests-failed"
elif doctor["ok"] and not build["ok"]:
    status = "mac-build-failed"
else:
    status = "mac-worker-unavailable"

payload = {
    "status": status,
    "profile": "masterofdrums-pipeline",
    "doctor": doctor,
    "build": build,
    "test": test,
}
print(json.dumps(payload, separators=(",", ":")))
PY
)"

printf '%s\n' "$SUMMARY_JSON"
print_artifact_note

if [[ "$TEST_STATUS_CODE" -ne 0 && "$TEST_STATUS" == "true" ]]; then
  printf 'warning: test exited nonzero but reported ok=true\n' >&2
fi

if [[ "$TEST_STATUS" != "true" && "$MAC_STRICT_TESTS" == "1" ]]; then
  exit 3
fi

exit 0
