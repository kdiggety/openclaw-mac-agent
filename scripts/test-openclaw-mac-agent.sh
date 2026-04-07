#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
AGENT_BIN="${REPO_ROOT}/tools/openclaw-mac-agent/bin/openclaw-mac-agent"
SSH_WRAPPER="${REPO_ROOT}/tools/openclaw-mac-agent/bin/openclaw-mac-agent-ssh-wrapper"

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/openclaw-mac-agent-test.XXXXXX")"
trap 'rm -rf "${TEST_ROOT}"' EXIT

FAKE_REPO="${TEST_ROOT}/masterofdrums-pipeline"
FAKE_APP_REPO="${TEST_ROOT}/masterofdrums"
FAKE_APP_REMOTE="${TEST_ROOT}/masterofdrums-origin.git"
FAKE_CONFIG="${TEST_ROOT}/repos.json"
FAKE_AGENT_HOME="${TEST_ROOT}/agent-home"

mkdir -p "${FAKE_REPO}/logs" "${FAKE_REPO}/output/latest" "${FAKE_REPO}/tmp" "${FAKE_REPO}/runs" "${FAKE_REPO}/scripts"
mkdir -p "${FAKE_APP_REPO}/fixtures" "${FAKE_APP_REPO}/tmp" "${FAKE_APP_REPO}/runs" "${FAKE_APP_REPO}/scripts"
printf 'line1\nline2\nline3\n' > "${FAKE_REPO}/logs/pipeline.log"
printf '{"meta":{"name":"demo"},"events":[1,2,3],"tempo_map":[120]}\n' > "${FAKE_REPO}/output/latest/base-chart.json"
printf 'hello world\n' > "${FAKE_REPO}/README.txt"
printf 'fake' > "${FAKE_REPO}/tmp/input.wav"
cat > "${FAKE_APP_REPO}/fixtures/chart.json" <<'EOF'
{"title":"Fixture Song","bpm":120.0,"timingContractVersion":1,"timing":{"bpm":120.0,"offsetSeconds":0.0,"ticksPerBeat":480,"timeSignature":{"numerator":4,"denominator":4},"source":"generated"},"timelineDuration":8.0,"notes":[{"lane":0,"time":0.0},{"lane":1,"time":1.0}],"sections":[{"name":"Intro","startTime":0.0,"endTime":4.0,"colorName":"blue"}]}
EOF
printf 'audio' > "${FAKE_APP_REPO}/fixtures/song.mp3"

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

cat > "${FAKE_APP_REPO}/scripts/build_app.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
echo "build ok"
EOF

cat > "${FAKE_APP_REPO}/scripts/run_package_tests.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
echo "test ok"
EOF

cat > "${FAKE_APP_REPO}/scripts/validate_ui_state.py" <<'EOF'
#!/usr/bin/env python3
import argparse
import json

parser = argparse.ArgumentParser()
parser.add_argument("--chart", required=True)
parser.add_argument("--mode", required=True)
parser.add_argument("--expected-timing-source", default="")
args = parser.parse_args()

payload = {
    "status": "pass",
    "authorityChecks": {
        "generatedTimingAuthoritative": True,
        "audioDetectionDiagnosticOnly": True,
        "manualOverrideExplicit": True if args.mode in {"manual-override", "full"} else None,
        "timeSignatureRespected": True,
    },
    "uiObservations": [
        "Timing source displayed as Chart Timing v0.1.0 · Generated",
        "Audio BPM shown as diagnostic only",
    ],
    "artifacts": {
        "screenshots": [],
        "logs": [],
        "xcresult": None,
    },
    "warnings": [],
    "errors": [],
}
print(json.dumps(payload))
EOF

chmod +x "${FAKE_APP_REPO}/scripts/build_app.sh" "${FAKE_APP_REPO}/scripts/run_package_tests.sh" "${FAKE_APP_REPO}/scripts/validate_ui_state.py"

cd "${FAKE_REPO}"
git init >/dev/null
git config user.email "test@example.com"
git config user.name "Test User"
git add .
git commit -m "Initial fake repo" >/dev/null

cd "${FAKE_APP_REPO}"
git init >/dev/null
git config user.email "test@example.com"
git config user.name "Test User"
git add .
git commit -m "Initial fake app repo" >/dev/null
git init --bare "${FAKE_APP_REMOTE}" >/dev/null
git remote add origin "${FAKE_APP_REMOTE}"
APP_BRANCH="$(git branch --show-current)"
git push -u origin "${APP_BRANCH}" >/dev/null
cat >> "${FAKE_APP_REPO}/.git/info/exclude" <<'EOF'
tmp/
runs/
EOF

cat > "${FAKE_CONFIG}" <<EOF
{
  "repos": {
    "masterofdrums-pipeline": {
      "path": "${FAKE_REPO}",
      "sample_sources": {
        "fixture-input": "file://${FAKE_REPO}/tmp/input.wav"
      },
      "validation": {
        "build_recipe": {
          "argv": [
            "/usr/bin/env",
            "python3",
            "-c",
            "print('pipeline build ok')"
          ],
          "timeout_seconds": 30
        },
        "test_recipe": {
          "argv": [
            "/usr/bin/env",
            "python3",
            "-c",
            "print('pipeline test ok')"
          ],
          "timeout_seconds": 30
        }
      },
      "sample_sets": {
        "smoke": [
          "fixture-input"
        ]
      },
      "pipeline_profiles": {
        "debug": {
          "default_sample_set": "smoke",
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
    },
    "masterofdrums": {
      "path": "${FAKE_APP_REPO}",
      "roots": {
        "fixtures": "{repo}/fixtures",
        "tmp": "{repo}/tmp",
        "runs": "{repo}/runs"
      },
      "app_validation": {
        "build_recipe": {
          "argv": [
            "{repo}/scripts/build_app.sh"
          ],
          "timeout_seconds": 30
        },
        "test_recipe": {
          "argv": [
            "{repo}/scripts/run_package_tests.sh"
          ],
          "timeout_seconds": 30
        },
        "build_recipes": [
          {
            "argv": [
              "{repo}/scripts/build_app.sh"
            ],
            "timeout_seconds": 30
          },
          {
            "argv": [
              "{repo}/scripts/run_package_tests.sh"
            ],
            "timeout_seconds": 30
          }
        ],
        "import_recipe": {
          "argv": [
            "/usr/bin/python3",
            "{agent_repo}/scripts/validate-masterofdrums-chart-headless.py",
            "--chart",
            "{chart_resolved_path}",
            "--mode",
            "{validation_mode}",
            "--audio",
            "{audio_resolved_path}",
            "--expected-bpm",
            "{expected_bpm}",
            "--expected-offset-seconds",
            "{expected_offset_seconds}",
            "--expected-ticks-per-beat",
            "{expected_ticks_per_beat}",
            "--expected-time-signature",
            "{expected_time_signature}",
            "--expected-timing-source",
            "{expected_timing_source}"
          ],
          "timeout_seconds": 30
        },
        "integration_recipe": {
          "argv": [
            "/usr/bin/python3",
            "{repo}/scripts/validate_ui_state.py",
            "--chart",
            "{chart_resolved_path}",
            "--mode",
            "{validation_mode}",
            "--expected-timing-source",
            "{expected_timing_source}"
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
    if isinstance(value, list):
        value = value[int(part)]
    else:
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

printf 'Phase 6b: resolve-sources sample set\n'
RESOLVE_JSON="$(run_json resolve-sources --repo masterofdrums-pipeline --profile debug --sample-set smoke --json)"
[[ "$(json_field "$RESOLVE_JSON" "ok")" == "True" || "$(json_field "$RESOLVE_JSON" "ok")" == "true" ]]
[[ "$(json_field "$RESOLVE_JSON" "data.sources.0.source_name")" == "fixture-input" ]]

printf 'Phase 7: validate-analyzer\n'
INPUT_FILE="${FAKE_REPO}/tmp/input.wav"
VAL_JSON="$(run_json validate-analyzer --repo masterofdrums-pipeline --source-uri "file://${INPUT_FILE}" --json)"
[[ "$(json_field "$VAL_JSON" "ok")" == "True" || "$(json_field "$VAL_JSON" "ok")" == "true" ]]

printf 'Phase 7a: swift-build / swift-test\n'
PIPE_BUILD_JSON="$(run_json swift-build --repo masterofdrums-pipeline --json)"
[[ "$(json_field "$PIPE_BUILD_JSON" "ok")" == "True" || "$(json_field "$PIPE_BUILD_JSON" "ok")" == "true" ]]
[[ "$(json_field "$PIPE_BUILD_JSON" "data.status")" == "pass" ]]
PIPE_TEST_JSON="$(run_json swift-test --repo masterofdrums-pipeline --json)"
[[ "$(json_field "$PIPE_TEST_JSON" "ok")" == "True" || "$(json_field "$PIPE_TEST_JSON" "ok")" == "true" ]]
[[ "$(json_field "$PIPE_TEST_JSON" "data.status")" == "pass" ]]

printf 'Phase 7b: validate-analyzer default sample\n'
VAL_DEFAULT_JSON="$(run_json validate-analyzer --repo masterofdrums-pipeline --profile debug --json)"
[[ "$(json_field "$VAL_DEFAULT_JSON" "ok")" == "True" || "$(json_field "$VAL_DEFAULT_JSON" "ok")" == "true" ]]
[[ "$(json_field "$VAL_DEFAULT_JSON" "data.source.source_name")" == "fixture-input" ]]

printf 'Phase 8: run-pipeline + get-run-status\n'
RUN_JSON="$(run_json run-pipeline --repo masterofdrums-pipeline --source-uri "file://${INPUT_FILE}" --profile debug --json)"
RUN_ID="$(json_field "$RUN_JSON" "data.run.run_id")"
sleep 1
RUN_STATUS_JSON="$(run_json get-run-status --repo masterofdrums-pipeline --run-id "${RUN_ID}" --json)"
[[ "$(json_field "$RUN_STATUS_JSON" "data.run.status")" == "completed" ]]

printf 'Phase 8b: run-pipeline default sample\n'
RUN_DEFAULT_JSON="$(run_json run-pipeline --repo masterofdrums-pipeline --profile debug --json)"
RUN_DEFAULT_ID="$(json_field "$RUN_DEFAULT_JSON" "data.run.run_id")"
sleep 1
RUN_DEFAULT_STATUS_JSON="$(run_json get-run-status --repo masterofdrums-pipeline --run-id "${RUN_DEFAULT_ID}" --json)"
[[ "$(json_field "$RUN_DEFAULT_STATUS_JSON" "data.run.status")" == "completed" ]]

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

printf 'Phase 12: validate-masterofdrums-chart\n'
APP_HEAD="$(git -C "${FAKE_APP_REPO}" rev-parse HEAD)"
APP_BUILD_JSON="$(run_json swift-build --repo masterofdrums --json)"
[[ "$(json_field "$APP_BUILD_JSON" "ok")" == "True" || "$(json_field "$APP_BUILD_JSON" "ok")" == "true" ]]
[[ "$(json_field "$APP_BUILD_JSON" "data.status")" == "pass" ]]
APP_TEST_JSON="$(run_json swift-test --repo masterofdrums --json)"
[[ "$(json_field "$APP_TEST_JSON" "ok")" == "True" || "$(json_field "$APP_TEST_JSON" "ok")" == "true" ]]
[[ "$(json_field "$APP_TEST_JSON" "data.status")" == "pass" ]]
APP_VALIDATE_JSON="$(run_json validate-masterofdrums-chart --repo masterofdrums --branch "${APP_BRANCH}" --expected-commit "${APP_HEAD}" --chart-root fixtures --chart-path chart.json --audio-root fixtures --audio-path song.mp3 --validation-mode import-timing --expected-bpm 120 --expected-offset-seconds 0 --expected-ticks-per-beat 480 --expected-time-signature 4/4 --expected-timing-source generated --json)"
[[ "$(json_field "$APP_VALIDATE_JSON" "ok")" == "True" || "$(json_field "$APP_VALIDATE_JSON" "ok")" == "true" ]]
[[ "$(json_field "$APP_VALIDATE_JSON" "data.status")" == "pass" ]]
[[ "$(json_field "$APP_VALIDATE_JSON" "data.import.timing.source")" == "generated" ]]

printf 'Phase 12b: validate-masterofdrums-chart full integration\n'
APP_VALIDATE_FULL_JSON="$(run_json validate-masterofdrums-chart --repo masterofdrums --branch "${APP_BRANCH}" --expected-commit "${APP_HEAD}" --chart-root fixtures --chart-path chart.json --audio-root fixtures --audio-path song.mp3 --validation-mode full --expected-bpm 120 --expected-offset-seconds 0 --expected-ticks-per-beat 480 --expected-time-signature 4/4 --expected-timing-source generated --json)"
[[ "$(json_field "$APP_VALIDATE_FULL_JSON" "ok")" == "True" || "$(json_field "$APP_VALIDATE_FULL_JSON" "ok")" == "true" ]]
[[ "$(json_field "$APP_VALIDATE_FULL_JSON" "data.integration.status")" == "pass" ]]
[[ "$(json_field "$APP_VALIDATE_FULL_JSON" "data.authorityChecks.manualOverrideExplicit")" == "True" || "$(json_field "$APP_VALIDATE_FULL_JSON" "data.authorityChecks.manualOverrideExplicit")" == "true" ]]

printf 'Phase 13: fail closed when build/test config missing\n'
MISSING_CONFIG="${TEST_ROOT}/repos-missing-validation.json"
python3 - <<'PY' "${FAKE_CONFIG}" "${MISSING_CONFIG}"
import json, sys
src, dst = sys.argv[1], sys.argv[2]
payload = json.load(open(src, 'r', encoding='utf-8'))
payload['repos']['masterofdrums-pipeline'].pop('validation', None)
payload['repos']['masterofdrums']['app_validation'].pop('build_recipe', None)
payload['repos']['masterofdrums']['app_validation'].pop('test_recipe', None)
json.dump(payload, open(dst, 'w', encoding='utf-8'))
PY
MISSING_BUILD_JSON="$(OPENCLAW_MAC_AGENT_CONFIG="${MISSING_CONFIG}" OPENCLAW_MAC_AGENT_HOME="${FAKE_AGENT_HOME}" "${AGENT_BIN}" swift-build --repo masterofdrums-pipeline --json || true)"
[[ "$(json_field "$MISSING_BUILD_JSON" "ok")" == "False" || "$(json_field "$MISSING_BUILD_JSON" "ok")" == "false" ]]
[[ "$(json_field "$MISSING_BUILD_JSON" "error.code")" == "BUILD_NOT_CONFIGURED" ]]
MISSING_TEST_JSON="$(OPENCLAW_MAC_AGENT_CONFIG="${MISSING_CONFIG}" OPENCLAW_MAC_AGENT_HOME="${FAKE_AGENT_HOME}" "${AGENT_BIN}" swift-test --repo masterofdrums --json || true)"
[[ "$(json_field "$MISSING_TEST_JSON" "ok")" == "False" || "$(json_field "$MISSING_TEST_JSON" "ok")" == "false" ]]
[[ "$(json_field "$MISSING_TEST_JSON" "error.code")" == "TEST_NOT_CONFIGURED" ]]

printf '\nAll openclaw-mac-agent smoke phases passed.\n'
