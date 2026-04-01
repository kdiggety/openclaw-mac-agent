#!/bin/bash
set -euo pipefail
MAC_HOST="${1:?usage: $0 <mac-host> [remote-repo-path]}"
REMOTE_REPO_PATH="${2:-~/src/your-repo}"
ssh "$MAC_HOST" "cd '$REMOTE_REPO_PATH' && ./tools/mac-worker/bin/mac_worker build --scheme DrumApp --workspace apps/DrumApp/DrumApp.xcworkspace --json"
