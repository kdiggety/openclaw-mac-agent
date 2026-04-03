#!/bin/bash
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: test-openclaw-mac-agent-remote.sh [mac-host]

Runs a small remote smoke test for the openclaw-mac-agent forced-command path.

Environment overrides:
  MAC_HOST                default: openclaw-agent@192.168.1.156
  MAC_SSH_KEY             default: ~/.ssh/id_ed25519
  MAC_AGENT_REPO          default: masterofdrums-pipeline
  MAC_AGENT_LOG_ROOT      default: logs
  MAC_AGENT_LOG_PATH      default: pipeline.log

Notes:
  - This script assumes the dedicated SSH key is already wired to
    openclaw-mac-agent-ssh-wrapper on the Mac.
  - It only exercises JSON-returning safe verbs.
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

MAC_HOST="${1:-${MAC_HOST:-openclaw-agent@192.168.1.156}}"
MAC_SSH_KEY="${MAC_SSH_KEY:-$HOME/.ssh/id_ed25519}"
MAC_AGENT_REPO="${MAC_AGENT_REPO:-masterofdrums-pipeline}"
MAC_AGENT_LOG_ROOT="${MAC_AGENT_LOG_ROOT:-logs}"
MAC_AGENT_LOG_PATH="${MAC_AGENT_LOG_PATH:-pipeline.log}"

[[ -f "$MAC_SSH_KEY" ]] || {
  printf 'missing SSH private key: %s\n' "$MAC_SSH_KEY" >&2
  exit 4
}

run_remote_json() {
  local verb="$1"
  shift
  ssh -i "$MAC_SSH_KEY" "$MAC_HOST" "openclaw-mac-agent $verb --repo $MAC_AGENT_REPO --json $*"
}

json_field() {
  local json_payload="$1"
  local field_path="$2"
  MAC_AGENT_REMOTE_JSON="$json_payload" python3 - <<'PY' "$field_path"
import json
import os
import sys

value = json.loads(os.environ["MAC_AGENT_REMOTE_JSON"])
for part in sys.argv[1].split("."):
    value = value[part]

if isinstance(value, bool):
    print("true" if value else "false")
else:
    print(value)
PY
}

run_and_print() {
  local stage="$1"
  shift
  local payload
  payload="$(run_remote_json "$@")"
  printf '%s: ok=%s verb=%s\n' \
    "$stage" \
    "$(json_field "$payload" "ok")" \
    "$(json_field "$payload" "verb")"
}

ENV_JSON="$(run_remote_json env-check)"
printf 'env-check: ok=%s repo=%s\n' \
  "$(json_field "$ENV_JSON" "ok")" \
  "$(json_field "$ENV_JSON" "data.repo.name")"

STATUS_JSON="$(run_remote_json repo-status)"
printf 'repo-status: ok=%s branch=%s dirty=%s\n' \
  "$(json_field "$STATUS_JSON" "ok")" \
  "$(json_field "$STATUS_JSON" "data.git.branch")" \
  "$(json_field "$STATUS_JSON" "data.git.is_dirty")"

TAIL_JSON="$(run_remote_json tail-file --root "$MAC_AGENT_LOG_ROOT" --path "$MAC_AGENT_LOG_PATH" --lines 20)"
printf 'tail-file: ok=%s returned_lines=%s\n' \
  "$(json_field "$TAIL_JSON" "ok")" \
  "$(json_field "$TAIL_JSON" "data.tail.returned_lines")"

LIST_JSON="$(run_remote_json list-artifacts --root artifacts)"
printf 'list-artifacts: ok=%s items=%s\n' \
  "$(json_field "$LIST_JSON" "ok")" \
  "$(MAC_AGENT_REMOTE_JSON="$LIST_JSON" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["MAC_AGENT_REMOTE_JSON"])
print(len(payload["data"]["items"]))
PY
)"

printf '\nRemote openclaw-mac-agent smoke checks completed.\n'
