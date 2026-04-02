# Security Guidance

## Intended Deployment Model

`mac_worker` is intended to run as a dedicated macOS worker account on a real Mac and to be called over SSH by a Linux orchestrator.

Recommended baseline:

- dedicated macOS user for the worker
- no admin privileges
- no `sudo` in the worker flow
- dedicated SSH key for automation
- forced-command boundary for that key
- one or more project profiles with narrow allowlists

## Why Hardened Mode Exists

`--mode hardened` narrows the remote surface area:

- profile is mandatory
- arbitrary project roots are rejected
- workspace/project overrides are rejected
- scheme, destination, and simulator values must match profile allowlists
- artifacts and logs stay under worker-owned directories

This keeps the worker from becoming a general-purpose remote Xcode wrapper.

## SSH Gate

Use [`/Users/klewisjr/Development/MacOS/openclaw-mac-agent/tools/mac-worker/bin/mac_worker_ssh_gate`](/Users/klewisjr/Development/MacOS/openclaw-mac-agent/tools/mac-worker/bin/mac_worker_ssh_gate) as the forced command in `authorized_keys`.

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
- avoid sharing the worker account interactively
- run `bash ./scripts/test-mac-worker-v1.sh` after changes to the worker contract or gate logic

## Known v1 Limits

- no per-profile user separation
- no signed request layer beyond SSH auth
- no retention/cleanup policy yet
- no artifact checksum manifest yet
- limited audit logging
