# Security Guidance

## Intended Deployment Model

`openclaw-mac-agent` and `mac_worker` are both intended to run as a dedicated macOS worker account on a real Mac and to be called over SSH by a Linux orchestrator.

Recommended baseline:

- dedicated macOS user for the worker
- no admin privileges
- no `sudo` in the worker flow
- dedicated SSH key for automation
- forced-command boundary for that key
- one or more project profiles with narrow allowlists
- one or more repo maps and named roots with narrow allowlists

## Why Hardened Mode Exists

`--mode hardened` narrows the remote surface area:

- profile is mandatory
- arbitrary project roots are rejected
- workspace/project overrides are rejected
- scheme, destination, and simulator values must match profile allowlists
- artifacts and logs stay under worker-owned directories

This keeps the worker from becoming a general-purpose remote Xcode wrapper.

## Why openclaw-mac-agent Exists

`openclaw-mac-agent` covers the broader OpenClaw repo/debug contract without opening a shell:

- fixed logical repo names instead of caller-supplied absolute paths
- named roots with relative-path-only access
- JSON-only output
- fixed internal recipes for analyzer and pipeline verbs
- bounded long-running work through `run_id` plus polling instead of persistent sessions

This keeps repo inspection and pipeline debugging useful without turning SSH access into a general remote shell.

## SSH Gates

Use a dedicated forced-command wrapper per SSH key in `authorized_keys`.

For `mac_worker`, use [`/Users/klewisjr/Development/MacOS/openclaw-mac-agent/tools/mac-worker/bin/mac_worker_ssh_gate`](/Users/klewisjr/Development/MacOS/openclaw-mac-agent/tools/mac-worker/bin/mac_worker_ssh_gate).

Example:

```text
command="/Users/worker/src/openclaw-mac-agent/tools/mac-worker/bin/mac_worker_ssh_gate",no-agent-forwarding,no-port-forwarding,no-pty,no-user-rc,no-X11-forwarding ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... linux-orchestrator
```

Remote command examples:

```bash
ssh worker@mac-mini 'mac_worker doctor --project-profile sample-macos-app --json'
ssh worker@mac-mini 'mac_worker build --project-profile sample-macos-app --json'
ssh worker@mac-mini 'mac_worker ui-test --project-profile sample-ios-app --simulator "iPhone 16" --json'
```

The gate will:

- reject unknown commands
- reject unsafe flags such as `--project-root`, `--workspace`, `--project`, `--app`, `--out`, and `--mode`
- force `--mode hardened`
- optionally log invocations to `~/mac-worker/ssh-gate.log`

For `openclaw-mac-agent`, use [`/Users/klewisjr/Development/MacOS/openclaw-mac-agent/tools/openclaw-mac-agent/bin/openclaw-mac-agent-ssh-wrapper`](/Users/klewisjr/Development/MacOS/openclaw-mac-agent/tools/openclaw-mac-agent/bin/openclaw-mac-agent-ssh-wrapper).

Example:

```text
command="/Users/worker/src/openclaw-mac-agent/tools/openclaw-mac-agent/bin/openclaw-mac-agent-ssh-wrapper",no-agent-forwarding,no-port-forwarding,no-pty,no-user-rc,no-X11-forwarding ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... openclaw-debug
```

The wrapper will:

- require the remote command to begin with `openclaw-mac-agent`
- reject malformed or empty SSH commands
- dispatch only through the structured CLI
- log invocations to `~/.openclaw-mac-agent/logs/ssh-wrapper.log`

Recommended rollout order:

1. validate locally with `bash ./scripts/test-openclaw-mac-agent.sh`
2. install a real `tools/openclaw-mac-agent/config/repos.json` on the Mac with `bash ./scripts/install-openclaw-mac-agent-config.sh openclaw-agent`
3. wire the SSH key to `openclaw-mac-agent-ssh-wrapper`
4. validate remotely with `bash ./scripts/test-openclaw-mac-agent-remote.sh` from Linux

## Profile Recommendations

- keep one profile per app/project target
- keep allowlists narrow
- prefer a single allowed scheme unless there is a strong reason not to
- prefer a single allowed simulator/device family for CI-style usage
- keep the project root inside the dedicated worker user's home directory when practical

## Operational Notes

- treat the macOS worker as disposable infrastructure where practical
- use separate SSH keys for separate orchestrators or environments
- review `~/mac-worker/work/` and `~/mac-worker/ssh-gate.log` regularly
- review `~/.openclaw-mac-agent/logs/audit.log` and `~/.openclaw-mac-agent/logs/ssh-wrapper.log` regularly
- avoid sharing the worker account interactively
- run `bash ./scripts/test-mac-worker-v1.sh` after changes to the worker contract or gate logic
- run `bash ./scripts/test-openclaw-mac-agent.sh` after changes to the `openclaw-mac-agent` contract or wrapper logic

## Known v1 Limits

- no per-profile user separation
- no signed request layer beyond SSH auth
- no retention/cleanup policy yet
- no artifact checksum manifest yet
- limited audit logging
- no direct artifact download path over the forced-command key
