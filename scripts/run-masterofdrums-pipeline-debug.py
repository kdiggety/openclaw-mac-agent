#!/usr/bin/env python3
"""Run the real masterofdrums-pipeline CLI flow inside an OPENCLAW_RUN_DIR."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import List


@dataclass
class StepResult:
    name: str
    argv: List[str]
    exit_code: int
    stdout_path: str
    stderr_path: str
    duration_ms: int


def parse_key_value_line(line: str) -> dict[str, str]:
    data: dict[str, str] = {}
    for token in line.strip().split():
        if "=" not in token:
            continue
        key, value = token.split("=", 1)
        data[key] = value
    return data


def collect_artifacts(list_artifacts_stdout: str) -> list[dict[str, str]]:
    items: list[dict[str, str]] = []
    for raw_line in list_artifacts_stdout.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        parsed = parse_key_value_line(line)
        if "type" in parsed and "uri" in parsed:
            items.append(parsed)
    return items


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run masterofdrums-pipeline debug workflow")
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--run-dir", help="explicit run directory; defaults to OPENCLAW_RUN_DIR")
    parser.add_argument("--source-uri", required=True)
    parser.add_argument("--requested-by", default="openclaw-mac-agent")
    parser.add_argument("--stop-after-idle-polls", type=int, default=2)
    parser.add_argument("--list-limit", type=int, default=20)
    parser.add_argument("--scratch-path", help="swift run scratch/build path")
    return parser


def run_step(name: str, argv: List[str], cwd: Path, env: dict[str, str], steps_dir: Path) -> StepResult:
    stdout_path = steps_dir / f"{name}.stdout.log"
    stderr_path = steps_dir / f"{name}.stderr.log"
    started = datetime.now(timezone.utc)
    completed = subprocess.run(
        argv,
        cwd=str(cwd),
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    duration_ms = int((datetime.now(timezone.utc) - started).total_seconds() * 1000)
    stdout_path.write_text(completed.stdout or "", encoding="utf-8")
    stderr_path.write_text(completed.stderr or "", encoding="utf-8")
    return StepResult(
        name=name,
        argv=argv,
        exit_code=completed.returncode,
        stdout_path=str(stdout_path),
        stderr_path=str(stderr_path),
        duration_ms=duration_ms,
    )


def main() -> int:
    args = build_parser().parse_args()

    run_dir_raw = args.run_dir or os.environ.get("OPENCLAW_RUN_DIR")
    if not run_dir_raw:
        print("--run-dir or OPENCLAW_RUN_DIR is required", file=sys.stderr)
        return 2

    repo_root = Path(args.repo_root).expanduser().resolve()
    run_dir = Path(run_dir_raw).expanduser().resolve()
    artifacts_dir = run_dir / "artifacts"
    steps_dir = run_dir / "steps"
    artifacts_dir.mkdir(parents=True, exist_ok=True)
    steps_dir.mkdir(parents=True, exist_ok=True)

    env = os.environ.copy()
    env.setdefault("PIPELINE_DATABASE_PATH", str(run_dir / "pipeline.sqlite"))
    env.setdefault("PIPELINE_ARTIFACT_ROOT", str(artifacts_dir))
    env.setdefault("PIPELINE_AUTO_MIGRATE", "true")

    swift_prefix = ["/usr/bin/env", "swift", "run"]
    if args.scratch_path:
        swift_prefix.extend(["--scratch-path", args.scratch_path])
    swift_prefix.append("MasterOfDrumsPipeline")
    steps = [
        (
            "init-db",
            [*swift_prefix, "init-db"],
        ),
        (
            "enqueue-audio-ingest",
            [
                *swift_prefix,
                "enqueue-audio-ingest",
                "--source-uri",
                args.source_uri,
                "--source-type",
                "file",
                "--requested-by",
                args.requested_by,
            ],
        ),
        (
            "worker",
            [
                *swift_prefix,
                "worker",
                "--stop-after-idle-polls",
                str(args.stop_after_idle_polls),
            ],
        ),
        (
            "list-jobs",
            [*swift_prefix, "list-jobs"],
        ),
        (
            "list-events",
            [*swift_prefix, "list-events", "--limit", str(args.list_limit)],
        ),
        (
            "list-artifacts",
            [*swift_prefix, "list-artifacts", "--limit", str(args.list_limit)],
        ),
    ]

    results: list[StepResult] = []
    collected_artifacts: list[dict[str, str]] = []
    for name, argv in steps:
        print(f"[openclaw-mac-agent] running {name}: {' '.join(argv)}")
        result = run_step(name, argv, repo_root, env, steps_dir)
        results.append(result)
        if name == "list-artifacts":
            collected_artifacts = collect_artifacts(Path(result.stdout_path).read_text(encoding="utf-8"))
        if result.exit_code != 0:
            summary = {
                "ok": False,
                "failed_step": name,
                "finished_at": utc_now(),
                "steps": [step.__dict__ for step in results],
                "artifacts": collected_artifacts,
                "paths": {
                    "run_dir": str(run_dir),
                    "artifacts_dir": str(artifacts_dir),
                    "steps_dir": str(steps_dir),
                },
            }
            (artifacts_dir / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
            print(json.dumps(summary, separators=(",", ":")))
            return result.exit_code

    summary = {
        "ok": True,
        "finished_at": utc_now(),
        "steps": [step.__dict__ for step in results],
        "artifacts": collected_artifacts,
        "paths": {
            "run_dir": str(run_dir),
            "artifacts_dir": str(artifacts_dir),
            "steps_dir": str(steps_dir),
        },
    }
    (artifacts_dir / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
