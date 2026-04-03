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
  MAC_AGENT_LOG_ROOT      optional explicit tail-file root override
  MAC_AGENT_LOG_PATH      optional explicit tail-file path override

Notes:
  - This script assumes the dedicated SSH key is already wired to
    openclaw-mac-agent-ssh-wrapper on the Mac.
  - It only exercises JSON-returning safe verbs.
  - If no explicit log target is provided, it auto-discovers a readable file
    from logs/, runs/, or output/ on the Mac.
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

MAC_HOST="${1:-${MAC_HOST:-openclaw-agent@192.168.1.156}}"
MAC_SSH_KEY="${MAC_SSH_KEY:-$HOME/.ssh/id_ed25519}"
MAC_AGENT_REPO="${MAC_AGENT_REPO:-masterofdrums-pipeline}"
MAC_AGENT_LOG_ROOT="${MAC_AGENT_LOG_ROOT:-}"
MAC_AGENT_LOG_PATH="${MAC_AGENT_LOG_PATH:-}"

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

first_tail_candidate() {
  local list_payload="$1"
  MAC_AGENT_REMOTE_JSON="$list_payload" python3 - <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["MAC_AGENT_REMOTE_JSON"])
items = payload["data"]["items"]

preferred_suffixes = (
    ".log",
    ".txt",
    ".json",
    ".md",
    ".csv",
    ".yaml",
    ".yml",
)

def score(path: str) -> tuple[int, str]:
    lower = path.lower()
    if lower.endswith("stdout.log"):
        return (0, lower)
    if lower.endswith("stderr.log"):
        return (1, lower)
    if lower.endswith(".log"):
        return (2, lower)
    for idx, suffix in enumerate(preferred_suffixes[1:], start=3):
        if lower.endswith(suffix):
            return (idx, lower)
    return (999, lower)

candidates = [item["path"] for item in items]
if not candidates:
    sys.exit(1)

best = sorted(candidates, key=score)[0]
print(best)
PY
}

discover_tail_target() {
  local root
  local list_payload
  local candidate_path

  if [[ -n "$MAC_AGENT_LOG_ROOT" && -n "$MAC_AGENT_LOG_PATH" ]]; then
    printf '%s\t%s\n' "$MAC_AGENT_LOG_ROOT" "$MAC_AGENT_LOG_PATH"
    return 0
  fi

  for root in logs runs artifacts; do
    list_payload="$(run_remote_json list-artifacts --root "$root")"
    if [[ "$(json_field "$list_payload" "ok")" != "true" ]]; then
      continue
    fi
    candidate_path="$(first_tail_candidate "$list_payload" 2>/dev/null || true)"
    if [[ -n "$candidate_path" ]]; then
      printf '%s\t%s\n' "$root" "$candidate_path"
      return 0
    fi
  done

  return 1
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

if TAIL_TARGET="$(discover_tail_target)"; then
  IFS=$'\t' read -r DISCOVERED_ROOT DISCOVERED_PATH <<<"$TAIL_TARGET"
  TAIL_JSON="$(run_remote_json tail-file --root "$DISCOVERED_ROOT" --path "$DISCOVERED_PATH" --lines 20)"
  printf 'tail-file: ok=%s root=%s path=%s returned_lines=%s\n' \
    "$(json_field "$TAIL_JSON" "ok")" \
    "$DISCOVERED_ROOT" \
    "$DISCOVERED_PATH" \
    "$(json_field "$TAIL_JSON" "data.tail.returned_lines")"
else
  printf 'tail-file: skipped no readable file discovered under logs/, runs/, or output/\n'
fi

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
