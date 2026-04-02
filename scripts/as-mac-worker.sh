#!/bin/bash
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: as-mac-worker.sh <worker-user> [command...]

Runs a command as the dedicated macOS worker account using sudo -iu.
If no command is provided, an interactive login shell is started.

Examples:
  ./scripts/as-mac-worker.sh macworker
  ./scripts/as-mac-worker.sh macworker whoami
  ./scripts/as-mac-worker.sh macworker bash -lc 'cd ~/src/openclaw-mac-agent && ./tools/mac-worker/bin/mac_worker doctor --json'
  ./scripts/as-mac-worker.sh macworker bash -lc 'cd ~/src/openclaw-mac-agent && bash ./scripts/test-mac-worker-v1.sh'
USAGE
}

WORKER_USER="${1:-}"
if [[ -z "$WORKER_USER" || "$WORKER_USER" == "--help" || "$WORKER_USER" == "-h" ]]; then
  usage
  exit 0
fi

shift || true

if [[ $# -eq 0 ]]; then
  exec sudo -iu "$WORKER_USER"
fi

exec sudo -iu "$WORKER_USER" -- "$@"
