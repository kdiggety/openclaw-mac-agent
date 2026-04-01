#!/bin/bash
set -euo pipefail
MAC_HOST="${1:?usage: $0 <mac-host> [remote-repo-path] [local-out]}"
REMOTE_REPO_PATH="${2:-~/src/your-repo}"
LOCAL_OUT="${3:-./mac-artifacts}"
mkdir -p "$LOCAL_OUT"
rsync -av "$MAC_HOST":"$REMOTE_REPO_PATH"/tools/mac-worker/work/artifacts/ "$LOCAL_OUT"/
