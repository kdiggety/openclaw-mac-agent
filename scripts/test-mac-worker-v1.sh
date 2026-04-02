#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORKER_BIN="${REPO_ROOT}/tools/mac-worker/bin/mac_worker"
SSH_GATE_BIN="${REPO_ROOT}/tools/mac-worker/bin/mac_worker_ssh_gate"

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mac-worker-v1-test.XXXXXX")"
FAKE_BIN="${TEST_ROOT}/fake-bin"
FAKE_HOME="${TEST_ROOT}/home"
FAKE_WORKER_HOME="${FAKE_HOME}/mac-worker"
FAKE_PROJECT_ROOT="${TEST_ROOT}/sample-project"
FAKE_REMOTE_REPO="${FAKE_HOME}/src/openclaw-mac-agent"
FAKE_PROFILE_NAME="self-test-profile"
FAKE_PROFILE_PATH="${REPO_ROOT}/tools/mac-worker/config/projects/${FAKE_PROFILE_NAME}.json"

mkdir -p "${FAKE_BIN}" "${FAKE_HOME}" "${FAKE_PROJECT_ROOT}/FakeApp.xcworkspace" "${FAKE_PROJECT_ROOT}/FakeApp.app/Contents/MacOS"
touch "${FAKE_PROJECT_ROOT}/FakeApp.xcodeproj"

cleanup() {
  rm -f "${FAKE_PROFILE_PATH}"
  rm -rf "${TEST_ROOT}"
}
trap cleanup EXIT

cat >"${FAKE_PROFILE_PATH}" <<EOF
{
  "projectRoot": "${FAKE_PROJECT_ROOT}",
  "workspacePath": "FakeApp.xcworkspace",
  "defaultScheme": "FakeApp",
  "allowedSchemes": ["FakeApp"],
  "defaultDestination": "platform=macOS",
  "allowedDestinations": [
    "platform=macOS",
    "platform=iOS Simulator,id=SIM-UDID-1234"
  ],
  "defaultSimulator": "iPhone 16",
  "allowedSimulators": ["iPhone 16"],
  "bundleId": "com.example.FakeApp"
}
EOF

cat >"${FAKE_BIN}/xcodebuild" <<'EOF'
#!/bin/bash
set -euo pipefail
if [[ "${1:-}" == "-version" ]]; then
  printf 'Xcode 16.0\nBuild version 16A242d\n'
  exit 0
fi
printf 'xcodebuild %s\n' "$*" >>"${MAC_WORKER_TEST_LOG}"
if [[ "${1:-}" == "-workspace" || "${1:-}" == "-project" ]]; then
  target_flag="$1"
  target_path="$2"
  shift 2
fi
result_bundle=""
derived_data=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -resultBundlePath) result_bundle="$2"; shift 2 ;;
    -derivedDataPath) derived_data="$2"; shift 2 ;;
    *) shift ;;
  esac
done
if [[ -n "$result_bundle" ]]; then
  mkdir -p "$result_bundle"
  printf 'fake xcresult\n' >"${result_bundle}/Info.plist"
fi
if [[ -n "$derived_data" ]]; then
  mkdir -p "${derived_data}/Build"
fi
printf 'fake xcodebuild succeeded\n'
EOF

cat >"${FAKE_BIN}/xcrun" <<'EOF'
#!/bin/bash
set -euo pipefail
printf 'xcrun %s\n' "$*" >>"${MAC_WORKER_TEST_LOG}"
if [[ "${1:-}" == "simctl" && "${2:-}" == "list" && "${3:-}" == "devices" && "${4:-}" == "available" && "${5:-}" == "--json" ]]; then
  cat <<JSON
{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[{"state":"Shutdown","isAvailable":true,"name":"iPhone 16","udid":"SIM-UDID-1234"}]}}
JSON
  exit 0
fi
if [[ "${1:-}" == "simctl" && "${2:-}" == "boot" ]]; then
  exit 0
fi
if [[ "${1:-}" == "simctl" && "${2:-}" == "bootstatus" ]]; then
  exit 0
fi
printf 'unexpected xcrun invocation: %s\n' "$*" >&2
exit 1
EOF

cat >"${FAKE_BIN}/sw_vers" <<'EOF'
#!/bin/bash
set -euo pipefail
if [[ "${1:-}" == "-productVersion" ]]; then
  printf '14.5\n'
  exit 0
fi
exit 1
EOF

cat >"${FAKE_BIN}/xcode-select" <<'EOF'
#!/bin/bash
set -euo pipefail
if [[ "${1:-}" == "-p" ]]; then
  printf '/Applications/Xcode.app/Contents/Developer\n'
  exit 0
fi
exit 1
EOF

cat >"${FAKE_BIN}/open" <<'EOF'
#!/bin/bash
set -euo pipefail
printf 'open %s\n' "$*" >>"${MAC_WORKER_TEST_LOG}"
exit 0
EOF

cat >"${FAKE_BIN}/screencapture" <<'EOF'
#!/bin/bash
set -euo pipefail
out="${@: -1}"
mkdir -p "$(dirname "$out")"
printf 'fake screenshot\n' >"$out"
printf 'screencapture %s\n' "$*" >>"${MAC_WORKER_TEST_LOG}"
EOF

cat >"${FAKE_BIN}/log" <<'EOF'
#!/bin/bash
set -euo pipefail
printf 'log %s\n' "$*" >>"${MAC_WORKER_TEST_LOG}"
printf 'fake unified log\n'
EOF

cat >"${FAKE_BIN}/ssh" <<EOF
#!/bin/bash
set -euo pipefail
printf 'ssh %s\n' "\$*" >>"\${MAC_WORKER_TEST_LOG}"
host="\$1"
shift
if [[ "\${1:-}" == "test" && "\${2:-}" == "-d" ]]; then
  path="\${3:-}"
  path="\${path/#\~\//${FAKE_HOME}/}"
  test -d "\$path"
  exit \$?
fi
SSH_ORIGINAL_COMMAND="\$*" "${SSH_GATE_BIN}"
EOF

cat >"${FAKE_BIN}/rsync" <<EOF
#!/bin/bash
set -euo pipefail
printf 'rsync %s\n' "\$*" >>"\${MAC_WORKER_TEST_LOG}"
args=()
for arg in "\$@"; do
  case "\$arg" in
    -*) ;;
    *) args+=("\$arg") ;;
  esac
done
src="\${args[\${#args[@]}-2]}"
dest="\${args[\${#args[@]}-1]}"
translate() {
  local value="\$1"
  if [[ "\$value" == *:* ]]; then
    value="\${value#*:}"
  fi
  value="\${value/#\~\//${FAKE_HOME}/}"
  printf '%s\n' "\$value"
}
src_path="\$(translate "\$src")"
dest_path="\$(translate "\$dest")"
mkdir -p "\$(dirname "\$dest_path")"
rm -rf "\$dest_path"
cp -R "\$src_path" "\$dest_path"
EOF

chmod +x "${FAKE_BIN}"/*

export HOME="${FAKE_HOME}"
export PATH="${FAKE_BIN}:/usr/bin:/bin:/usr/sbin:/sbin"
export MAC_WORKER_HOME="${FAKE_WORKER_HOME}"
export MAC_WORKER_SSH_GATE_LOG="${FAKE_WORKER_HOME}/ssh-gate.log"
export MAC_WORKER_TEST_LOG="${TEST_ROOT}/tool-invocations.log"

assert_json_field_equals() {
  local json_payload="$1"
  local field_path="$2"
  local expected="$3"
  MAC_WORKER_ASSERT_JSON="$json_payload" python3 - <<'PY' "$field_path" "$expected"
import json
import os
import sys

payload = json.loads(os.environ["MAC_WORKER_ASSERT_JSON"])
path = sys.argv[1].split(".")
value = payload
for part in path:
    value = value[part]
expected = sys.argv[2]
if str(value) != expected:
    raise SystemExit(f"expected {sys.argv[1]}={expected!r}, got {value!r}")
PY
}

json_get_field() {
  local json_payload="$1"
  local field_path="$2"
  MAC_WORKER_ASSERT_JSON="$json_payload" python3 - <<'PY' "$field_path"
import json
import os
import sys

payload = json.loads(os.environ["MAC_WORKER_ASSERT_JSON"])
value = payload
for part in sys.argv[1].split("."):
    value = value[part]
print(value)
PY
}

assert_path_exists() {
  [[ -e "$1" ]] || {
    printf 'expected path to exist: %s\n' "$1" >&2
    exit 1
  }
}

assert_contains() {
  local file="$1"
  local needle="$2"
  grep -F "$needle" "$file" >/dev/null 2>&1 || {
    printf 'expected %s to contain %s\n' "$file" "$needle" >&2
    exit 1
  }
}

run_and_capture() {
  local output
  output="$("$@")"
  printf '%s' "$output"
}

printf 'Phase 1: doctor\n'
DOCTOR_JSON="$(run_and_capture "${WORKER_BIN}" doctor --mode hardened --project-profile "${FAKE_PROFILE_NAME}" --json)"
assert_json_field_equals "$DOCTOR_JSON" "ok" "True"
assert_json_field_equals "$DOCTOR_JSON" "command" "doctor"
assert_json_field_equals "$DOCTOR_JSON" "data.projectProfile" "${FAKE_PROFILE_NAME}"

printf 'Phase 2: build\n'
BUILD_JSON="$(run_and_capture "${WORKER_BIN}" build --mode hardened --project-profile "${FAKE_PROFILE_NAME}" --json)"
BUILD_JOB_ID="$(json_get_field "$BUILD_JSON" "jobId")"
assert_json_field_equals "$BUILD_JSON" "ok" "True"
assert_json_field_equals "$BUILD_JSON" "data.scheme" "FakeApp"
assert_path_exists "${FAKE_WORKER_HOME}/work/logs/${BUILD_JOB_ID}/build.log"
assert_path_exists "${FAKE_WORKER_HOME}/work/jobs/${BUILD_JOB_ID}/DerivedData/Build"

printf 'Phase 3: test\n'
TEST_JSON="$(run_and_capture "${WORKER_BIN}" test --mode hardened --project-profile "${FAKE_PROFILE_NAME}" --json)"
TEST_JOB_ID="$(json_get_field "$TEST_JSON" "jobId")"
assert_json_field_equals "$TEST_JSON" "ok" "True"
assert_path_exists "${FAKE_WORKER_HOME}/work/artifacts/${TEST_JOB_ID}/TestResults.xcresult/Info.plist"

printf 'Phase 4: ui-test\n'
UITEST_JSON="$(run_and_capture "${WORKER_BIN}" ui-test --mode hardened --project-profile "${FAKE_PROFILE_NAME}" --json)"
UITEST_JOB_ID="$(json_get_field "$UITEST_JSON" "jobId")"
assert_json_field_equals "$UITEST_JSON" "ok" "True"
assert_json_field_equals "$UITEST_JSON" "data.udid" "SIM-UDID-1234"
assert_path_exists "${FAKE_WORKER_HOME}/work/artifacts/${UITEST_JOB_ID}/UITestResults.xcresult/Info.plist"

printf 'Phase 5: launch\n'
LAUNCH_JSON="$(run_and_capture "${WORKER_BIN}" launch --mode hardened --project-profile "${FAKE_PROFILE_NAME}" --json)"
assert_json_field_equals "$LAUNCH_JSON" "ok" "True"
assert_json_field_equals "$LAUNCH_JSON" "data.bundleId" "com.example.FakeApp"

printf 'Phase 6: screenshot\n'
SCREENSHOT_JSON="$(run_and_capture "${WORKER_BIN}" screenshot --mode hardened --project-profile "${FAKE_PROFILE_NAME}" --json)"
SCREENSHOT_PATH="$(json_get_field "$SCREENSHOT_JSON" "data.output")"
assert_path_exists "$SCREENSHOT_PATH"

printf 'Phase 7: collect-logs\n'
LOG_JSON="$(run_and_capture "${WORKER_BIN}" collect-logs --mode hardened --project-profile "${FAKE_PROFILE_NAME}" --last 5m --json)"
LOG_PATH="$(json_get_field "$LOG_JSON" "data.output")"
assert_path_exists "$LOG_PATH"

printf 'Phase 8: hardened rejections\n'
if "${WORKER_BIN}" build --mode hardened --project-profile "${FAKE_PROFILE_NAME}" --scheme NotAllowed --json >/dev/null 2>&1; then
  printf 'expected hardened scheme rejection\n' >&2
  exit 1
fi
if "${WORKER_BIN}" launch --mode hardened --project-profile "${FAKE_PROFILE_NAME}" --bundle-id com.apple.TextEdit --json >/dev/null 2>&1; then
  printf 'expected hardened bundle-id rejection\n' >&2
  exit 1
fi
if "${WORKER_BIN}" screenshot --mode hardened --project-profile "${FAKE_PROFILE_NAME}" --out /tmp/outside.png --json >/dev/null 2>&1; then
  printf 'expected hardened output-path rejection\n' >&2
  exit 1
fi

printf 'Phase 9: SSH gate\n'
SSH_DOCTOR_JSON="$(SSH_ORIGINAL_COMMAND="mac_worker doctor --project-profile ${FAKE_PROFILE_NAME} --json" "${SSH_GATE_BIN}")"
assert_json_field_equals "$SSH_DOCTOR_JSON" "ok" "True"
if SSH_ORIGINAL_COMMAND="mac_worker screenshot --project-profile ${FAKE_PROFILE_NAME} --out /tmp/evil.png --json" "${SSH_GATE_BIN}" >/dev/null 2>&1; then
  printf 'expected SSH gate flag rejection\n' >&2
  exit 1
fi

printf 'Phase 10: artifact collection helper\n'
mkdir -p "${FAKE_REMOTE_REPO}"
"${REPO_ROOT}/scripts/sync-mac-worker.sh" fake-mac "~/src/openclaw-mac-agent"
assert_path_exists "${FAKE_REMOTE_REPO}/tools/mac-worker/bin/mac_worker"

REMOTE_BUILD_JSON="$("${REPO_ROOT}/scripts/run-remote-build.sh" fake-mac "${FAKE_PROFILE_NAME}" build)"
assert_json_field_equals "$REMOTE_BUILD_JSON" "ok" "True"

COLLECT_OUT="${TEST_ROOT}/collected-artifacts"
"${REPO_ROOT}/scripts/collect-mac-artifacts.sh" fake-mac "${BUILD_JOB_ID}" "${COLLECT_OUT}"
assert_path_exists "${COLLECT_OUT}/${BUILD_JOB_ID}"
assert_path_exists "${COLLECT_OUT}/${BUILD_JOB_ID}/logs/build.log"

assert_contains "${MAC_WORKER_TEST_LOG}" "xcodebuild -workspace "
assert_contains "${MAC_WORKER_TEST_LOG}" "FakeApp.xcworkspace build -scheme FakeApp"
assert_contains "${MAC_WORKER_TEST_LOG}" "xcrun simctl list devices available --json"
assert_contains "${MAC_WORKER_TEST_LOG}" "open -b com.example.FakeApp"
assert_contains "${MAC_WORKER_TEST_LOG}" "ssh fake-mac mac_worker build --project-profile ${FAKE_PROFILE_NAME} --json"
assert_contains "${MAC_WORKER_TEST_LOG}" "rsync -av"

printf '\nAll mac_worker v1 smoke phases passed.\n'
printf 'Worker home: %s\n' "${FAKE_WORKER_HOME}"
printf 'Tool log: %s\n' "${MAC_WORKER_TEST_LOG}"
