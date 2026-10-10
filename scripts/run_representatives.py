#!/usr/bin/env python3
"""Replay the objectively selected sweep runs with per-tick metrics."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

METRICS = ["control-fraction", "cumulative-trade-profit", "controlled-kingdoms",
           "mean-religion", "mean-dependency", "ticks", "model-valid?",
           "netlogo-version"]
FIXED = ("set initial-missionaries 12 set initial-traders 12 "
         "set trade-attractiveness 0.6 set tech-decay-rate 0.015 "
         "set religion-trade-weight 0.55 set independence-effort 0.15 "
         "set view-mode \"kingdom\"")


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def build_xml(selection, duration):
    root = ET.Element("experiments")
    for row in selection:
        name = "Representative " + row["regime"]
        experiment = ET.SubElement(root, "experiment", name=name,
                                   repetitions="1", runMetricsEveryStep="true")
        duration_command = "" if duration == 450 else f"set tick-limit {duration} "
        setup = (f"set missionary-effectiveness {row['missionary_effectiveness']} "
                 f"set royal-intolerance {row['royal_intolerance']} {FIXED} "
                 f"{duration_command}random-seed {row['seed']} setup")
        ET.SubElement(experiment, "setup").text = setup
        ET.SubElement(experiment, "go").text = "go"
        ET.SubElement(experiment, "timeLimit", steps=str(duration))
        if duration != 450:
            ET.SubElement(experiment, "exitCondition").text = "ticks >= active-tick-limit"
        for metric in METRICS:
            ET.SubElement(experiment, "metric").text = metric
    ET.indent(root, space="  ")
    return ('<?xml version="1.0" encoding="UTF-8"?>\n'
            '<!DOCTYPE experiments SYSTEM "behaviorspace.dtd">\n' +
            ET.tostring(root, encoding="unicode") + "\n")


def read_export(path, experiment, duration):
    with path.open(newline="", encoding="utf-8-sig") as stream:
        rows = list(csv.reader(stream))
    index = next(i for i, row in enumerate(rows) if row and row[0] == "[run number]")
    if [experiment] not in rows[:index]:
        raise ValueError("Wrong representative experiment metadata")
    header = rows[index]
    data = [dict(zip(header, row)) for row in rows[index + 1:] if row]
    if (len(data) != duration + 1 or
            {int(row["[step]"]) for row in data} != set(range(duration + 1))):
        raise ValueError("Incomplete representative time series")
    for row in data:
        if row["model-valid?"] != "true" or float(row["ticks"]) != int(row["[step]"]):
            raise ValueError("Invalid representative state or clock")
        if not re.fullmatch(r"6\.4\.\d+", row["netlogo-version"].strip('"')):
            raise ValueError("Representative run did not use NetLogo 6.4.x")
    return sorted(data, key=lambda row: int(row["[step]"]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("netlogo_home", type=Path)
    parser.add_argument("--selection", type=Path,
                        default=Path("results/processed/representative_selection.csv"))
    parser.add_argument("--xml", type=Path,
                        default=Path("experiments/representative_timeseries.xml"))
    parser.add_argument("--exports", type=Path,
                        default=Path("results/raw/representative_exports"))
    parser.add_argument("--output", type=Path,
                        default=Path("results/raw/representative_timeseries.csv"))
    parser.add_argument("--duration", type=int, default=450)
    args = parser.parse_args()
    with args.selection.open(newline="", encoding="utf-8") as stream:
        selection = list(csv.DictReader(stream))
    if [row["regime"] for row in selection] != ["failed", "intermediate", "highest observed"]:
        raise ValueError("Unexpected representative selection")
    if not 100 <= args.duration <= 3000 or args.duration % 50:
        raise ValueError("Duration must be 100–3000 in steps of 50")
    xml = build_xml(selection, args.duration)
    if args.xml.exists():
        if args.xml.read_text(encoding="utf-8") != xml:
            raise ValueError("Existing representative XML differs from selection")
    else:
        args.xml.parent.mkdir(parents=True, exist_ok=True)
        args.xml.write_text(xml, encoding="utf-8")
    args.exports.mkdir(parents=True, exist_ok=False)
    if args.output.exists():
        raise ValueError(f"Refusing to overwrite evidence: {args.output}")
    model = Path(__file__).resolve().parents[1] / "model/foundation.nlogo"
    launcher = args.netlogo_home.resolve() / "NetLogo_Console"
    combined = []
    commands = []
    for selected in selection:
        experiment = "Representative " + selected["regime"]
        export = args.exports / (selected["regime"].replace(" ", "_") + ".csv")
        command = [str(launcher), "--headless", "--model", str(model),
                   "--setup-file", str(args.xml.resolve()), "--experiment", experiment,
                   "--threads", "1", "--table", str(export.resolve())]
        commands.append(command)
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode or "RUNTIME ERROR" in result.stdout + result.stderr:
            raise ValueError(result.stdout + result.stderr)
        for row in read_export(export, experiment, args.duration):
            combined.append({
                "regime": selected["regime"],
                "missionary_effectiveness": selected["missionary_effectiveness"],
                "royal_intolerance": selected["royal_intolerance"],
                "seed": selected["seed"], "tick": row["ticks"],
                "control_fraction": row["control-fraction"],
                "cumulative_trade_profit": row["cumulative-trade-profit"],
                "controlled_kingdoms": row["controlled-kingdoms"],
                "mean_religion": row["mean-religion"],
                "mean_dependency": row["mean-dependency"],
            })
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(combined[0]))
        writer.writeheader()
        writer.writerows(combined)
    provenance = {
        "commands": commands, "model_sha256": digest(model),
        "experiment_sha256": digest(args.xml),
        "selection_sha256": digest(args.selection),
        "duration_ticks": args.duration,
        "source_export_sha256": {path.name: digest(path)
                                  for path in sorted(args.exports.glob("*.csv"))},
        "combined_csv_sha256": digest(args.output),
        "selection_rule": ("minimum cell mean; cell nearest midpoint of minimum and maximum; "
                           "maximum cell mean; within each cell terminal control nearest the cell "
                           "mean, ties by smallest production run number"),
    }
    args.output.with_suffix(".provenance.json").write_text(
        json.dumps(provenance, indent=2) + "\n", encoding="utf-8")
    print(f"PASS: 3 measured representative runs, {len(combined)} rows at "
          f"{args.duration} ticks: {args.output}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, StopIteration, ET.ParseError) as error:
        raise SystemExit(f"FAIL: {error}") from error
