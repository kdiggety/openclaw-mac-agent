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
      "sample_sources": {
        "known-tone": "file:///Users/${WORKER_USER}/workspace/masterofdrums-pipeline/Tests/PipelineRuntimeTests/Fixtures/known-tone.wav",
        "looperman-sad-drum-part-trap": "file:///Users/${WORKER_USER}/workspace/openclaw-mac-agent/looperman-l-1561860-0105686-ricciog-sad-drum-part-trap.wav",
        "looperman-dentist-drill-drums": "file:///Users/${WORKER_USER}/workspace/openclaw-mac-agent/looperman-l-2212484-0228674-dentist-drill-drums.wav",
        "looperman-wheezy-type-drum-loop": "file:///Users/${WORKER_USER}/workspace/openclaw-mac-agent/looperman-l-2786851-0217164-wheezy-type-drum-loop.wav",
        "looperman-motion-trap-drums": "file:///Users/${WORKER_USER}/workspace/openclaw-mac-agent/looperman-l-6643862-0403387-motion-trap-drums.wav"
      },
      "sample_sets": {
        "smoke": [
          "known-tone"
        ],
        "looperman-120": [
          "looperman-sad-drum-part-trap",
          "looperman-dentist-drill-drums",
          "looperman-wheezy-type-drum-loop",
          "looperman-motion-trap-drums"
        ]
      },
      "roots": {
        "logs": "{repo}/logs",
        "artifacts": "{repo}/output",
        "tmp": "{repo}/tmp",
        "runs": "{repo}/runs"
      },
      "validation": {
        "build_recipe": {
          "argv": [
            "/usr/bin/env",
            "swift",
            "build",
            "--package-path",
            "{repo}"
          ],
          "timeout_seconds": 900
        },
        "test_recipe": {
          "argv": [
            "/usr/bin/env",
            "swift",
            "test",
            "--package-path",
            "{repo}"
          ],
          "timeout_seconds": 900
        }
      },
      "recipes": {
        "validate-analyzer": {
          "argv": [
            "/usr/bin/env",
            "swift",
            "run",
            "--scratch-path",
            "{root_tmp}/swiftpm-validate",
            "MasterOfDrumsPipeline",
            "validate-audio-analyzer",
            "--source-uri",
            "{source_uri}",
            "--source-type",
            "file",
            "--requested-by",
            "openclaw-mac-agent",
            "--output-path",
            "{root_tmp}/validate-analyzer-output.json"
          ],
          "env": {
            "PIPELINE_AUDIO_ANALYZER_COMMAND": "{repo}/.venv/bin/python3 ./scripts/analyzer-wrapper.py --input {input} --output {output}",
            "PIPELINE_ANALYZER_PRIMARY_BACKEND_COMMAND": "{repo}/.venv/bin/python3 ./scripts/beat-this-backend.py --input {input} --output {output}",
            "PIPELINE_ANALYZER_FALLBACK_BACKEND_COMMAND": "{repo}/.venv/bin/python3 ./scripts/backend-analyzer.py --input {input} --output {output}",
            "PIPELINE_ANALYZER_FALLBACK_POLICY": "on-error-or-invalid",
            "PIPELINE_ANALYZER_VALIDATION_MODE": "require-timing",
            "PIPELINE_AUDIO_ANALYZER_TIMEOUT_SECONDS": "300",
            "PIPELINE_AUDIO_ANALYZER_STDOUT_JSON": "false"
          },
          "timeout_seconds": 60
        }
      },
      "pipeline_profiles": {
        "debug": {
          "default_sample_set": "smoke",
          "argv": [
            "/usr/bin/python3",
            "{agent_repo}/scripts/run-masterofdrums-pipeline-debug.py",
            "--repo-root",
            "{repo}",
            "--scratch-path",
            "{run_dir}/swiftpm-debug",
            "--requested-by",
            "openclaw-mac-agent",
            "--stop-after-idle-polls",
            "2",
            "--list-limit",
            "20",
            "--source-uri",
            "{source_uri}"
          ],
          "env": {
            "PIPELINE_AUDIO_ANALYZER_COMMAND": "{repo}/.venv/bin/python3 ./scripts/analyzer-wrapper.py --input {input} --output {output}",
            "PIPELINE_ANALYZER_PRIMARY_BACKEND_COMMAND": "{repo}/.venv/bin/python3 ./scripts/beat-this-backend.py --input {input} --output {output}",
            "PIPELINE_ANALYZER_FALLBACK_BACKEND_COMMAND": "{repo}/.venv/bin/python3 ./scripts/backend-analyzer.py --input {input} --output {output}",
            "PIPELINE_ANALYZER_FALLBACK_POLICY": "on-error-or-invalid",
            "PIPELINE_ANALYZER_VALIDATION_MODE": "require-timing",
            "PIPELINE_AUDIO_ANALYZER_TIMEOUT_SECONDS": "300",
            "PIPELINE_AUDIO_ANALYZER_STDOUT_JSON": "false"
          },
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
