#!/usr/bin/env python3
"""Run cumulative NetLogo acceptance checks in an isolated temporary model."""

import argparse
import csv
from pathlib import Path
import re
import subprocess
import tempfile


def test_model_source(root, stage):
    """Keep test procedures out of the self-contained production model."""
    sections = (root / "model/foundation.nlogo").read_text().split("@#$#@#$#@")
    flags = " ".join(f"stage{number}-checks-passed?" for number in range(1, stage + 1))
    sections[0] = sections[0].replace("globals [", f"globals [ {flags}", 1)
    for number in range(1, stage + 1):
        sections[0] += "\n" + (root / f"tests/stage{number}_checks.nls").read_text()
    return "@#$#@#$#@".join(sections)


def check_model(netlogo_home, stage, only=False):
    root = Path(__file__).resolve().parents[1]
    launcher = netlogo_home.expanduser().resolve() / "NetLogo_Console"
    numbers = (stage,) if only else range(1, stage + 1)
    commands = " ".join(f"check-stage{number}" for number in numbers)
    flag = f"stage{stage}-checks-passed?"
    with tempfile.TemporaryDirectory(prefix="foundation-checks-") as directory:
        work = Path(directory)
        model = work / "foundation.nlogo"
        model.write_text(test_model_source(root, stage))
        experiment = work / "checks.xml"
        experiment.write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE experiments SYSTEM "behaviorspace.dtd">
<experiments>
  <experiment name="Foundation acceptance" repetitions="1" runMetricsEveryStep="false">
    <setup>{commands}</setup>
    <go>stop</go>
    <timeLimit steps="1"/>
    <metric>{flag}</metric>
    <metric>model-valid?</metric>
    <metric>ticks</metric>
    <metric>netlogo-version</metric>
  </experiment>
</experiments>
''')
        table = work / "checks.csv"
        result = subprocess.run(
            [str(launcher), "--headless", "--model", str(model),
             "--setup-file", str(experiment), "--experiment", "Foundation acceptance",
             "--threads", "1", "--table", str(table)],
            capture_output=True, text=True, timeout=600,
        )
        if result.returncode or "RUNTIME ERROR" in result.stdout + result.stderr:
            raise ValueError(result.stdout + result.stderr)
        with table.open(newline="", encoding="utf-8-sig") as stream:
            rows = list(csv.reader(stream))
        header = next(i for i, row in enumerate(rows) if row and row[0] == "[run number]")
        if ["Foundation acceptance"] not in rows[:header]:
            raise ValueError("Unexpected experiment metadata")
        data = [row for row in rows[header + 1:] if row]
        if len(data) != 1 or len(data[0]) != len(rows[header]):
            raise ValueError("Expected one complete acceptance result row")
        row = dict(zip(rows[header], data[0]))
        if (row[flag], row["model-valid?"], row["ticks"]) != ("true", "true", "450"):
            raise ValueError(f"Checks incomplete: {row}\n{result.stdout}{result.stderr}")
        if not re.fullmatch(r"6\.4\.\d+", row["netlogo-version"].strip('"')):
            raise ValueError("Checks must run in NetLogo 6.4.x")
    if result.stdout.strip():
        print(result.stdout.strip())
    print(f"PASS: headless checks {list(numbers)}; final state valid at tick 450")
    print("GUI checks are separate; headless results do not establish GUI behavior.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("netlogo_home", type=Path)
    parser.add_argument("--stage", type=int, choices=(1, 2, 3, 4, 5, 6), default=6)
    parser.add_argument("--only", action="store_true", help="Run only the selected stage; compile all fixture dependencies")
    args = parser.parse_args()
    try:
        check_model(args.netlogo_home, args.stage, args.only)
    except (OSError, ValueError, StopIteration, KeyError, subprocess.TimeoutExpired) as error:
        raise SystemExit(f"FAIL: {error}") from error
