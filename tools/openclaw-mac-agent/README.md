# openclaw-mac-agent

`openclaw-mac-agent` is a shell-free, JSON-speaking macOS-side agent intended for OpenClaw-style remote debugging and bounded pipeline execution over SSH forced-command access.

## Design

- JSON-only responses
- logical repo names mapped to fixed absolute paths
- named roots with relative-path-only file access
- fixed internal recipes for write/execute verbs
- no generic shell access
- no persistent interactive sessions

## Verbs

- `env-check`
- `repo-status`
- `read-file`
- `tail-file`
- `list-artifacts`
- `summarize-artifact`
- `validate-analyzer`
- `run-pipeline`
- `get-run-status`
- `git-fetch`
- `git-pull --ff-only`

## Config

Copy:

```text
config/repos.example.json
```

to:

```text
config/repos.json
```

and update repo paths plus any recipe/profile commands needed for your project.

For the current `masterofdrums-pipeline` worker layout, start from:

```text
config/masterofdrums-pipeline.example.json
```

and adapt the `validate-analyzer` and `pipeline_profiles.debug` recipes to match the real repo scripts that should be exposed remotely.

To generate a real `repos.json` for the dedicated Mac worker account, use:

```bash
bash ./scripts/install-openclaw-mac-agent-config.sh openclaw-agent
```

If you already have the Linux-side public key available, the helper can also print a ready-to-paste `authorized_keys` line:

```bash
OPENCLAW_PUBLIC_KEY_FILE=~/.ssh/id_ed25519.pub \
bash ./scripts/install-openclaw-mac-agent-config.sh openclaw-agent
```

## SSH Forced Command

Use:

[`/Users/klewisjr/Development/MacOS/openclaw-mac-agent/tools/openclaw-mac-agent/bin/openclaw-mac-agent-ssh-wrapper`](/Users/klewisjr/Development/MacOS/openclaw-mac-agent/tools/openclaw-mac-agent/bin/openclaw-mac-agent-ssh-wrapper)

as the forced command for an SSH key dedicated to OpenClaw repo/debug operations.

The wrapper expects remote invocations shaped like:

```bash
ssh worker@mac 'openclaw-mac-agent env-check --repo masterofdrums-pipeline --json'
```

and rejects anything that does not begin with `openclaw-mac-agent`.

## Long Runs

`run-pipeline` starts a bounded background run and returns a `run_id`. OpenClaw can poll:

- `get-run-status`
- `tail-file --root runs`
- `list-artifacts --root runs`

instead of relying on persistent sessions.

## Remote Smoke Test

From Linux/OpenClaw, use:

```bash
bash ./scripts/test-openclaw-mac-agent-remote.sh
```

If you want a reusable local config on Linux, start from:

```text
scripts/test-openclaw-mac-agent-remote.env.example
```

and load it like this:

```bash
cp scripts/test-openclaw-mac-agent-remote.env.example scripts/test-openclaw-mac-agent-remote.env
set -a
source scripts/test-openclaw-mac-agent-remote.env
set +a
bash ./scripts/test-openclaw-mac-agent-remote.sh
```

Update `MAC_AGENT_LOG_ROOT` and `MAC_AGENT_LOG_PATH` in that env file to match a real log file in the target repo.
Those overrides are optional. If unset, the script will auto-discover a readable file from `logs/`, `runs/`, or `output/`.

to exercise the real forced-command path with:

- `env-check`
- `repo-status`
- `tail-file`
- `list-artifacts`
