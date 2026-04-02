# mac_worker

`mac_worker` is a thin macOS-side build, test, and validation worker for Apple-specific tasks. It is meant to be called locally on a real Mac or remotely over SSH by a Linux-hosted orchestrator such as OpenClaw.

It is not:

- a generic remote shell agent
- an arbitrary command runner
- a replacement for the Linux orchestration layer
- hardcoded to a single app in core worker logic

`v1` expects standard macOS developer tools plus `python3` on the Mac worker for JSON-safe profile loading and path validation.

## Status

- Shell `v1` is the primary implementation: [`/Users/klewisjr/Development/MacOS/openclaw-mac-agent/tools/mac-worker/bin/mac_worker`](/Users/klewisjr/Development/MacOS/openclaw-mac-agent/tools/mac-worker/bin/mac_worker)
- Swift CLI is still a scaffold that tracks the same command surface: [`/Users/klewisjr/Development/MacOS/openclaw-mac-agent/tools/mac-worker/Sources/mac_worker`](/Users/klewisjr/Development/MacOS/openclaw-mac-agent/tools/mac-worker/Sources/mac_worker)

## Command Surface

The supported `v1` commands are:

- `doctor`
- `build`
- `test`
- `ui-test`
- `launch`
- `screenshot`
- `collect-logs`

## Repo Layout

```text
.
├─ README.md
├─ docs/
│  ├─ architecture.md
│  └─ security.md
├─ scripts/
│  ├─ sync-mac-worker.sh
│  ├─ run-remote-build.sh
│  └─ collect-mac-artifacts.sh
└─ tools/
   └─ mac-worker/
      ├─ README.md
      ├─ bin/
      │  ├─ mac_worker
      │  └─ mac_worker_ssh_gate
      ├─ config/
      │  ├─ env.example.sh
      │  └─ projects/
      └─ Sources/
         └─ mac_worker/
```

## Local Dev Mode

Local development keeps some flexibility for engineers using the worker directly on a Mac:

- `--mode dev` is the default
- `--project-root` is allowed
- explicit `--workspace`, `--project`, `--destination`, `--simulator`, and worker-owned output paths are allowed

Example:

```bash
cd ~/src/apple-apps/sample-project
./tools/mac-worker/bin/mac_worker doctor --json
./tools/mac-worker/bin/mac_worker build \
  --mode dev \
  --project-root "$PWD" \
  --workspace SampleApp.xcworkspace \
  --scheme SampleApp \
  --json
```

## Hardened Remote Mode

Hardened mode is intended for SSH-triggered automation:

- requires `--project-profile`
- rejects arbitrary `--project-root`
- rejects `--workspace` and `--project` overrides
- restricts scheme, destination, and simulator values to profile allowlists
- keeps outputs under `~/mac-worker/work/...`
- is suitable for use behind an SSH forced-command gate

Example:

```bash
mac_worker build --mode hardened --project-profile sample-macos-app --json
mac_worker ui-test --mode hardened --project-profile sample-ios-app --json
```

## Project Profiles

Profiles live under [`/Users/klewisjr/Development/MacOS/openclaw-mac-agent/tools/mac-worker/config/projects`](/Users/klewisjr/Development/MacOS/openclaw-mac-agent/tools/mac-worker/config/projects). They keep project-specific defaults out of the core worker.

Sample profiles:

- [`/Users/klewisjr/Development/MacOS/openclaw-mac-agent/tools/mac-worker/config/projects/sample-macos-app.json`](/Users/klewisjr/Development/MacOS/openclaw-mac-agent/tools/mac-worker/config/projects/sample-macos-app.json)
- [`/Users/klewisjr/Development/MacOS/openclaw-mac-agent/tools/mac-worker/config/projects/sample-ios-app.json`](/Users/klewisjr/Development/MacOS/openclaw-mac-agent/tools/mac-worker/config/projects/sample-ios-app.json)

## Setup On The Mac

1. Create a dedicated non-admin macOS user for the worker if this will be exposed over SSH.
2. Clone this repo onto the Mac.
3. Copy [`/Users/klewisjr/Development/MacOS/openclaw-mac-agent/tools/mac-worker/config/env.example.sh`](/Users/klewisjr/Development/MacOS/openclaw-mac-agent/tools/mac-worker/config/env.example.sh) to `tools/mac-worker/config/env.sh`.
4. Create one or more real project profiles in `tools/mac-worker/config/projects/`.
5. Make the worker scripts executable.
6. Run `doctor` locally first.

```bash
chmod +x tools/mac-worker/bin/mac_worker tools/mac-worker/bin/mac_worker_ssh_gate scripts/*.sh
./tools/mac-worker/bin/mac_worker doctor --json
```

## Remote Use From Linux

Typical flow:

1. Sync the repo to the Mac.
2. Invoke a hardened command over SSH.
3. Pull artifacts back by `jobId`.

Examples:

```bash
./scripts/sync-mac-worker.sh mac-mini ~/src/openclaw-mac-agent
./scripts/run-remote-build.sh mac-mini sample-macos-app build
./scripts/run-remote-build.sh mac-mini sample-ios-app ui-test --simulator "iPhone 16"
./scripts/collect-mac-artifacts.sh mac-mini job-20260401-120000-12345 ./mac-artifacts
```

Useful local-admin helper for Mac setup:

```bash
./scripts/as-mac-worker.sh WORKER_USER
./scripts/as-mac-worker.sh WORKER_USER bash -lc 'cd ~/src/openclaw-mac-agent && ./tools/mac-worker/bin/mac_worker doctor --json'
```

## OpenClaw Integration Testability

For `v1`, the worker is now testable in phases:

1. Local shell smoke and JSON contract
2. Hardened profile enforcement
3. SSH forced-command gate behavior
4. Linux-side helper script flow for sync, invoke, and artifact collection

Run the self-contained smoke harness:

```bash
bash ./scripts/test-mac-worker-v1.sh
```

That script uses fake Apple tool stubs so it can validate the `mac_worker` command contract and remote orchestration workflow shape without needing a real app project in this repo.

For the real `masterofdrums-pipeline` remote validation flow from Linux/OpenClaw, use:

```bash
bash ./scripts/validate-masterofdrums-mac.sh
```

By default this wrapper:

- calls remote `doctor`, `build`, and `test`
- requires `doctor` and `build` to pass
- collects job artifacts/logs locally
- reports `test` failures in the summary without failing the wrapper unless `MAC_STRICT_TESTS=1` is set

## Artifacts And Logs

All worker-owned output goes under the macOS worker user's home directory:

- `~/mac-worker/work/jobs/<job-id>/`
- `~/mac-worker/work/artifacts/<job-id>/`
- `~/mac-worker/work/logs/<job-id>/`

## Security Guidance

Use the worker behind an SSH forced-command boundary rather than giving automation a full shell. See [`/Users/klewisjr/Development/MacOS/openclaw-mac-agent/docs/security.md`](/Users/klewisjr/Development/MacOS/openclaw-mac-agent/docs/security.md).

## v1 Limitations

- no generic command execution by design
- no signing/notarization pipeline yet
- no artifact manifest or retention policy yet
- Swift implementation is still partial
- profile format is intentionally simple and static

## Next Reads

- Worker-specific details: [`/Users/klewisjr/Development/MacOS/openclaw-mac-agent/tools/mac-worker/README.md`](/Users/klewisjr/Development/MacOS/openclaw-mac-agent/tools/mac-worker/README.md)
- Security and SSH gate setup: [`/Users/klewisjr/Development/MacOS/openclaw-mac-agent/docs/security.md`](/Users/klewisjr/Development/MacOS/openclaw-mac-agent/docs/security.md)
- Architecture overview: [`/Users/klewisjr/Development/MacOS/openclaw-mac-agent/docs/architecture.md`](/Users/klewisjr/Development/MacOS/openclaw-mac-agent/docs/architecture.md)
