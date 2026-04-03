#!/bin/bash
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: install-openclaw-mac-agent-config.sh <worker-user> [agent-repo-path] [app-repo-path] [config-path]

Writes a repos.json file for openclaw-mac-agent using the current
masterofdrums-pipeline worker layout and prints the matching SSH forced-command
wrapper path.

Defaults:
  agent-repo-path  /Users/<worker-user>/workspace/openclaw-mac-agent
  app-repo-path    /Users/<worker-user>/workspace/masterofdrums-pipeline
  config-path      <agent-repo-path>/tools/openclaw-mac-agent/config/repos.json

Optional environment:
  OPENCLAW_PUBLIC_KEY_FILE  If set to a public key file, prints a ready-to-paste
                            authorized_keys line for the openclaw-mac-agent SSH key.

Examples:
  ./scripts/install-openclaw-mac-agent-config.sh openclaw-agent
  OPENCLAW_PUBLIC_KEY_FILE=~/.ssh/id_ed25519.pub \
    ./scripts/install-openclaw-mac-agent-config.sh openclaw-agent
USAGE
}

WORKER_USER="${1:-}"
if [[ -z "$WORKER_USER" || "$WORKER_USER" == "--help" || "$WORKER_USER" == "-h" ]]; then
  usage
  exit 0
fi

AGENT_REPO_PATH="${2:-/Users/${WORKER_USER}/workspace/openclaw-mac-agent}"
APP_REPO_PATH="${3:-/Users/${WORKER_USER}/workspace/masterofdrums-pipeline}"
CONFIG_PATH="${4:-${AGENT_REPO_PATH}/tools/openclaw-mac-agent/config/repos.json}"
WRAPPER_PATH="${AGENT_REPO_PATH}/tools/openclaw-mac-agent/bin/openclaw-mac-agent-ssh-wrapper"

mkdir -p "$(dirname "${CONFIG_PATH}")"

cat > "${CONFIG_PATH}" <<EOF
{
  "repos": {
    "masterofdrums-pipeline": {
      "path": "${APP_REPO_PATH}",
      "roots": {
        "logs": "{repo}/logs",
        "artifacts": "{repo}/output",
        "tmp": "{repo}/tmp",
        "runs": "{repo}/runs"
      },
      "recipes": {
        "validate-analyzer": {
          "argv": [
            "{repo}/.venv/bin/python",
            "{repo}/scripts/analyzer-wrapper.py",
            "--input",
            "{source_path}",
            "--output",
            "{root_tmp}/validate-analyzer-output.json"
          ],
          "timeout_seconds": 60
        }
      },
      "pipeline_profiles": {
        "debug": {
          "argv": [
            "{repo}/.venv/bin/python",
            "{repo}/scripts/run_pipeline.py",
            "--source-uri",
            "{source_uri}"
          ],
          "timeout_seconds": 600
        }
      }
    }
  },
  "roots": {
    "repo": "{repo}",
    "logs": "{repo}/logs",
    "artifacts": "{repo}/output",
    "tmp": "{repo}/tmp",
    "runs": "{repo}/runs"
  }
}
EOF

printf 'wrote config: %s\n' "${CONFIG_PATH}"
printf 'repo: %s\n' "${APP_REPO_PATH}"
printf 'wrapper: %s\n' "${WRAPPER_PATH}"
printf '\nNext commands on the Mac:\n'
printf '  chmod +x %q %q\n' \
  "${AGENT_REPO_PATH}/tools/openclaw-mac-agent/bin/openclaw-mac-agent" \
  "${WRAPPER_PATH}"
printf '  %q env-check --repo masterofdrums-pipeline --json\n' \
  "${AGENT_REPO_PATH}/tools/openclaw-mac-agent/bin/openclaw-mac-agent"

if [[ -n "${OPENCLAW_PUBLIC_KEY_FILE:-}" ]]; then
  if [[ ! -f "${OPENCLAW_PUBLIC_KEY_FILE}" ]]; then
    printf '\nwarning: OPENCLAW_PUBLIC_KEY_FILE not found: %s\n' "${OPENCLAW_PUBLIC_KEY_FILE}" >&2
    exit 1
  fi
  PUBLIC_KEY_LINE="$(<"${OPENCLAW_PUBLIC_KEY_FILE}")"
  printf '\nauthorized_keys line:\n'
  printf 'command="%s",no-agent-forwarding,no-port-forwarding,no-pty,no-user-rc,no-X11-forwarding %s\n' \
    "${WRAPPER_PATH}" \
    "${PUBLIC_KEY_LINE}"
fi
