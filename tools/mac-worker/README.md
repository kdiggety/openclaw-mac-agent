# mac_worker Worker Guide

## Purpose

`mac_worker` is a reusable macOS-side worker for Apple build, test, simulator, launch, screenshot, and log collection tasks. The Linux orchestrator stays in charge; the Mac only exposes a narrow execution surface.

`v1` expects `python3`, Xcode command line tools, and the normal Apple developer utilities (`xcodebuild`, `xcrun`, `simctl`, `log`, `screencapture`) to be available on the Mac.

## Commands

```text
doctor
build
test
ui-test
launch
screenshot
collect-logs
```

## Modes

### `--mode dev`

Use for local engineering workflows on the Mac:

- flexible `--project-root`
- explicit workspace/project selection
- explicit output naming under worker-owned directories

### `--mode hardened`

Use for SSH-triggered automation:

- `--project-profile` required
- `--project-root` rejected
- workspace/project overrides rejected
- scheme, destination, and simulator constrained by profile allowlists
- output paths constrained to worker-owned directories

## Project Profiles

Profiles are JSON files under `config/projects/`.

Supported fields:

- `projectRoot`
- `workspacePath` or `projectPath`
- `defaultScheme`
- `allowedSchemes`
- `defaultDestination`
- `allowedDestinations`
- `defaultSimulator`
- `allowedSimulators`
- `bundleId`

Example:

```json
{
  "projectRoot": "/Users/worker/src/apple-apps/sample-ios-app",
  "workspacePath": "SampleiOSApp.xcworkspace",
  "defaultScheme": "SampleiOSApp",
  "allowedSchemes": ["SampleiOSApp"],
  "defaultDestination": "platform=iOS Simulator,name=iPhone 16",
  "allowedDestinations": ["platform=iOS Simulator,name=iPhone 16"],
  "defaultSimulator": "iPhone 16",
  "allowedSimulators": ["iPhone 16"],
  "bundleId": "com.example.SampleiOSApp"
}
```

## Output Layout

The worker keeps its own state and outputs under `~/mac-worker` by default:

- `~/mac-worker/work/jobs/<job-id>/`
- `~/mac-worker/work/artifacts/<job-id>/`
- `~/mac-worker/work/logs/<job-id>/`

Override the base with `MAC_WORKER_HOME` in `config/env.sh` if you need a different worker-owned location.

## Local Setup

1. Copy `config/env.example.sh` to `config/env.sh`.
2. Update `MAC_WORKER_HOME` if needed.
3. Add real profiles in `config/projects/`.
4. Make `bin/mac_worker` executable.
5. Validate with `doctor`.
6. Run the smoke harness before wiring this into a remote orchestrator.

## Examples

Local doctor:

```bash
./bin/mac_worker doctor --json
```

Local dev build:

```bash
./bin/mac_worker build \
  --mode dev \
  --project-root /Users/worker/src/apple-apps/sample-macos-app \
  --workspace SampleMacApp.xcworkspace \
  --scheme SampleMacApp \
  --json
```

Hardened build:

```bash
./bin/mac_worker build --mode hardened --project-profile sample-macos-app --json
```

Hardened UI test:

```bash
./bin/mac_worker ui-test --mode hardened --project-profile sample-ios-app --json
```

Launch by bundle id from profile:

```bash
./bin/mac_worker launch --mode hardened --project-profile sample-ios-app --json
```

Collect logs:

```bash
./bin/mac_worker collect-logs --mode hardened --project-profile sample-ios-app --last 15m --json
```

## Smoke Test

The repo includes a self-contained smoke/integration harness at [`/Users/klewisjr/Development/MacOS/openclaw-mac-agent/scripts/test-mac-worker-v1.sh`](/Users/klewisjr/Development/MacOS/openclaw-mac-agent/scripts/test-mac-worker-v1.sh).

Run it with:

```bash
bash ./scripts/test-mac-worker-v1.sh
```

It stubs the Apple tools, creates a temporary project profile, and verifies:

- `doctor`, `build`, `test`, `ui-test`, `launch`, `screenshot`, and `collect-logs`
- hardened-mode allowlist enforcement
- SSH gate flag rejection and forced hardened mode
- helper-script workflow for sync, remote invoke, and artifact collection

## SSH Forced Command

Use [`/Users/klewisjr/Development/MacOS/openclaw-mac-agent/tools/mac-worker/bin/mac_worker_ssh_gate`](/Users/klewisjr/Development/MacOS/openclaw-mac-agent/tools/mac-worker/bin/mac_worker_ssh_gate) as the forced command for the worker SSH key. It only allows approved `mac_worker` commands and always re-executes the worker in hardened mode.

See [`/Users/klewisjr/Development/MacOS/openclaw-mac-agent/docs/security.md`](/Users/klewisjr/Development/MacOS/openclaw-mac-agent/docs/security.md) for an example `authorized_keys` entry.

## Swift Scaffold

The Swift CLI under `Sources/mac_worker/` should stay aligned with the shell command contract, but the shell worker remains the primary `v1`.
