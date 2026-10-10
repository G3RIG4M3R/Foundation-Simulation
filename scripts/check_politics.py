#!/usr/bin/env python3
"""Export and audit Stage 5 scenarios, replay, variability and diagnostics."""

import argparse
import csv
import hashlib
import math
from pathlib import Path
import re
import subprocess
import tempfile

from check_model import test_model_source

METRICS = {
    "controlled-planets": (0, 30), "control-fraction": (0, 1),
    "controlled-kingdoms": (0, 4), "mean-religion": (0, 1),
    "mean-dependency": (0, 1), "mean-tech-health": (0, 1),
    "mean-wealth": (0, 100), "foundation-treasury": (0, math.inf),
    "cumulative-trade-profit": (-math.inf, math.inf),
    "total-executed-missionaries": (0, math.inf),
    "total-executed-traders": (0, math.inf), "recruitment-costs": (0, math.inf),
    "total-successful-trades": (0, math.inf),
    'count planets with [policy = "restrict"]': (0, 30),
    'count planets with [embargoed?]': (0, 30),
}
SCENARIOS = ("default", "failed-expansion", "stable-control", "political-resistance",
             "all-minimum", "all-maximum")


def audit(path, scenario):
    with path.open(newline="", encoding="utf-8-sig") as stream:
        rows = list(csv.reader(stream))
    index = next(i for i, row in enumerate(rows) if row and row[0] == "[run number]")
    if [scenario] not in rows[:index]:
        raise ValueError("Wrong experiment metadata")
    header = rows[index]
    expected = {"[run number]", "[step]", "ticks", "model-valid?", "netlogo-version", *METRICS}
    if len(header) != len(expected) or set(header) != expected:
        raise ValueError(f"Unexpected columns: {header}")
    observed = {}
    for values in rows[index + 1:]:
        if not values:
            continue
        if len(values) != len(header):
            raise ValueError("Partial row")
        row = dict(zip(header, values))
        run, step = int(row["[run number]"]), int(row["[step]"])
        if (run, step) in observed or float(row["ticks"]) != step or row["model-valid?"] != "true":
            raise ValueError("Duplicate row, bad clock or invalid state")
        if not re.fullmatch(r"6\.4\.\d+", row["netlogo-version"].strip('"')):
            raise ValueError("Wrong runtime")
        snapshot = {}
        for metric, (lower, upper) in METRICS.items():
            value = float(row[metric])
            if not math.isfinite(value) or not lower <= value <= upper:
                raise ValueError(f"Invalid {metric}: {value}")
            snapshot[metric] = value
        if abs(snapshot["foundation-treasury"] - 200 - snapshot["cumulative-trade-profit"]) > 1e-8:
            raise ValueError("Treasury/profit mismatch")
        if abs(snapshot["control-fraction"] - snapshot["controlled-planets"] / 30) > 1e-12:
            raise ValueError("Control fraction mismatch")
        observed[run, step] = snapshot
    if set(observed) != {(run, step) for run in (1, 2, 3) for step in range(451)}:
        raise ValueError("Incomplete run/step coverage")
    if any(observed[1, step] != observed[2, step] for step in range(451)):
        raise ValueError("Seed 123 replay mismatch")
    if all(observed[1, step] == observed[3, step] for step in range(451)):
        raise ValueError("Seed 124 produced no variability")
    for run in (1, 2, 3):
        for metric in ("total-executed-missionaries", "total-executed-traders",
                       "total-successful-trades", "recruitment-costs"):
            if any(observed[run, step][metric] < observed[run, step - 1][metric] for step in range(1, 451)):
                raise ValueError(f"Cumulative metric decreased: {metric}")
    if scenario == "failed-expansion" and any(row["controlled-planets"] for row in observed.values()):
        raise ValueError("Failed expansion fixture gained control")
    if scenario == "stable-control" and any(observed[run, 450]["controlled-planets"] == 0 for run in (1, 2, 3)):
        raise ValueError("Favorable fixture did not sustain control")
    if scenario == "political-resistance" and not any(row['count planets with [embargoed?]'] for row in observed.values()):
        raise ValueError("No endogenous embargo in resistance fixture")
    return observed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("netlogo_home", type=Path)
    parser.add_argument("output_directory", type=Path, help="Fresh directory for measured evidence")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = args.output_directory.resolve()
    output.mkdir(parents=True, exist_ok=False)
    launcher = args.netlogo_home.expanduser().resolve() / "NetLogo_Console"
    results = {}
    with tempfile.TemporaryDirectory(prefix="foundation-politics-") as directory:
        model = Path(directory) / "foundation.nlogo"
        model.write_text(test_model_source(root, 5))
        for scenario in SCENARIOS:
            xml = output / f"{scenario}.xml"
            metrics = "\n".join(f"    <metric>{name}</metric>" for name in METRICS)
            xml.write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE experiments SYSTEM "behaviorspace.dtd">
<experiments>
  <experiment name="{scenario}" repetitions="3" runMetricsEveryStep="true">
    <setup>setup-political-scenario "{scenario}" (ifelse-value (behaviorspace-run-number = 3) [124] [123])</setup>
    <go>go-political-check</go>
    <timeLimit steps="450"/>
    <metric>ticks</metric>
    <metric>model-valid?</metric>
    <metric>netlogo-version</metric>
{metrics}
  </experiment>
</experiments>
''')
            table = output / f"{scenario}.csv"
            result = subprocess.run(
                [str(launcher), "--headless", "--model", str(model),
                 "--setup-file", str(xml), "--experiment", scenario,
                 "--threads", "1", "--table", str(table)],
                capture_output=True, text=True, timeout=180,
            )
            if result.returncode or "RUNTIME ERROR" in result.stdout + result.stderr:
                raise ValueError(result.stdout + result.stderr)
            results[scenario] = audit(table, scenario)
            end = results[scenario][1, 450]
            print(f"PASS {scenario}: seed 123 replay, seed 124 variation; "
                  f"final control={end['controlled-planets']:.0f}, "
                  f"kingdoms={end['controlled-kingdoms']:.0f}, "
                  f"treasury={end['foundation-treasury']:.6f}", flush=True)
    with (output / "samples.csv").open("w", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(["scenario", "seed", "tick", *METRICS])
        for scenario in SCENARIOS:
            for run, seed in ((1, 123), (3, 124)):
                for step in (0, 50, 150, 300, 450):
                    writer.writerow([scenario, seed, step, *results[scenario][run, step].values()])
    paths = [root / "model/foundation.nlogo", Path(__file__).resolve(),
             root / "scripts/check_model.py", *sorted((root / "tests").glob("stage*_checks.nls")),
             *sorted(output.glob("*.xml")), *sorted(output.glob("*.csv"))]
    (output / "SHA256SUMS").write_text("".join(
        f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path}\n" for path in paths
    ))
    print(f"PASS: 6 scenarios / 18 full runs / 8118 finite valid rows; samples: {output / 'samples.csv'}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, StopIteration, KeyError, subprocess.TimeoutExpired) as error:
        raise SystemExit(f"FAIL: {error}") from error
