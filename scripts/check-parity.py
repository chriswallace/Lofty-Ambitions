#!/usr/bin/env python3
"""Compare every canonical save field against the shared replay baseline.

Object key order is irrelevant; array order and all integer/string/bool/null
values are exact. Floating-point fields use an absolute tolerance of 1e-9,
without relative tolerance, rounding, missing-field exclusions, or NaN support.
"""
from __future__ import annotations

import argparse
import decimal
import hashlib
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
FIXTURE = ROOT / "Tests/Fixtures/construction-transit-fire-v1.json"
EXPECTED = ROOT / "Tests/Fixtures/construction-transit-fire-v1.snapshot.json"
TOLERANCE = decimal.Decimal("0.000000001")


def digest(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path: pathlib.Path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"Duplicate JSON key {key!r} in {path}")
            result[key] = value
        return result

    def invalid(value):
        raise ValueError(f"Non-finite JSON number {value} in {path}")

    with path.open(encoding="utf-8-sig") as stream:
        return json.load(stream, parse_float=decimal.Decimal,
                         parse_constant=invalid, object_pairs_hook=unique)


def differences(expected, actual, path="$", result=None):
    if result is None:
        result = []
    if len(result) >= 100:
        return result
    number = lambda value: isinstance(value, (int, decimal.Decimal)) and not isinstance(value, bool)
    if number(expected) and number(actual):
        if isinstance(expected, int) and isinstance(actual, int):
            equal = expected == actual
        else:
            equal = abs(decimal.Decimal(expected) - decimal.Decimal(actual)) <= TOLERANCE
        if not equal:
            result.append(f"{path}: expected {expected}, actual {actual}")
    elif type(expected) is not type(actual):
        result.append(f"{path}: expected {type(expected).__name__}, actual {type(actual).__name__}")
    elif isinstance(expected, dict):
        for key in sorted(expected.keys() - actual.keys()):
            result.append(f"{path}[{key!r}]: missing field")
        for key in sorted(actual.keys() - expected.keys()):
            result.append(f"{path}[{key!r}]: unexpected field")
        for key in sorted(expected.keys() & actual.keys()):
            differences(expected[key], actual[key], f"{path}[{key!r}]", result)
            if len(result) >= 100:
                break
    elif isinstance(expected, list):
        if len(expected) != len(actual):
            result.append(f"{path}: expected {len(expected)} array entries, actual {len(actual)}")
        for index, (left, right) in enumerate(zip(expected, actual)):
            differences(left, right, f"{path}[{index}]", result)
            if len(result) >= 100:
                break
    elif expected != actual:
        result.append(f"{path}: expected {expected!r}, actual {actual!r}")
    return result


def source_inventory():
    files = [ROOT / "VERSION", ROOT / "Package.swift"]
    for directory in ("Sources/TowerCore", "Sources/TowerSession", "Sources/TowerPresentation", "Assets/Tokyo/Runtime"):
        files.extend(path for path in (ROOT / directory).rglob("*") if path.is_file())
    return {path.relative_to(ROOT).as_posix(): digest(path) for path in sorted(files) if path.is_file()}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    choice = parser.add_mutually_exclusive_group(required=True)
    choice.add_argument("--actual", type=pathlib.Path, help="Canonical JSON produced by either platform")
    choice.add_argument("--replay", type=pathlib.Path, help="Built TowerReplay executable to run")
    parser.add_argument("--expected", type=pathlib.Path, default=EXPECTED)
    parser.add_argument("--fixture", type=pathlib.Path, default=FIXTURE)
    parser.add_argument("--write-actual", type=pathlib.Path, help="Output path when using --replay")
    parser.add_argument("--report", type=pathlib.Path)
    args = parser.parse_args()
    report = {"status": "failed", "float_absolute_tolerance": str(TOLERANCE), "errors": []}
    try:
        actual = args.actual
        if args.replay:
            if args.write_actual is None:
                parser.error("--replay requires --write-actual")
            actual = args.write_actual.resolve()
            actual.parent.mkdir(parents=True, exist_ok=True)
            command = [str(args.replay.resolve()), "--self-check", "--fixture", str(args.fixture.resolve()), "--output", str(actual)]
            completed = subprocess.run(command, text=True, encoding="utf-8", errors="replace", capture_output=True, timeout=120)
            if completed.returncode:
                raise RuntimeError(f"TowerReplay exited {completed.returncode}: {completed.stderr.strip()}")
        report.update({"expected_sha256": digest(args.expected), "actual_sha256": digest(actual),
                       "fixture_sha256": digest(args.fixture), "source_sha256": source_inventory(),
                       "version": (ROOT / "VERSION").read_text(encoding="utf-8").strip()})
        report["errors"] = differences(load(args.expected), load(actual))
        report["status"] = "passed" if not report["errors"] else "failed"
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired, decimal.InvalidOperation) as error:
        report["errors"] = [str(error)]
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    if report["status"] == "passed":
        print(f"Replay parity passed against {args.expected.name}; every field checked, float absolute tolerance 1e-9.")
        return 0
    for error in report["errors"][:100]:
        print(error, file=sys.stderr)
    print("Replay parity FAILED.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
