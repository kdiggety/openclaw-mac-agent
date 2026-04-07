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

- `agent-version`
- `self-update`
- `config-status`
- `refresh-config`
- `env-check`
- `repo-status`
- `read-file`
- `tail-file`
- `list-artifacts`
- `summarize-artifact`
- `swift-build`
- `swift-test`
- `validate-analyzer`
- `validate-masterofdrums-chart`
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

Build/test stages are now fail-closed for merge-readiness flows:

- `swift-build` requires an explicit configured build recipe
- `swift-test` requires an explicit configured test recipe
- wrappers should treat missing build/test config as `NO-GO`, not as a skipped or inferred pass

```text
config/masterofdrums-pipeline.example.json
```

and adapt the `validate-analyzer` and `pipeline_profiles.debug` recipes to match the real repo scripts that should be exposed remotely.

For app-level `masterofdrums` validation, add a separate repo entry with `app_validation.build_recipe`, `app_validation.test_recipe`, and `app_validation.import_recipe`. You can optionally add `app_validation.integration_recipe` for richer controller/UI-state checks. `app_validation.build_recipes` is still supported by `validate-masterofdrums-chart`, but merge-readiness wrappers now call `swift-build` and `swift-test` as separate required stages. The new `validate-masterofdrums-chart` verb will:

- `git-sync` the repo to an exact branch and commit
- resolve chart/audio paths against named roots
- run the configured build recipe or build step sequence
- run the configured chart-import/timing validation recipe
- optionally run a configured integration validation recipe for `manual-override`, `mismatch-diagnostic`, or `full`
- return structured JSON for build/import/authority-check results

For the current `masterofdrums` SwiftPM layout, prefer `build_recipes` with:

- `swift build --package-path {repo}`
- `swift test --package-path {repo}`

If the app later grows a committed Xcode project or workspace, you can switch the build stage to an allowlisted `xcodebuild` recipe instead.

The checked-in `masterofdrums-pipeline` example now targets the real app flow:

- `validate-analyzer` calls `swift run MasterOfDrumsPipeline validate-audio-analyzer`
- `run-pipeline --profile debug` calls [`/Users/klewisjr/Development/MacOS/openclaw-mac-agent/scripts/run-masterofdrums-pipeline-debug.py`](/Users/klewisjr/Development/MacOS/openclaw-mac-agent/scripts/run-masterofdrums-pipeline-debug.py), which orchestrates:
  - `init-db`
  - `enqueue-audio-ingest`
  - `worker --stop-after-idle-polls 2`
  - `list-jobs`
  - `list-events`
  - `list-artifacts`
- sample inputs can be declared in config via `sample_sources` and grouped into `sample_sets`, with a profile-level `default_sample_set`, `default_source_name`, or `default_source_uri`
- Linux can optionally request a logical `sample_set`, but the Mac-side config owns the actual file paths

To generate a real `repos.json` for the dedicated Mac worker account, use:

```bash
bash ./scripts/install-openclaw-mac-agent-config.sh openclaw-agent
```

If you already have the Linux-side public key available, the helper can also print a ready-to-paste `authorized_keys` line:

```bash
OPENCLAW_PUBLIC_KEY_FILE=~/.ssh/id_ed25519.pub \
bash ./scripts/install-openclaw-mac-agent-config.sh openclaw-agent
```

`agent-version` reports the deployed agent repo head/branch/dirty state.

`self-update` performs a bounded `git fetch origin` + `git checkout --force <ref>` inside the agent repo only.

`config-status` reports whether the current `repos.json` includes the expected app/pipeline validation sections.

`refresh-config` reruns the checked-in installer script to regenerate a worker config without requiring shell access.

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

For the `masterofdrums-pipeline` debug profile, each run now writes repo-local files under `runs/<run-id>/`, including:

- `stdout.log`
- `stderr.log`
- `status.json`
- `steps/*.stdout.log`
- `steps/*.stderr.log`
- `artifacts/summary.json`

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

## OpenClaw Wrapper

For the actual OpenClaw-driven validation flow, use:

```bash
TARGET_BRANCH=main \
EXPECTED_COMMIT=<sha> \
MAC_SSH_KEY=~/.ssh/openclaw_mac_agent \
bash ./scripts/run-openclaw-masterofdrums-validation.sh
```

For app-level `masterofdrums` validation, use:

```bash
TARGET_BRANCH=feature/chart-timing-contract \
EXPECTED_COMMIT=<sha> \
CHART_ROOT=fixtures \
CHART_PATH=validation-fixture.modchart.json \
MAC_SSH_KEY=~/.ssh/openclaw_mac_agent \
bash ./scripts/run-openclaw-masterofdrums-app-validation.sh
```

This wrapper belongs in the agent repo rather than the pipeline repo because it owns:

- SSH transport details
- branch/commit sync semantics
- polling and result collation
- the final machine-readable validation payload

The app wrapper uses the same SSH forced-command surface, but calls `validate-masterofdrums-chart` instead of the pipeline verbs.

If `SOURCE_URI` and `SOURCE_NAME` are omitted, the wrapper now relies on the Mac-side profile default configured in `repos.json`.
