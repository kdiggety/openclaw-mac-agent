#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
AGENT_BIN="${REPO_ROOT}/tools/openclaw-mac-agent/bin/openclaw-mac-agent"
SSH_WRAPPER="${REPO_ROOT}/tools/openclaw-mac-agent/bin/openclaw-mac-agent-ssh-wrapper"

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/openclaw-mac-agent-test.XXXXXX")"
trap 'rm -rf "${TEST_ROOT}"' EXIT

FAKE_REPO="${TEST_ROOT}/masterofdrums-pipeline"
FAKE_CONFIG="${TEST_ROOT}/repos.json"
FAKE_AGENT_HOME="${TEST_ROOT}/agent-home"

mkdir -p "${FAKE_REPO}/logs" "${FAKE_REPO}/output/latest" "${FAKE_REPO}/tmp" "${FAKE_REPO}/runs" "${FAKE_REPO}/scripts"
printf 'line1\nline2\nline3\n' > "${FAKE_REPO}/logs/pipeline.log"
printf '{"meta":{"name":"demo"},"events":[1,2,3],"tempo_map":[120]}\n' > "${FAKE_REPO}/output/latest/base-chart.json"
printf 'hello world\n' > "${FAKE_REPO}/README.txt"

cat > "${FAKE_REPO}/scripts/validate_analyzer.py" <<'EOF'
#!/usr/bin/env python3
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--input", required=True)
parser.add_argument("--output", required=True)
args = parser.parse_args()

Path(args.output).write_text(json.dumps({"validated": True, "input": args.input}))
print("validation ok")
EOF

cat > "${FAKE_REPO}/scripts/run_pipeline.py" <<'EOF'
#!/usr/bin/env python3
import argparse
import json
import os
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--source-uri", required=True)
args = parser.parse_args()

run_dir = Path(os.environ["OPENCLAW_RUN_DIR"])
(run_dir / "artifacts").mkdir(parents=True, exist_ok=True)
(run_dir / "artifacts" / "result.json").write_text(json.dumps({"ok": True, "source": args.source_uri}))
print("pipeline complete")
EOF

chmod +x "${FAKE_REPO}/scripts/validate_analyzer.py" "${FAKE_REPO}/scripts/run_pipeline.py"

cd "${FAKE_REPO}"
git init >/dev/null
git config user.email "test@example.com"
git config user.name "Test User"
git add .
git commit -m "Initial fake repo" >/dev/null

cat > "${FAKE_CONFIG}" <<EOF
{
  "repos": {
    "masterofdrums-pipeline": {
      "path": "${FAKE_REPO}",
      "pipeline_profiles": {
        "debug": {
          "argv": [
            "/usr/bin/python3",
            "{repo}/scripts/run_pipeline.py",
            "--source-uri",
            "{source_uri}"
          ],
          "timeout_seconds": 30
        }
      },
      "recipes": {
        "validate-analyzer": {
          "argv": [
            "/usr/bin/python3",
            "{repo}/scripts/validate_analyzer.py",
            "--input",
            "{source_path}",
            "--output",
            "{root_tmp}/validated.json"
          ],
          "timeout_seconds": 30
        }
      }
    }
  }
}
EOF

json_field() {
  local payload="$1"
  local path="$2"
  TEST_JSON="$payload" python3 - <<'PY' "$path"
import json
import os
import sys

value = json.loads(os.environ["TEST_JSON"])
for part in sys.argv[1].split("."):
    value = value[part]
print(value)
PY
}

run_json() {
  OPENCLAW_MAC_AGENT_CONFIG="${FAKE_CONFIG}" OPENCLAW_MAC_AGENT_HOME="${FAKE_AGENT_HOME}" "${AGENT_BIN}" "$@"
}

run_json_allow_fail() {
  set +e
  local output
  output="$(OPENCLAW_MAC_AGENT_CONFIG="${FAKE_CONFIG}" OPENCLAW_MAC_AGENT_HOME="${FAKE_AGENT_HOME}" "${AGENT_BIN}" "$@")"
  local status=$?
  set -e
  printf '%s' "${output}"
  return ${status}
}

printf 'Phase 1: env-check\n'
ENV_JSON="$(run_json env-check --repo masterofdrums-pipeline --json)"
[[ "$(json_field "$ENV_JSON" "ok")" == "True" || "$(json_field "$ENV_JSON" "ok")" == "true" ]]

printf 'Phase 2: repo-status\n'
STATUS_JSON="$(run_json repo-status --repo masterofdrums-pipeline --json)"
[[ "$(json_field "$STATUS_JSON" "ok")" == "True" || "$(json_field "$STATUS_JSON" "ok")" == "true" ]]

printf 'Phase 3: read-file\n'
READ_JSON="$(run_json read-file --repo masterofdrums-pipeline --root logs --path pipeline.log --json)"
[[ "$(json_field "$READ_JSON" "data.file.relative_path")" == "pipeline.log" ]]

printf 'Phase 4: tail-file\n'
TAIL_JSON="$(run_json tail-file --repo masterofdrums-pipeline --root logs --path pipeline.log --lines 2 --json)"
[[ "$(json_field "$TAIL_JSON" "ok")" == "True" || "$(json_field "$TAIL_JSON" "ok")" == "true" ]]

printf 'Phase 5: list-artifacts\n'
ART_JSON="$(run_json list-artifacts --repo masterofdrums-pipeline --root artifacts --json)"
[[ "$(json_field "$ART_JSON" "ok")" == "True" || "$(json_field "$ART_JSON" "ok")" == "true" ]]

printf 'Phase 6: summarize-artifact\n'
SUM_JSON="$(run_json summarize-artifact --repo masterofdrums-pipeline --root artifacts --path latest/base-chart.json --json)"
[[ "$(json_field "$SUM_JSON" "data.artifact.kind")" == "json" ]]

printf 'Phase 7: validate-analyzer\n'
INPUT_FILE="${FAKE_REPO}/tmp/input.wav"
printf 'fake' > "${INPUT_FILE}"
VAL_JSON="$(run_json validate-analyzer --repo masterofdrums-pipeline --source-uri "file://${INPUT_FILE}" --json)"
[[ "$(json_field "$VAL_JSON" "ok")" == "True" || "$(json_field "$VAL_JSON" "ok")" == "true" ]]

printf 'Phase 8: run-pipeline + get-run-status\n'
RUN_JSON="$(run_json run-pipeline --repo masterofdrums-pipeline --source-uri "file://${INPUT_FILE}" --profile debug --json)"
RUN_ID="$(json_field "$RUN_JSON" "data.run.run_id")"
sleep 1
RUN_STATUS_JSON="$(run_json get-run-status --repo masterofdrums-pipeline --run-id "${RUN_ID}" --json)"
[[ "$(json_field "$RUN_STATUS_JSON" "data.run.status")" == "completed" ]]

printf 'Phase 9: git-fetch\n'
FETCH_JSON="$(run_json git-fetch --repo masterofdrums-pipeline --json)"
[[ "$(json_field "$FETCH_JSON" "ok")" == "True" || "$(json_field "$FETCH_JSON" "ok")" == "true" ]]

printf 'Phase 10: path restrictions\n'
ABS_JSON="$(run_json_allow_fail read-file --repo masterofdrums-pipeline --path /etc/passwd --json || true)"
[[ "$(json_field "$ABS_JSON" "ok")" == "False" || "$(json_field "$ABS_JSON" "ok")" == "false" ]]
[[ "$(json_field "$ABS_JSON" "error.code")" == "ABSOLUTE_PATH_REJECTED" ]]

TRAVERSAL_JSON="$(run_json_allow_fail read-file --repo masterofdrums-pipeline --path ../secret.txt --json || true)"
[[ "$(json_field "$TRAVERSAL_JSON" "ok")" == "False" || "$(json_field "$TRAVERSAL_JSON" "ok")" == "false" ]]
[[ "$(json_field "$TRAVERSAL_JSON" "error.code")" == "PARENT_PATH_REJECTED" ]]

printf 'Phase 11: SSH wrapper dispatch\n'
WRAPPER_JSON="$(OPENCLAW_MAC_AGENT_CONFIG="${FAKE_CONFIG}" OPENCLAW_MAC_AGENT_HOME="${FAKE_AGENT_HOME}" SSH_ORIGINAL_COMMAND='openclaw-mac-agent env-check --repo masterofdrums-pipeline --json' "${SSH_WRAPPER}")"
[[ "$(json_field "$WRAPPER_JSON" "ok")" == "True" || "$(json_field "$WRAPPER_JSON" "ok")" == "true" ]]

printf '\nAll openclaw-mac-agent smoke phases passed.\n'
