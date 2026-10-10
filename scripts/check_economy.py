#!/usr/bin/env python3
"""Export and audit three controlled Stage 4 scenarios in actual NetLogo 6.4.x."""

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
    "mean-religion": (0, 1), "mean-dependency": (0, 1),
    "mean-tech-health": (0, 1), "mean-tech-demand": (0, 1),
    "mean-wealth": (0, 100), "technology-crisis-planets": (0, 30),
    "total-successful-trades": (0, math.inf),
    "foundation-treasury": (0, math.inf),
}
SCENARIOS = ("prosperity", "dependency-trap", "alternative-industry")


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
        if (run, step) in observed:
            raise ValueError("Duplicate run/step")
        if row["model-valid?"] != "true" or float(row["ticks"]) != step:
            raise ValueError("Invalid state or clock")
        if not re.fullmatch(r"6\.4\.\d+", row["netlogo-version"].strip('"')):
            raise ValueError("Wrong NetLogo version")
        snapshot = {}
        for metric, (lower, upper) in METRICS.items():
            value = float(row[metric])
            if not math.isfinite(value) or not lower <= value <= upper:
                raise ValueError(f"Invalid {metric}: {value}")
            snapshot[metric] = value
        observed[run, step] = snapshot
    if set(observed) != {(run, step) for run in (1, 2) for step in range(451)}:
        raise ValueError("Incomplete run/step coverage")
    if any(observed[1, step] != observed[2, step] for step in range(451)):
        raise ValueError("Seed 101 replay mismatch")
    return observed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("netlogo_home", type=Path)
    parser.add_argument("output_directory", type=Path, help="Fresh directory for measured CSV evidence")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = args.output_directory.resolve()
    output.mkdir(parents=True, exist_ok=False)
    launcher = args.netlogo_home.expanduser().resolve() / "NetLogo_Console"
    results = {}
    with tempfile.TemporaryDirectory(prefix="foundation-economy-") as directory:
        model = Path(directory) / "foundation.nlogo"
        model.write_text(test_model_source(root, 4))
        for scenario in SCENARIOS:
            xml = output / f"{scenario}.xml"
            metrics = "\n".join(f"    <metric>{name}</metric>" for name in METRICS)
            xml.write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE experiments SYSTEM "behaviorspace.dtd">
<experiments>
  <experiment name="{scenario}" repetitions="2" runMetricsEveryStep="true">
    <setup>setup-economic-scenario "{scenario}"</setup>
    <go>go-economic-scenario assert-valid-model-state</go>
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
                capture_output=True, text=True, timeout=120,
            )
            if result.returncode or "RUNTIME ERROR" in result.stderr + result.stdout:
                raise ValueError(result.stdout + result.stderr)
            results[scenario] = audit(table, scenario)
    prosperity, trap, alternative = (results[name][1, 450] for name in SCENARIOS)
    if not (prosperity["mean-wealth"] > 80 and prosperity["mean-tech-health"] > .5
            and prosperity["total-successful-trades"] > 0):
        raise ValueError("Supported prosperity fixture failed")
    if not (trap["mean-wealth"] < 80 and trap["mean-tech-health"] < .5
            and trap["total-successful-trades"] == 0):
        raise ValueError("Unsupported crisis fixture failed")
    if not (alternative["mean-dependency"] < trap["mean-dependency"]
            and alternative["mean-wealth"] > trap["mean-wealth"]
            and alternative["total-successful-trades"] == 0):
        raise ValueError("Domestic substitution fixture failed")
    with (output / "samples.csv").open("w", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(["scenario", "seed", "tick", *METRICS])
        for scenario in SCENARIOS:
            for step in (0, 50, 150, 300, 450):
                writer.writerow([scenario, 101, step, *results[scenario][1, step].values()])
    # Scientific provenance: source/fixture/XML/data hashes, no execution manifest.
    paths = [root / "model/foundation.nlogo", root / "tests/stage4_checks.nls",
             Path(__file__).resolve(), *sorted(output.glob("*.xml")), *sorted(output.glob("*.csv"))]
    (output / "SHA256SUMS").write_text("".join(
        f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path}\n" for path in paths
    ))
    print("PASS: 3 scenarios, 2 identical seed-101 replays each, 2706 finite valid rows at ticks 0–450")
    print(f"CSV time-series samples: {output / 'samples.csv'}")
    for scenario in SCENARIOS:
        row = results[scenario][1, 450]
        print(f"{scenario}: health={row['mean-tech-health']:.6f}, "
              f"dependency={row['mean-dependency']:.6f}, wealth={row['mean-wealth']:.6f}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, StopIteration, KeyError, subprocess.TimeoutExpired) as error:
        raise SystemExit(f"FAIL: {error}") from error
