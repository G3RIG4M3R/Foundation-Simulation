#!/usr/bin/env python3
"""Audit and summarize the staged tipping-point investigation."""
import csv
from collections import defaultdict
import math
from pathlib import Path
import statistics

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "results/tipping_point_investigation"
RAW = BASE / "raw"
PROCESSED = BASE / "processed"
FIGURES = BASE / "figures"
T19 = 2.093024054408263


def table(path):
    with path.open(newline="", encoding="utf-8-sig") as stream:
        rows = list(csv.reader(stream))
    starts = [i for i, row in enumerate(rows) if row and row[0] == "[run number]"]
    if len(starts) != 1:
        raise ValueError(f"Malformed BehaviorSpace table: {path}")
    header = rows[starts[0]]
    return [dict(zip(header, row)) for row in rows[starts[0] + 1:] if row]


def write(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def wilson(successes, n, z=1.959963984540054):
    p = successes / n
    denominator = 1 + z * z / n
    center = (p + z * z / (2 * n)) / denominator
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / denominator
    return center - half, center + half


def audit(rows, expected, horizon):
    if len(rows) != expected or any(row["model-valid?"] != "true" for row in rows):
        raise ValueError("Incomplete or invalid experimental evidence")
    if {int(float(row["ticks"])) for row in rows} != {horizon}:
        raise ValueError("Wrong terminal horizon")


def duration_summary():
    output = []
    for horizon in (450, 1000, 1500, 2000, 3000):
        rows = table(RAW / f"duration_{horizon}.csv")
        audit(rows, 5, horizon)
        values = [float(row["control-fraction"]) for row in rows]
        output.append({
            "duration_ticks": horizon, "n": len(rows),
            "control_mean": statistics.fmean(values),
            "control_sd": statistics.stdev(values),
            "religion_mean": statistics.fmean(float(r["mean-religion"]) for r in rows),
            "dependency_mean": statistics.fmean(float(r["mean-dependency"]) for r in rows),
            "widespread_probability": sum(v >= .5 for v in values) / len(values),
            "kingdom_probability": sum(float(r["controlled-kingdoms"]) >= 1 for r in rows) / len(rows),
        })
    return output


def confirmatory_summary():
    rows = table(RAW / "confirmatory.csv")
    audit(rows, 300, 1000)
    seeds = [int(float(row["500000 + behaviorspace-run-number"])) for row in rows]
    if len(set(seeds)) != 300 or (min(seeds), max(seeds)) != (500001, 500300):
        raise ValueError("Confirmatory seeds are not unique and complete")
    groups = defaultdict(list)
    for row in rows:
        groups[(int(float(row["initial-traders"])),
                float(row["trade-attractiveness"]))].append(row)
    if len(groups) != 15 or any(len(samples) != 20 for samples in groups.values()):
        raise ValueError("Confirmatory grid is incomplete")
    output = []
    for (traders, attractiveness), samples in sorted(groups.items()):
        control = [float(r["control-fraction"]) for r in samples]
        mean = statistics.fmean(control)
        sd = statistics.stdev(control)
        half = T19 * sd / math.sqrt(20)
        widespread = sum(value >= .5 for value in control)
        low, high = wilson(widespread, 20)
        kingdoms = sum(float(r["controlled-kingdoms"]) >= 1 for r in samples)
        kingdom_low, kingdom_high = wilson(kingdoms, 20)
        output.append({
            "initial_traders": traders, "trade_attractiveness": attractiveness, "n": 20,
            "control_mean": mean, "control_sd": sd,
            "control_ci_low": mean - half, "control_ci_high": mean + half,
            "widespread_count": widespread, "widespread_probability": widespread / 20,
            "widespread_wilson_low": low, "widespread_wilson_high": high,
            "kingdom_count": kingdoms, "kingdom_probability": kingdoms / 20,
            "kingdom_wilson_low": kingdom_low, "kingdom_wilson_high": kingdom_high,
            "religion_mean": statistics.fmean(float(r["mean-religion"]) for r in samples),
            "dependency_mean": statistics.fmean(float(r["mean-dependency"]) for r in samples),
            "profit_mean": statistics.fmean(float(r["cumulative-trade-profit"]) for r in samples),
            "successful_trades_mean": statistics.fmean(float(r["total-successful-trades"]) for r in samples),
        })
    return rows, output


def exploratory_summaries():
    screening = table(RAW / "mechanism_screening_audited.csv")
    audit(screening, 192, 1000)
    marginal = []
    factors = ("initial-missionaries", "initial-traders", "trade-attractiveness",
               "tech-decay-rate", "religion-trade-weight", "independence-effort")
    for factor in factors:
        for value in sorted({float(row[factor]) for row in screening}):
            samples = [row for row in screening if float(row[factor]) == value]
            control = [float(row["control-fraction"]) for row in samples]
            marginal.append({"factor": factor, "value": value, "n": len(samples),
                             "control_mean": statistics.fmean(control),
                             "widespread_probability": sum(v >= .5 for v in control) / len(control),
                             "religion_mean": statistics.fmean(float(r["mean-religion"]) for r in samples),
                             "dependency_mean": statistics.fmean(float(r["mean-dependency"]) for r in samples)})
    boundary = table(RAW / "boundary_search.csv")
    audit(boundary, 220, 1000)
    groups = defaultdict(list)
    for row in boundary:
        groups[(int(float(row["initial-traders"])), float(row["trade-attractiveness"]))].append(row)
    cells = []
    for (traders, attraction), samples in sorted(groups.items()):
        control = [float(row["control-fraction"]) for row in samples]
        successes = sum(value >= .5 for value in control)
        low, high = wilson(successes, len(samples))
        cells.append({"initial_traders": traders, "trade_attractiveness": attraction,
                      "n": len(samples), "control_mean": statistics.fmean(control),
                      "widespread_probability": successes / len(samples),
                      "widespread_wilson_low": low, "widespread_wilson_high": high,
                      "dependency_mean": statistics.fmean(float(r["mean-dependency"]) for r in samples),
                      "religion_mean": statistics.fmean(float(r["mean-religion"]) for r in samples)})
    return marginal, cells


def plots(duration, summary):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np
    FIGURES.mkdir(parents=True, exist_ok=True)
    traders = sorted({row["initial_traders"] for row in summary})
    attraction = sorted({row["trade_attractiveness"] for row in summary})
    lookup = {(row["initial_traders"], row["trade_attractiveness"]): row for row in summary}
    for field, name, title, label in (
        ("control_mean", "control_heatmap.png", "Mean final control fraction", "Mean control"),
        ("widespread_probability", "widespread_probability_heatmap.png",
         "Probability of final control ≥ 0.50", "Probability")):
        matrix = np.array([[lookup[t, a][field] for t in traders] for a in attraction])
        fig, ax = plt.subplots(figsize=(8, 5))
        image = ax.imshow(matrix, origin="lower", aspect="auto", vmin=0, vmax=1,
                          cmap="viridis")
        for y in range(len(attraction)):
            for x in range(len(traders)):
                ax.text(x, y, f"{matrix[y, x]:.2f}", ha="center", va="center",
                        color="white" if matrix[y, x] < .55 else "black")
        ax.set(xticks=range(len(traders)), xticklabels=traders,
               yticks=range(len(attraction)), yticklabels=attraction,
               xlabel="Initial / target traders", ylabel="Trade attractiveness", title=title)
        fig.colorbar(image, ax=ax, label=label)
        fig.tight_layout(); fig.savefig(FIGURES / name, dpi=180); plt.close(fig)
    fig, ax = plt.subplots(figsize=(8, 5))
    ax.errorbar([r["duration_ticks"] for r in duration], [r["control_mean"] for r in duration],
                yerr=[r["control_sd"] / math.sqrt(r["n"]) * T19 for r in duration],
                marker="o", capsize=4)
    ax.axhline(.5, color="firebrick", linestyle="--", label="Widespread threshold")
    ax.set(xlabel="Duration (ticks)", ylabel="Mean final control fraction",
           title="Duration pilot (mean ± 95% t interval, n=5)", ylim=(0, 1))
    ax.grid(alpha=.25); ax.legend(); fig.tight_layout()
    fig.savefig(FIGURES / "duration_comparison.png", dpi=180); plt.close(fig)
    fig, ax = plt.subplots(figsize=(8, 5))
    for a in attraction:
        cells = [lookup[t, a] for t in traders]
        ax.plot(traders, [r["widespread_probability"] for r in cells], marker="o",
                label=f"attractiveness {a:g}")
    ax.set(xlabel="Initial / target traders", ylabel="P(final control ≥ 0.50)",
           title="Confirmatory transition curves", ylim=(-.03, 1.03))
    ax.grid(alpha=.25); ax.legend(); fig.tight_layout()
    fig.savefig(FIGURES / "transition_curves.png", dpi=180); plt.close(fig)


def representative_analysis():
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    cases = (
        ("below boundary", "representative_below_boundary.csv", 8, .6, 500003),
        ("boundary", "representative_boundary.csv", 16, .6, 500121),
        ("above boundary", "representative_above_boundary.csv", 20, .8, 500207),
    )
    output = []
    fig, axes = plt.subplots(3, 1, figsize=(9, 9), sharex=True)
    for label, filename, traders, attraction, seed in cases:
        rows = table(RAW / filename)
        if (len(rows) != 1001 or any(row["model-valid?"] != "true" for row in rows)
                or [int(float(row["ticks"])) for row in rows] != list(range(1001))):
            raise ValueError(f"Invalid representative trace: {label}")
        control = [float(row["control-fraction"]) for row in rows]
        crossings = [tick for tick, value in enumerate(control) if value >= .5]
        output.append({
            "regime": label, "initial_traders": traders,
            "trade_attractiveness": attraction, "seed": seed,
            "first_widespread_tick": crossings[0] if crossings else "not observed",
            "ticks_widespread": len(crossings),
            "last_100_ticks_widespread": sum(value >= .5 for value in control[-100:]),
            "terminal_control_fraction": control[-1],
            "terminal_kingdoms": int(float(rows[-1]["controlled-kingdoms"])),
        })
        caption = f"{label}: traders={traders}, attraction={attraction:g}, seed={seed}"
        x = list(range(1001))
        axes[0].plot(x, control, label=caption)
        axes[1].plot(x, [float(r["mean-religion"]) for r in rows], label=caption)
        axes[2].plot(x, [float(r["mean-dependency"]) for r in rows], label=caption)
    axes[0].axhline(.5, color="firebrick", linestyle="--", alpha=.8)
    for ax, label in zip(axes, ("Control fraction", "Mean religion", "Mean dependency")):
        ax.set_ylabel(label); ax.set_ylim(0, 1); ax.grid(alpha=.25)
    axes[0].legend(fontsize=8); axes[-1].set_xlabel("Tick")
    fig.suptitle("Representative confirmatory trajectories")
    fig.tight_layout(); fig.savefig(FIGURES / "representative_timeseries.png", dpi=180)
    plt.close(fig)
    return output


def main():
    PROCESSED.mkdir(parents=True, exist_ok=True)
    duration = duration_summary()
    marginal, boundary = exploratory_summaries()
    raw, summary = confirmatory_summary()
    write(PROCESSED / "duration_summary.csv", duration)
    write(PROCESSED / "screening_marginal_summary.csv", marginal)
    write(PROCESSED / "boundary_search_summary.csv", boundary)
    write(PROCESSED / "confirmatory_cell_summary.csv", summary)
    plots(duration, summary)
    write(PROCESSED / "representative_persistence.csv", representative_analysis())
    print("PASS: 25 duration-pilot, 300 confirmatory, and 3 representative runs audited; summaries and five figures written")


if __name__ == "__main__":
    main()
