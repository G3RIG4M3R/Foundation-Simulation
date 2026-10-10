#!/usr/bin/env python3
"""Run galaxy acceptance checks in NetLogo 6.4.x without modifying the model."""

import argparse
import csv
from pathlib import Path
import subprocess
import tempfile


def run_checks(netlogo_home):
    root = Path(__file__).resolve().parents[1]
    launcher = netlogo_home.expanduser().resolve() / "NetLogo_Console"
    source = (root / "model/foundation.nlogo").read_text()
    sections = source.split("@#$#@#$#@")
    sections[0] = sections[0].replace(
        "globals [", "globals [ stage1-checks-passed?", 1
    ) + (root / "tests/stage1_checks.nls").read_text()
    with tempfile.TemporaryDirectory(prefix="foundation-stage1-") as directory:
        work = Path(directory)
        model = work / "foundation.nlogo"
        model.write_text("@#$#@#$#@".join(sections))
        experiment = work / "checks.xml"
        experiment.write_text('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE experiments SYSTEM "behaviorspace.dtd">
<experiments>
  <experiment name="Galaxy acceptance" repetitions="1" runMetricsEveryStep="false">
    <setup>check-stage1</setup>
    <go>stop</go>
    <timeLimit steps="1"/>
    <metric>stage1-checks-passed?</metric>
    <metric>model-valid?</metric>
    <metric>ticks</metric>
    <metric>netlogo-version</metric>
  </experiment>
</experiments>
''')
        table = work / "checks.csv"
        result = subprocess.run(
            [str(launcher), "--headless", "--model", str(model),
             "--setup-file", str(experiment), "--experiment", "Galaxy acceptance",
             "--threads", "1", "--table", str(table)],
            capture_output=True, text=True, timeout=120,
        )
        if result.returncode:
            raise ValueError(result.stdout + result.stderr)
        with table.open(newline="", encoding="utf-8-sig") as stream:
            rows = list(csv.reader(stream))
        header = next(i for i, row in enumerate(rows) if row and row[0] == "[run number]")
        data = [row for row in rows[header + 1:] if row]
        if len(data) != 1 or len(data[0]) != len(rows[header]):
            raise ValueError("Expected one complete acceptance result row")
        row = dict(zip(rows[header], data[0]))
        if (row["stage1-checks-passed?"], row["model-valid?"], row["ticks"]) != ("true", "true", "450"):
            raise ValueError(f"Incomplete or failed checks: {row}\n{result.stdout}{result.stderr}")
        if not row["netlogo-version"].strip('"').startswith("6.4."):
            raise ValueError("Checks must run in NetLogo 6.4.x")
    print("PASS: S1-B through S1-H (headless); 25 seeded population cases through 450 ticks")
    print("PASS: initialization bounds, reset, seed replay, rendering purity, placement errors and validator rejection")
    print("S1-A GUI buttons/open and S1-B Settings require separate GUI verification.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("netlogo_home", type=Path)
    args = parser.parse_args()
    try:
        run_checks(args.netlogo_home)
    except (OSError, ValueError, StopIteration, KeyError, subprocess.TimeoutExpired) as error:
        raise SystemExit(f"FAIL: {error}") from error
