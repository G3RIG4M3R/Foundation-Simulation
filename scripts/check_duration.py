#!/usr/bin/env python3
"""Validate configurable horizons, plots, and seeded prefix reproducibility."""
import argparse
import csv
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET

HORIZONS = (100, 450, 1000, 2000)
TRACE_METRICS = ("control-fraction", "cumulative-trade-profit", "controlled-planets",
                 "controlled-kingdoms", "mean-religion", "mean-dependency",
                 "total-successful-trades", "ticks", "active-tick-limit",
                 "model-valid?")
DIAGNOSTICS = ("count planets", "count missionaries", "count traders",
               "valid-tick-limit? tick-limit", "valid-tick-limit? active-tick-limit",
               "empty? filter [world -> not [planet-state-valid?] of world] sort planets",
               "empty? filter [visitor -> not [missionary-state-valid?] of visitor] sort missionaries",
               "empty? filter [visitor -> not [trader-state-valid?] of visitor] sort traders",
               "(list min-pxcor max-pxcor min-pycor max-pycor) = [-32 31 -32 31]",
               "is-planet? terminus-planet", "[foundation?] of terminus-planet",
               "[planet-id] of terminus-planet = 0", "[kingdom-id] of terminus-planet = 0",
               "[distance patch 31 0] of patch -32 0 = 1",
               "[distance patch 0 31] of patch 0 -32 = 1",
               "count planets with [kingdom-id = 5] = 10",
               "not any? planets with [capital? and not member? kingdom-id [1 2 3 4]]",
               "sort map [world -> [planet-id] of world] sort planets = range 31",
               "empty? filter [group -> count planets with [kingdom-id = group] != 5 or count planets with [kingdom-id = group and capital?] != 1] [1 2 3 4]",
               "empty? filter [world -> any? planets with [self != world and distance world < 3]] sort planets",
               "not any? trade-routes with [not in-range? route-strength 0 1 or not natural-number? route-age]",
               "in-range? last-recruitment-tick -1 ticks",
               "in-range? foundation-treasury 0 1.0E+300",
               "in-range? cumulative-trade-profit (-1.0E+300) 1.0E+300",
               "in-range? trade-income-this-tick 0 1.0E+300",
               "empty? filter [value -> not natural-number? value] (list total-executed-missionaries total-executed-traders total-rejected-missions total-successful-missions total-rejected-trades total-successful-trades kingdom-policy-timer total-recruited-missionaries total-recruited-traders)")
FIXED = ("set initial-missionaries 12 set initial-traders 12 "
         "set missionary-effectiveness 0.25 set trade-attractiveness 0.6 "
         "set royal-intolerance 0.5 set tech-decay-rate 0.015 "
         "set religion-trade-weight 0.55 set independence-effort 0.15 "
         "set view-mode \"kingdom\"")
PLOTS = ("Control over time", "Religion and dependency",
         "Religion distribution", "Trade economy")


def experiment(name, setup, horizon, go="go", post=None, parameter_horizon=False,
               exit_condition=True):
    node = ET.Element("experiment", name=name, repetitions="1",
                      runMetricsEveryStep="true")
    ET.SubElement(node, "setup").text = setup
    ET.SubElement(node, "go").text = go
    if post:
        ET.SubElement(node, "postRun").text = post
    ET.SubElement(node, "timeLimit", steps=str(horizon))
    if exit_condition:
        ET.SubElement(node, "exitCondition").text = "ticks >= active-tick-limit"
    for metric in TRACE_METRICS:
        ET.SubElement(node, "metric").text = metric
    for metric in DIAGNOSTICS:
        ET.SubElement(node, "metric").text = metric
    if parameter_horizon:
        values = ET.SubElement(node, "enumeratedValueSet", variable="tick-limit")
        ET.SubElement(values, "value", value=str(horizon))
    return node


def read_table(path, name):
    with path.open(newline="", encoding="utf-8-sig") as stream:
        rows = list(csv.reader(stream))
    header_at = next(i for i, row in enumerate(rows) if row and row[0] == "[run number]")
    if [name] not in rows[:header_at]:
        raise ValueError(f"Wrong experiment metadata for {name}")
    header = rows[header_at]
    return [dict(zip(header, row)) for row in rows[header_at + 1:] if row]


def read_plot(path, title):
    with path.open(newline="", encoding="utf-8-sig") as stream:
        rows = list(csv.reader(stream))
    if [f'"{title}"'] not in rows:
        raise ValueError(f"Wrong plot export: {title}")
    meta = next(i for i, row in enumerate(rows) if row and row[0] == "x min")
    bounds = {key: float(value) for key, value in zip(rows[meta][:4], rows[meta + 1][:4])}
    start = next(i for i, row in enumerate(rows)
                 if row and row[:4] == ["x", "y", "color", "pen down?"])
    names = [value.strip('"') for value in rows[start - 1][::4]]
    points = {name: [] for name in names}
    for row in rows[start + 1:]:
        if not row:
            continue
        for index, name in enumerate(names):
            x, y = row[index * 4:index * 4 + 2]
            if x or y:
                points[name].append((float(x), float(y)))
    return bounds, points


def check_widget_and_experiments(root):
    sections = (root / "model/foundation.nlogo").read_text().split("@#$#@#$#@")
    blocks = [block.splitlines() for block in sections[1].strip().split("\n\n")]
    slider = next(row for row in blocks if row[0] == "SLIDER" and row[6] == "tick-limit")
    if tuple(map(float, slider[7:11])) != (0, 3000, 0, 50):
        raise ValueError("Incorrect Simulation Duration slider")
    standalone = ET.parse(root / "experiments/foundation_duration_sweeps.xml").getroot()
    embedded = ET.fromstring(sections[7])
    expected = {"Foundation Baseline Sweep (450 ticks)": 450,
                "Foundation Extended Sweep (1000 ticks)": 1000}
    for tree in (standalone, embedded):
        found = {}
        for item in tree.findall("experiment"):
            values = item.find("enumeratedValueSet[@variable='tick-limit']")
            found[item.get("name")] = int(values.find("value").get("value"))
            if (item.get("repetitions") != "20"
                    or int(item.find("timeLimit").get("steps")) != found[item.get("name")]
                    or item.findtext("exitCondition") != "ticks >= active-tick-limit"):
                raise ValueError("Duration sweep repetitions/time limit changed")
        if found != expected:
            raise ValueError("Missing or incorrect duration sweeps")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("netlogo_home", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    check_widget_and_experiments(root)
    launcher = args.netlogo_home.resolve() / "NetLogo_Console"
    with tempfile.TemporaryDirectory(prefix="foundation-duration-") as directory:
        work = Path(directory)
        experiments = ET.Element("experiments")
        for horizon in HORIZONS:
            name = f"Duration {horizon}"
            setup = f"{FIXED} random-seed 123 setup"
            post = " ".join(
                f'export-plot "{title}" "{work / f"plot-{horizon}-{index}.csv"}"'
                for index, title in enumerate(PLOTS))
            experiments.append(experiment(name, setup, horizon, post=post,
                                          parameter_horizon=True))
        experiments.append(experiment(
            "Unlimited interactive prefix", f"{FIXED} set tick-limit 0 random-seed 123 setup",
            250, exit_condition=False))
        experiments.append(experiment(
            "Mid-run slider isolation",
            f"{FIXED} set tick-limit 100 random-seed 123 setup set tick-limit 2000", 100))
        experiments.append(experiment(
            "Reinitialize duration",
            f"{FIXED} set tick-limit 100 random-seed 123 setup repeat 100 [go] "
            "set tick-limit 450 random-seed 123 setup", 450))
        experiments.append(experiment(
            "Go once at limit",
            f"{FIXED} set tick-limit 100 random-seed 123 setup repeat 100 [go-once]",
            100, go="go-once"))
        ET.indent(experiments, space="  ")
        xml = work / "duration.xml"
        xml.write_text('<?xml version="1.0" encoding="UTF-8"?>\n'
                       '<!DOCTYPE experiments SYSTEM "behaviorspace.dtd">\n' +
                       ET.tostring(experiments, encoding="unicode") + "\n")
        traces = {}
        for node in experiments.findall("experiment"):
            name = node.get("name")
            table = work / f"{name.replace(' ', '-')}.csv"
            command = [str(launcher), "--headless", "--model",
                       str(root / "model/foundation.nlogo"), "--setup-file", str(xml),
                       "--experiment", name, "--threads", "1", "--table", str(table)]
            if node.find("postRun") is not None:
                command.append("--update-plots")
            result = subprocess.run(command, capture_output=True, text=True, timeout=300)
            if result.returncode or "RUNTIME ERROR" in result.stdout + result.stderr:
                raise ValueError(result.stdout + result.stderr)
            rows = read_table(table, name)
            if not rows or any(row["model-valid?"] != "true" for row in rows):
                bad = next((row for row in rows if row["model-valid?"] != "true"), None)
                raise ValueError(f"Invalid or empty run: {name}: {bad or 'no rows'}")
            traces[name] = rows
            print(f"PASS runtime: {name}", flush=True)
        for horizon in HORIZONS:
            rows = traces[f"Duration {horizon}"]
            if [int(float(row["ticks"])) for row in rows] != list(range(horizon + 1)):
                raise ValueError(f"Incorrect steps for duration {horizon}")
            if int(float(rows[-1]["active-tick-limit"])) != horizon:
                raise ValueError(f"Wrong captured duration {horizon}")
            for index, title in enumerate(PLOTS):
                bounds, pens = read_plot(work / f"plot-{horizon}-{index}.csv", title)
                expected_x = 1 if title == "Religion distribution" else horizon
                if bounds["x min"] != 0 or bounds["x max"] != expected_x:
                    raise ValueError(f"Wrong plot range: {horizon} {title}")
                if title != "Religion distribution" and any(points[-1][0] != horizon
                                                               for points in pens.values()):
                    raise ValueError(f"Plot stopped early: {horizon} {title}")
        unlimited = traces["Unlimited interactive prefix"]
        if ([int(float(row["ticks"])) for row in unlimited] != list(range(251))
                or any(float(row["active-tick-limit"]) != 0 for row in unlimited)):
            raise ValueError("Unlimited run did not continue under the external test horizon")
        if int(float(traces["Mid-run slider isolation"][-1]["ticks"])) != 100:
            raise ValueError("Mid-run slider change altered active horizon")
        if int(float(traces["Reinitialize duration"][-1]["ticks"])) != 450:
            raise ValueError("Setup did not apply the new duration")
        if int(float(traces["Go once at limit"][-1]["ticks"])) != 100:
            raise ValueError("go-once advanced beyond the limit")
        short = traces["Duration 450"]
        long = traces["Duration 1000"][:451]
        comparable = tuple(metric for metric in TRACE_METRICS
                           if metric != "active-tick-limit")
        if any(tuple(a[m] for m in comparable) != tuple(b[m] for m in comparable)
               for a, b in zip(short, long)):
            raise ValueError("450/1000 seeded trajectories differ before tick 450")
    print("PASS: exact stops at 100/450/1000/2000; go-once guard and setup capture")
    print("PASS: interactive default 0 remains unlimited through a 250-tick external test horizon")
    print("PASS: time-series plot ranges/endpoints; histogram unchanged; data continues past 450")
    print("PASS: identical-seed 450/1000 trajectories match through tick 450")
    print("PASS: embedded and standalone paired 20-repetition duration sweeps")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, StopIteration, KeyError, ET.ParseError,
            subprocess.TimeoutExpired) as error:
        raise SystemExit(f"FAIL: {error}") from error
