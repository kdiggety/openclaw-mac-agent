# mac_worker

`mac_worker` is a thin macOS-side command runner for Apple-specific build and validation tasks.

## Design goals

- JSON-first output for automation
- easy to call over SSH
- minimal dependencies
- stable command contract
- safe to version-control in a shared repo

## Commands

- `doctor`
- `build`
- `test`
- `ui-test`
- `launch`
- `screenshot`
- `collect-logs`
- `record-video` (stub in shell v1)

## Shell worker

The shell worker lives at:

```text
bin/mac_worker
```

Make it executable:

```bash
chmod +x bin/mac_worker
```

## Config

Copy:

```text
config/env.example.sh
```

To:

```text
config/env.sh
```

And update the project root.

## Example

```bash
./bin/mac_worker doctor --json
./bin/mac_worker screenshot --out latest.png --json
```

## Swift rewrite path

The Swift package scaffold preserves the same external interface. You can migrate one command at a time while keeping Linux-side orchestration unchanged.
