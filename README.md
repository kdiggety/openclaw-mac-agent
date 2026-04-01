# mac_worker project scaffold

This repo is a starter scaffold for a thin macOS validation/build worker that can be driven by OpenClaw or any Linux-hosted orchestrator.

## Purpose

Use this when:
- your main agent/orchestrator runs on Linux
- you need a real Mac for Xcode, Simulator, signing, screenshots, and logs
- you want all code version-controlled in GitHub

## What runs where

### On the Mac
- `tools/mac-worker/bin/mac_worker`
- Xcode build/test/UI test commands
- app launch
- screenshots
- log collection

### On Linux / Pop!_OS
- OpenClaw / orchestrator
- repo automation
- audio-analysis / chart-generation pipeline
- remote calls into the Mac over SSH

## Repo layout

```text
.
├─ README.md
├─ docs/
│  └─ architecture.md
├─ scripts/
│  ├─ sync-mac-worker.sh
│  ├─ run-remote-build.sh
│  └─ collect-mac-artifacts.sh
└─ tools/
   └─ mac-worker/
      ├─ README.md
      ├─ Package.swift
      ├─ bin/
      │  └─ mac_worker
      ├─ config/
      │  └─ env.example.sh
      └─ Sources/
         └─ mac_worker/
```

## Quick start

1. Clone this repo on both Linux and the Mac.
2. On the Mac, copy `tools/mac-worker/config/env.example.sh` to `env.sh` and edit paths.
3. Make the shell worker executable.
4. Run `mac_worker doctor --json` on the Mac.
5. Trigger it remotely over SSH from Linux.

## Example

```bash
ssh mac-mini 'cd ~/src/your-repo && ./tools/mac-worker/bin/mac_worker doctor --json'
```

## Notes

- The shell worker is the v1 implementation.
- The Swift CLI is scaffolded so you can replace internals later without changing the command contract.
- `record-video` is intentionally left unsupported in shell v1.
