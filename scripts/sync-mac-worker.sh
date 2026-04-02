#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

MAC_HOST="${1:?usage: $0 <mac-host> [remote-repo-path]}"
REMOTE_REPO_PATH="${2:-~/src/openclaw-mac-agent}"

rsync \
  -av \
  --delete \
  --exclude '.git/' \
  --exclude '.build/' \
  --exclude 'tools/mac-worker/work/' \
  "${REPO_ROOT}/" \
  "${MAC_HOST}:${REMOTE_REPO_PATH}/"
