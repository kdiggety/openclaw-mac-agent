# Architecture

## Goal

Keep one main agent/orchestrator on Linux and use the Mac as a thin execution node for Apple-specific tasks.

## Recommended split

### Linux / Pop!_OS
- OpenClaw or other orchestrator
- source control automation
- chart generation / ML / batch audio analysis
- job planning and dispatch

### macOS
- Xcode toolchain
- Simulator
- screenshot/log capture
- macOS/iOS app validation
- packaging/signing later if needed

## Why this split

A Mac is required for credible Apple app validation. Linux is often better for orchestration, scripting, and ML tooling. Do not turn the Mac into a second full brain unless you truly need independent autonomy.

## Command boundary

The worker should expose a small stable surface:
- `doctor`
- `build`
- `test`
- `ui-test`
- `launch`
- `screenshot`
- `collect-logs`

Profiles provide project-specific defaults and allowlists so the core worker stays reusable across multiple Apple app projects.

## Execution modes

- `dev`: local Mac developer workflows, still narrow but more flexible
- `hardened`: profile-required remote mode intended for SSH forced-command use

## Version control model

All source stays in GitHub. The same repo is cloned on Linux and on the Mac. Linux triggers commands against the Mac checkout via SSH.
