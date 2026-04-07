#!/bin/bash
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: run-openclaw-masterofdrums-validation.sh

Runs the end-to-end OpenClaw validation flow against the dedicated
openclaw-mac-agent SSH surface:

  1. git-sync to an exact branch and commit
  2. env-check
  3. swift-build
  4. swift-test
  5. validate-analyzer
  6. run-pipeline
  7. poll get-run-status until completion

Required environment:
  TARGET_BRANCH              branch OpenClaw wants tested
  EXPECTED_COMMIT            exact commit SHA OpenClaw wants tested

Required environment:
  MAC_AGENT_REPO             explicit repo id to validate via openclaw-mac-agent
                             valid options: masterofdrums-pipeline, masterofdrums

Optional environment:
  MAC_HOST                   default: openclaw-agent@192.168.1.156
  MAC_SSH_KEY                default: ~/.ssh/openclaw_mac_agent
  PIPELINE_PROFILE           default: debug
  SOURCE_URI                 explicit file:// URI for the audio input on the Mac
  SOURCE_NAME                logical Mac-side sample source name from repos.json
  SAMPLE_SET                 logical Mac-side sample set name from repos.json
  RUN_VALIDATE_ANALYZER      default: 1
  POLL_INTERVAL_SECONDS      default: 5
  POLL_TIMEOUT_SECONDS       default: 900

Exit codes:
  0  validation succeeded
  1  git-sync failed
  2  env-check failed
  3  swift-build failed
  4  swift-test failed
  5  validate-analyzer failed
  6  run-pipeline start failed
  7  run-pipeline completed with failure / wrapper-runtime error
  8  polling timed out
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

VALID_MAC_AGENT_REPOS="masterofdrums-pipeline, masterofdrums"

MAC_HOST="${MAC_HOST:-openclaw-agent@192.168.1.156}"
MAC_SSH_KEY="${MAC_SSH_KEY:-$HOME/.ssh/openclaw_mac_agent}"
MAC_AGENT_REPO="${MAC_AGENT_REPO:-}"
PIPELINE_PROFILE="${PIPELINE_PROFILE:-debug}"
RUN_VALIDATE_ANALYZER="${RUN_VALIDATE_ANALYZER:-1}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-5}"
POLL_TIMEOUT_SECONDS="${POLL_TIMEOUT_SECONDS:-900}"
TARGET_BRANCH="${TARGET_BRANCH:-}"
EXPECTED_COMMIT="${EXPECTED_COMMIT:-}"
SOURCE_URI="${SOURCE_URI:-}"
SOURCE_NAME="${SOURCE_NAME:-}"
SAMPLE_SET="${SAMPLE_SET:-}"

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
  masterofdrums-pipeline|masterofdrums) ;;
  *)
    printf 'invalid MAC_AGENT_REPO: %s\nvalid options: %s\n' "$MAC_AGENT_REPO" "$VALID_MAC_AGENT_REPOS" >&2
    exit 7
    ;;
esac

SELECTOR_COUNT=0
[[ -n "$SOURCE_URI" ]] && SELECTOR_COUNT=$((SELECTOR_COUNT + 1))
[[ -n "$SOURCE_NAME" ]] && SELECTOR_COUNT=$((SELECTOR_COUNT + 1))
[[ -n "$SAMPLE_SET" ]] && SELECTOR_COUNT=$((SELECTOR_COUNT + 1))
if (( SELECTOR_COUNT > 1 )); then
  printf 'set only one of SOURCE_URI, SOURCE_NAME, or SAMPLE_SET\n' >&2
  exit 7
fi

printf 'wrapper-config: repo=%s host=%s profile=%s\n' "$MAC_AGENT_REPO" "$MAC_HOST" "$PIPELINE_PROFILE"
if [[ -n "$SOURCE_URI" ]]; then
  printf 'wrapper-config: source_uri=%s\n' "$SOURCE_URI"
elif [[ -n "$SOURCE_NAME" ]]; then
  printf 'wrapper-config: source_name=%s\n' "$SOURCE_NAME"
elif [[ -n "$SAMPLE_SET" ]]; then
  printf 'wrapper-config: sample_set=%s\n' "$SAMPLE_SET"
else
  printf 'wrapper-config: source_selector=profile-default\n'
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

resolve_sources_json() {
  if [[ -n "$SOURCE_URI" ]]; then
    run_remote_json resolve-sources --profile "$PIPELINE_PROFILE" --source-uri "$SOURCE_URI"
  elif [[ -n "$SOURCE_NAME" ]]; then
    run_remote_json resolve-sources --profile "$PIPELINE_PROFILE" --source-name "$SOURCE_NAME"
  elif [[ -n "$SAMPLE_SET" ]]; then
    run_remote_json resolve-sources --profile "$PIPELINE_PROFILE" --sample-set "$SAMPLE_SET"
  else
    run_remote_json resolve-sources --profile "$PIPELINE_PROFILE"
  fi
}

resolve_sources_args() {
  if [[ -n "$SOURCE_URI" ]]; then
    printf '%s\n' --profile "$PIPELINE_PROFILE" --source-uri "$SOURCE_URI"
  elif [[ -n "$SOURCE_NAME" ]]; then
    printf '%s\n' --profile "$PIPELINE_PROFILE" --source-name "$SOURCE_NAME"
  elif [[ -n "$SAMPLE_SET" ]]; then
    printf '%s\n' --profile "$PIPELINE_PROFILE" --sample-set "$SAMPLE_SET"
  else
    printf '%s\n' --profile "$PIPELINE_PROFILE"
  fi
}

iter_sources() {
  local json_payload="$1"
  OPENCLAW_WRAPPER_JSON="$json_payload" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["OPENCLAW_WRAPPER_JSON"])
for item in payload["data"]["sources"]:
    name = item.get("source_name") or ""
    uri = item["source_uri"]
    print(f"{name}\t{uri}")
PY
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

BUILD_STATUS=0
BUILD_JSON="$(run_remote_json_capture swift-build)" || BUILD_STATUS=$?
[[ -n "$BUILD_JSON" ]] || {
  printf 'swift-build returned no JSON output\n' >&2
  exit 7
}
BUILD_JSON="$(json_compact "$BUILD_JSON")"
print_stage swift-build "$BUILD_JSON"
if [[ "$BUILD_STATUS" -ne 0 || "$(json_field "$BUILD_JSON" "ok")" != "true" || "$(json_field "$BUILD_JSON" "data.status")" != "pass" ]]; then
  printf '%s\n' "$BUILD_JSON"
  exit 3
fi

TEST_STATUS=0
TEST_JSON="$(run_remote_json_capture swift-test)" || TEST_STATUS=$?
[[ -n "$TEST_JSON" ]] || {
  printf 'swift-test returned no JSON output\n' >&2
  exit 7
}
TEST_JSON="$(json_compact "$TEST_JSON")"
print_stage swift-test "$TEST_JSON"
if [[ "$TEST_STATUS" -ne 0 || "$(json_field "$TEST_JSON" "ok")" != "true" || "$(json_field "$TEST_JSON" "data.status")" != "pass" ]]; then
  printf '%s\n' "$TEST_JSON"
  exit 4
fi

mapfile -t RESOLVE_ARGS < <(resolve_sources_args)
RESOLVE_STATUS=0
RESOLVE_JSON="$(run_remote_json_capture resolve-sources "${RESOLVE_ARGS[@]}")" || RESOLVE_STATUS=$?
[[ -n "$RESOLVE_JSON" ]] || {
  printf 'resolve-sources returned no JSON output\n' >&2
  exit 7
}
RESOLVE_JSON="$(json_compact "$RESOLVE_JSON")"
print_stage resolve-sources "$RESOLVE_JSON"
if [[ "$RESOLVE_STATUS" -ne 0 || "$(json_field "$RESOLVE_JSON" "ok")" != "true" ]]; then
  printf '%s\n' "$RESOLVE_JSON"
  exit 5
fi

ANALYZER_RESULTS_FILE="$(mktemp)"
RUN_STARTED_FILE="$(mktemp)"
RUN_FINAL_FILE="$(mktemp)"
trap 'rm -f "$ANALYZER_RESULTS_FILE" "$RUN_STARTED_FILE" "$RUN_FINAL_FILE"' EXIT

SOURCE_COUNT=0
while IFS=$'\t' read -r RESOLVED_NAME RESOLVED_URI; do
  [[ -n "$RESOLVED_URI" ]] || continue
  SOURCE_COUNT=$((SOURCE_COUNT + 1))
  printf 'source[%s]: name=%s uri=%s\n' "$SOURCE_COUNT" "${RESOLVED_NAME:-<unnamed>}" "$RESOLVED_URI" >&2

  if [[ "$RUN_VALIDATE_ANALYZER" == "1" ]]; then
    ANALYZER_STATUS=0
    ANALYZER_JSON="$(run_remote_json_capture validate-analyzer --source-uri "$RESOLVED_URI")" || ANALYZER_STATUS=$?
    [[ -n "$ANALYZER_JSON" ]] || {
      printf 'validate-analyzer returned no JSON output\n' >&2
      exit 7
    }
    ANALYZER_JSON="$(json_compact "$ANALYZER_JSON")"
    print_stage validate-analyzer "$ANALYZER_JSON"
    if [[ "$ANALYZER_STATUS" -ne 0 || "$(json_field "$ANALYZER_JSON" "ok")" != "true" ]]; then
      printf '%s\n' "$ANALYZER_JSON"
      exit 5
    fi
    printf '%s\n' "$ANALYZER_JSON" >> "$ANALYZER_RESULTS_FILE"
  fi

  RUN_STATUS=0
  RUN_JSON="$(run_remote_json_capture run-pipeline --profile "$PIPELINE_PROFILE" --source-uri "$RESOLVED_URI")" || RUN_STATUS=$?
  [[ -n "$RUN_JSON" ]] || {
    printf 'run-pipeline returned no JSON output\n' >&2
    exit 7
  }
  RUN_JSON="$(json_compact "$RUN_JSON")"
  print_stage run-pipeline "$RUN_JSON"
  if [[ "$RUN_STATUS" -ne 0 || "$(json_field "$RUN_JSON" "ok")" != "true" ]]; then
    printf '%s\n' "$RUN_JSON"
    exit 6
  fi
  printf '%s\n' "$RUN_JSON" >> "$RUN_STARTED_FILE"

  RUN_ID="$(json_field "$RUN_JSON" "data.run.run_id")"
  START_TIME="$(date +%s)"
  FINAL_STATUS_JSON=""

  while true; do
    NOW="$(date +%s)"
    ELAPSED=$((NOW - START_TIME))
    if (( ELAPSED > POLL_TIMEOUT_SECONDS )); then
      printf 'polling timed out after %ss for run %s\n' "$POLL_TIMEOUT_SECONDS" "$RUN_ID" >&2
      exit 8
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

  printf '%s\n' "$FINAL_STATUS_JSON" >> "$RUN_FINAL_FILE"
done < <(iter_sources "$RESOLVE_JSON")

if (( SOURCE_COUNT == 0 )); then
  printf 'resolve-sources returned no sources\n' >&2
  exit 7
fi

RESULT_JSON="$(
  OPENCLAW_SYNC_JSON="$SYNC_JSON" \
  OPENCLAW_ENV_JSON="$ENV_JSON" \
  OPENCLAW_BUILD_JSON="$BUILD_JSON" \
  OPENCLAW_TEST_JSON="$TEST_JSON" \
  OPENCLAW_RESOLVE_JSON="$RESOLVE_JSON" \
  OPENCLAW_ANALYZER_RESULTS_FILE="$ANALYZER_RESULTS_FILE" \
  OPENCLAW_RUN_STARTED_FILE="$RUN_STARTED_FILE" \
  OPENCLAW_RUN_FINAL_FILE="$RUN_FINAL_FILE" \
  python3 - <<'PY'
import json
import os

sync = json.loads(os.environ["OPENCLAW_SYNC_JSON"])
env = json.loads(os.environ["OPENCLAW_ENV_JSON"])
build = json.loads(os.environ["OPENCLAW_BUILD_JSON"])
test = json.loads(os.environ["OPENCLAW_TEST_JSON"])
resolve = json.loads(os.environ["OPENCLAW_RESOLVE_JSON"])

def load_json_lines(path_env):
    path = os.environ[path_env]
    with open(path, "r", encoding="utf-8") as handle:
        return [json.loads(line) for line in handle if line.strip()]

analyzer_results = load_json_lines("OPENCLAW_ANALYZER_RESULTS_FILE")
run_started = load_json_lines("OPENCLAW_RUN_STARTED_FILE")
run_final = load_json_lines("OPENCLAW_RUN_FINAL_FILE")

all_artifacts = []
base_charts = []
normalized_artifacts = []
audio_analysis_artifacts = []
scenario_ok = True

for item in run_final:
    run_info = item["data"]["run"]
    if run_info["status"] != "completed" or run_info.get("exit_code") != 0:
        scenario_ok = False
    for artifact in run_info.get("artifacts", []):
        all_artifacts.append(artifact)
        if artifact.get("type") == "base_chart":
            base_charts.append(artifact["uri"])
        elif artifact.get("type") == "normalized_analysis":
            normalized_artifacts.append(artifact["uri"])
        elif artifact.get("type") == "audio_analysis":
            audio_analysis_artifacts.append(artifact["uri"])

build_ok = build["data"]["status"] == "pass"
test_ok = test["data"]["status"] == "pass"
analyzer_ok = all(item["data"]["validation"].get("imports_ok") for item in analyzer_results) if analyzer_results else True
overall_ok = build_ok and test_ok and analyzer_ok and scenario_ok
status = "validation-passed" if overall_ok else "validation-failed"

payload = {
    "status": status,
    "repo": resolve["data"]["repo"],
    "sync": sync["data"]["git"],
    "env_check": env["data"],
    "build": build["data"],
    "test": test["data"],
    "resolved_sources": resolve["data"]["sources"],
    "validate_analyzer": [item["data"] for item in analyzer_results],
    "runs_started": [item["data"]["run"] for item in run_started],
    "runs_final": [item["data"]["run"] for item in run_final],
    "artifacts": {
        "base_chart": base_charts[0] if len(base_charts) == 1 else base_charts,
        "normalized_analysis": normalized_artifacts[0] if len(normalized_artifacts) == 1 else normalized_artifacts,
        "audio_analysis": audio_analysis_artifacts[0] if len(audio_analysis_artifacts) == 1 else audio_analysis_artifacts,
        "all": all_artifacts,
    },
    "merge_readiness": {
        "go": overall_ok,
        "reason": "all required stages passed" if overall_ok else "one or more required stages failed",
    },
}
print(json.dumps(payload, separators=(",", ":")))
PY
)"

printf '%s\n' "$RESULT_JSON"

if [[ "$(json_field "$RESULT_JSON" "status")" != "validation-passed" ]]; then
  exit 7
fi
