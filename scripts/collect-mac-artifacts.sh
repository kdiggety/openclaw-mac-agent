#!/bin/bash
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: collect-mac-artifacts.sh <mac-host> <job-id> [local-out-dir]

Examples:
  collect-mac-artifacts.sh mac-mini job-20260401-123456 ./mac-artifacts
USAGE
}

MAC_HOST="${1:-}"
JOB_ID="${2:-}"
LOCAL_OUT="${3:-./mac-artifacts}"
REMOTE_WORKER_HOME="${REMOTE_MAC_WORKER_HOME:-~/mac-worker}"
REMOTE_ARTIFACT_ROOT="${REMOTE_WORKER_HOME}/work/artifacts"
REMOTE_LOG_ROOT="${REMOTE_WORKER_HOME}/work/logs"

if [[ -z "$MAC_HOST" || -z "$JOB_ID" ]]; then
  usage >&2
  exit 2
fi

mkdir -p "$LOCAL_OUT"
rsync -av "${MAC_HOST}:${REMOTE_ARTIFACT_ROOT}/${JOB_ID}/" "${LOCAL_OUT}/${JOB_ID}/"

if ssh "$MAC_HOST" test -d "${REMOTE_LOG_ROOT}/${JOB_ID}"; then
  mkdir -p "${LOCAL_OUT}/${JOB_ID}/logs"
  rsync -av "${MAC_HOST}:${REMOTE_LOG_ROOT}/${JOB_ID}/" "${LOCAL_OUT}/${JOB_ID}/logs/"
fi
