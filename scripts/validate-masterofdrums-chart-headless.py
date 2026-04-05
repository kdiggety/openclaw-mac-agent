#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
from typing import Any, Dict, Optional


def load_chart(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def normalize_time_signature(raw_value: Any) -> Optional[Dict[str, int]]:
    if not isinstance(raw_value, dict):
        return None
    numerator = raw_value.get("numerator")
    denominator = raw_value.get("denominator")
    if numerator is None or denominator is None:
        return None
    return {"numerator": numerator, "denominator": denominator}


def normalize_contract_version(value: Any) -> Optional[str]:
    if value is None:
        return None
    return str(value)


def infer_timing(payload: Dict[str, Any]) -> Dict[str, Any]:
    timing = payload.get("timing")
    if isinstance(timing, dict):
        return {
            "bpm": timing.get("bpm"),
            "offsetSeconds": timing.get("offsetSeconds"),
            "ticksPerBeat": timing.get("ticksPerBeat"),
            "timeSignature": normalize_time_signature(timing.get("timeSignature")),
            "source": timing.get("source"),
        }

    chart = payload.get("chart") or {}
    source = None
    if payload.get("chartStage") == "base_chart_v1":
        source = "generated"

    measures = chart.get("measures") or []
    first_measure = measures[0] if measures and isinstance(measures[0], dict) else {}
    return {
        "bpm": chart.get("bpm"),
        "offsetSeconds": chart.get("offsetSeconds"),
        "ticksPerBeat": chart.get("ticksPerBeat"),
        "timeSignature": normalize_time_signature(first_measure.get("timeSignature")),
        "source": source,
    }


def mismatch(field: str, expected, actual):
    return {"code": "EXPECTED_TIMING_MISMATCH", "details": {"field": field, "expected": expected, "actual": actual}}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--chart", required=True)
    parser.add_argument("--mode", required=True)
    parser.add_argument("--audio", default="")
    parser.add_argument("--expected-bpm", default="")
    parser.add_argument("--expected-offset-seconds", default="")
    parser.add_argument("--expected-ticks-per-beat", default="")
    parser.add_argument("--expected-time-signature", default="")
    parser.add_argument("--expected-timing-source", default="")
    args = parser.parse_args()

    payload = load_chart(Path(args.chart))
    timing = infer_timing(payload)
    warnings = []
    errors = []
    ui_observations = []
    contract_version = normalize_contract_version(payload.get("timingContractVersion", payload.get("schemaVersion")))

    if timing["bpm"] is None:
        warnings.append("Chart timing is missing bpm.")
    if timing["offsetSeconds"] is None:
        warnings.append("Chart timing is missing offsetSeconds.")
    if timing["ticksPerBeat"] is None:
        warnings.append("Chart timing is missing ticksPerBeat.")
    if timing["timeSignature"] is None:
        warnings.append("Chart timing is missing timeSignature.")
    if timing["source"] is None:
        warnings.append("Chart timing is missing source.")

    if contract_version and timing["source"]:
        ui_observations.append(f"Timing source should present Chart Timing v{contract_version} · {str(timing['source']).replace('_', ' ').title()}")

    if timing["source"] == "generated":
        ui_observations.append("Generated chart timing should remain authoritative")

    if args.audio:
        ui_observations.append("Audio BPM should be presented as diagnostic only")

    if args.mode in {"manual-override", "full"}:
        warnings.append("Manual override behavior still requires app/UI verification on feature/chart-timing-contract.")

    if args.expected_bpm:
        expected = float(args.expected_bpm)
        actual = timing["bpm"]
        if actual != expected:
            errors.append(mismatch("bpm", expected, actual))
    if args.expected_offset_seconds:
        expected = float(args.expected_offset_seconds)
        actual = timing["offsetSeconds"]
        if actual != expected:
            errors.append(mismatch("offsetSeconds", expected, actual))
    if args.expected_ticks_per_beat:
        expected = int(args.expected_ticks_per_beat)
        actual = timing["ticksPerBeat"]
        if actual != expected:
            errors.append(mismatch("ticksPerBeat", expected, actual))
    if args.expected_time_signature:
        numerator, denominator = (int(part) for part in args.expected_time_signature.split("/", 1))
        expected = {"numerator": numerator, "denominator": denominator}
        actual = timing["timeSignature"]
        if actual != expected:
            errors.append(mismatch("timeSignature", expected, actual))
    if args.expected_timing_source:
        expected = args.expected_timing_source
        actual = timing["source"]
        if actual != expected:
            errors.append(mismatch("source", expected, actual))

    authority_checks = {
        "generatedTimingAuthoritative": timing["source"] == "generated" if timing["source"] is not None else None,
        "audioDetectionDiagnosticOnly": True if args.audio and timing["source"] == "generated" else (True if args.audio else None),
        "manualOverrideExplicit": None,
        "timeSignatureRespected": bool(timing["timeSignature"]),
    }

    status = "pass"
    if errors:
        status = "fail"
    elif warnings:
        status = "partial"

    result = {
        "status": status,
        "timingContractVersion": contract_version,
        "timing": timing,
        "authorityChecks": authority_checks,
        "uiObservations": ui_observations,
        "artifacts": {
            "screenshots": [],
            "logs": [],
            "xcresult": None,
        },
        "warnings": warnings,
        "errors": errors,
    }
    print(json.dumps(result, separators=(",", ":")))
    return 0 if not errors else 22


if __name__ == "__main__":
    raise SystemExit(main())
