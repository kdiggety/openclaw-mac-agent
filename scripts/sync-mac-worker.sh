#!/bin/bash
set -euo pipefail
MAC_HOST="${1:?usage: $0 <mac-host> [remote-repo-path]}"
REMOTE_REPO_PATH="${2:-~/src/your-repo}"
rsync -av tools/mac-worker/ "$MAC_HOST":"$REMOTE_REPO_PATH"/tools/mac-worker/
