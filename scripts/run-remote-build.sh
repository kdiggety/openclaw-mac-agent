#!/bin/bash
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: run-remote-build.sh <mac-host> <project-profile> [command] [worker args...]

This helper assumes the remote SSH key is configured with the mac_worker forced-command gate.

Examples:
  run-remote-build.sh mac-mini sample-macos-app build
  run-remote-build.sh mac-mini sample-ios-app test --job-id ci-123
  run-remote-build.sh mac-mini sample-ios-app ui-test --simulator "iPhone 16"
USAGE
}

MAC_HOST="${1:-}"
PROJECT_PROFILE="${2:-}"
COMMAND="${3:-build}"

if [[ -z "$MAC_HOST" || -z "$PROJECT_PROFILE" ]]; then
  usage >&2
  exit 2
fi

shift 3 || true

case "$COMMAND" in
  build|test|ui-test|doctor|launch|screenshot|collect-logs) ;;
  *)
    printf 'unsupported command: %s\n' "$COMMAND" >&2
    exit 2
    ;;
esac

ssh "$MAC_HOST" \
  mac_worker "$COMMAND" --project-profile "$PROJECT_PROFILE" --json "$@"
