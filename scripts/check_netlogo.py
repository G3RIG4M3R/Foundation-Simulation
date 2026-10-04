#!/usr/bin/env python3
"""Compile an empty .nlogo and audit real BehaviorSpace output; no dependencies."""

import argparse
import csv
import os
from pathlib import Path
import re
import subprocess
import tempfile


def validate_table(path):
    """Reject empty/partial output, wrong versions, and missing or duplicate steps."""
    with path.open(newline="", encoding="utf-8-sig") as stream:
        rows = list(csv.reader(stream))
    header_index = next(
        (i for i, row in enumerate(rows) if row and row[0] == "[run number]"),
        None,
    )
    if header_index is None:
        raise ValueError("BehaviorSpace data header missing")
    metadata = rows[:header_index]
    if ["Runtime probe"] not in metadata:
        raise ValueError("Unexpected experiment name in metadata")
    header = rows[header_index]
    required = {
        "[run number]", "[step]", "netlogo-version", "ticks",
        "world-width", "world-height", "count turtles",
    }
    if len(header) != len(required) or set(header) != required:
        raise ValueError(f"Unexpected data columns: {header}")
    data = [row for row in rows[header_index + 1:] if row]
    if len(data) != 8:
        raise ValueError(f"Expected eight data rows, got {len(data)}")
    observed = set()
    versions = set()
    for values in data:
        if len(values) != len(header):
            raise ValueError("Malformed data row")
        row = dict(zip(header, values))
        version = row["netlogo-version"].strip('"')
        if not re.fullmatch(r"6\.4\.\d+", version):
            raise ValueError(f"Requires NetLogo 6.4.x, got {version}")
        versions.add(version)
        run = int(row["[run number]"])
        step = int(row["[step]"])
        if float(row["ticks"]) != step:
            raise ValueError("Tick does not match the recorded step")
        if (float(row["world-width"]), float(row["world-height"])) != (33, 33):
            raise ValueError("Unexpected blank fixture dimensions")
        if float(row["count turtles"]) != 0:
            raise ValueError("Runtime probe must not create agents")
        if (run, step) in observed:
            raise ValueError("Duplicate run/step")
        observed.add((run, step))
    if observed != {(run, step) for run in (1, 2) for step in range(4)}:
        raise ValueError("Incomplete run/step coverage")
    if len(versions) != 1:
        raise ValueError("Inconsistent NetLogo versions")
    return versions.pop()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("netlogo_home", type=Path, help="NetLogo installation directory")
    args = parser.parse_args()
    launcher = args.netlogo_home.expanduser().resolve() / "NetLogo_Console"
    if not launcher.is_file() or not os.access(launcher, os.X_OK):
        parser.error(f"Executable native console not found: {launcher}")
    fixtures = Path(__file__).resolve().parents[1] / "tests" / "fixtures"
    try:
        with tempfile.TemporaryDirectory(prefix="netlogo-runtime-") as output:
            table = Path(output) / "runtime_probe.csv"
            command = [
                str(launcher), "--headless",
                "--model", str(fixtures / "runtime_probe.nlogo"),
                "--setup-file", str(fixtures / "runtime_probe.xml"),
                "--experiment", "Runtime probe", "--threads", "1",
                "--table", str(table),
            ]
            result = subprocess.run(command, capture_output=True, text=True, timeout=90)
            if result.returncode:
                raise ValueError(
                    f"NetLogo exit {result.returncode}: {result.stdout}{result.stderr}"
                )
            version = validate_table(table)
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        raise SystemExit(f"FAIL: {error}") from error
    print(f"PASS: NetLogo {version}; .nlogo compiled; 2 runs; 8 rows; ticks 0–3; 0 agents")
    print("Foundation model and GUI behavior have not been tested.")


if __name__ == "__main__":
    main()
