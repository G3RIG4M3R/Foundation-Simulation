#!/usr/bin/env python3
"""Summarize the final sweep and plot measured uncertainty and trajectories."""
import argparse
import csv
from collections import defaultdict
import math
from pathlib import Path
import statistics

from validate_results import FACTORS, NAME, validate

T_CRITICAL_DF19 = 2.093024054408263


def summarize(rows):
    grouped = defaultdict(list)
    for row in rows:
        key = tuple(float(row[factor]) for factor in FACTORS)
        grouped[key].append(row)
    summaries = []
    for (effectiveness, intolerance), samples in sorted(grouped.items()):
        result = {
            "missionary_effectiveness": effectiveness,
            "royal_intolerance": intolerance,
            "duration_ticks": int(float(samples[0]["ticks"])),
            "n": len(samples),
        }
        for source, prefix in (("control-fraction", "control"),
                               ("cumulative-trade-profit", "profit")):
            values = [float(row[source]) for row in samples]
            mean = statistics.fmean(values)
            sd = statistics.stdev(values)
            half = T_CRITICAL_DF19 * sd / math.sqrt(len(values))
            result.update({f"{prefix}_mean": mean, f"{prefix}_sd": sd,
                           f"{prefix}_ci_low": mean - half,
                           f"{prefix}_ci_high": mean + half,
                           f"{prefix}_ci_half_width": half})
        for source, target in (("controlled-kingdoms", "kingdoms_mean"),
                               ("mean-religion", "religion_mean"),
                               ("mean-dependency", "dependency_mean")):
            result[target] = statistics.fmean(float(row[source]) for row in samples)
        summaries.append(result)
    return summaries


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def select_representatives(raw_rows, summaries):
    ordered = sorted(summaries,
                     key=lambda row: (row["control_mean"],
                                      row["missionary_effectiveness"],
                                      -row["royal_intolerance"]))
    low, high = ordered[0], ordered[-1]
    midpoint = (low["control_mean"] + high["control_mean"]) / 2
    middle = min((row for row in summaries if row not in (low, high)),
                 key=lambda row: (abs(row["control_mean"] - midpoint),
                                  row["missionary_effectiveness"],
                                  row["royal_intolerance"]))
    labels = (("failed", low), ("intermediate", middle),
              ("highest observed", high))
    chosen = []
    for label, cell in labels:
        candidates = [row for row in raw_rows
                      if float(row[FACTORS[0]]) == cell["missionary_effectiveness"]
                      and float(row[FACTORS[1]]) == cell["royal_intolerance"]]
        sample = min(candidates,
                     key=lambda row: (abs(float(row["control-fraction"]) -
                                          cell["control_mean"]),
                                      int(row["[run number]"])))
        chosen.append({
            "regime": label,
            "missionary_effectiveness": cell["missionary_effectiveness"],
            "royal_intolerance": cell["royal_intolerance"],
            "cell_control_mean": cell["control_mean"],
            "terminal_control_fraction": float(sample["control-fraction"]),
            "production_run_number": int(sample["[run number]"]),
            "seed": int(float(sample["100000 + behaviorspace-run-number"])),
        })
    return chosen


def make_heatmaps(summaries, figures, horizon):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np

    xs = sorted({row["missionary_effectiveness"] for row in summaries})
    ys = sorted({row["royal_intolerance"] for row in summaries})
    lookup = {(row["missionary_effectiveness"], row["royal_intolerance"]): row
              for row in summaries}
    mean = np.array([[lookup[x, y]["control_mean"] for x in xs] for y in ys])
    half = np.array([[lookup[x, y]["control_ci_half_width"] for x in xs] for y in ys])
    figures.mkdir(parents=True, exist_ok=True)

    fig, ax = plt.subplots(figsize=(10, 7))
    observed_max = max(float(mean.max()), 1e-6)
    image = ax.imshow(mean, origin="lower", aspect="auto", vmin=0,
                      vmax=observed_max, cmap="viridis")
    for iy in range(len(ys)):
        for ix in range(len(xs)):
            color = "white" if mean[iy, ix] < observed_max * .55 else "black"
            ax.text(ix, iy, f"{mean[iy, ix]:.2f}\n±{half[iy, ix]:.2f}",
                    ha="center", va="center", color=color, fontsize=8)
    ax.set(xticks=range(len(xs)), xticklabels=[f"{x:.2f}" for x in xs],
           yticks=range(len(ys)), yticklabels=[f"{y:.2f}" for y in ys],
           xlabel="Missionary effectiveness", ylabel="Royal intolerance",
           title=(f"Foundation control at tick {horizon}\ncell mean ± 95% Student t CI "
                  "half-width (n=20; color scaled to observed range)"))
    fig.colorbar(image, ax=ax, label="Mean control fraction")
    fig.tight_layout()
    fig.savefig(figures / "control_heatmap.png", dpi=180)
    plt.close(fig)

    fig, ax = plt.subplots(figsize=(9, 6.5))
    image = ax.imshow(half, origin="lower", aspect="auto", cmap="magma")
    for iy in range(len(ys)):
        for ix in range(len(xs)):
            ax.text(ix, iy, f"{half[iy, ix]:.3f}", ha="center", va="center",
                    color="white" if half[iy, ix] > half.max() / 2 else "black",
                    fontsize=8)
    ax.set(xticks=range(len(xs)), xticklabels=[f"{x:.2f}" for x in xs],
           yticks=range(len(ys)), yticklabels=[f"{y:.2f}" for y in ys],
           xlabel="Missionary effectiveness", ylabel="Royal intolerance",
           title="95% confidence interval half-width for control fraction")
    fig.colorbar(image, ax=ax, label="CI half-width")
    fig.tight_layout()
    fig.savefig(figures / "control_ci_halfwidth.png", dpi=180)
    plt.close(fig)


def tipping_points(summaries):
    results = []
    for intolerance in sorted({row["royal_intolerance"] for row in summaries}):
        cells = sorted((row for row in summaries
                        if row["royal_intolerance"] == intolerance),
                       key=lambda row: row["missionary_effectiveness"])
        crossing = next((row for row in cells if row["control_mean"] >= .5), None)
        results.append({"royal_intolerance": intolerance,
                        "first_effectiveness_with_mean_control_ge_0_5":
                            "not observed" if crossing is None else
                            crossing["missionary_effectiveness"]})
    return results


def plot_timeseries(path, figure, expected_horizon=None):
    if not path.is_file():
        return False
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    with path.open(newline="", encoding="utf-8") as stream:
        rows = list(csv.DictReader(stream))
    groups = defaultdict(list)
    for row in rows:
        groups[row["regime"]].append(row)
    horizons = {max(int(row["tick"]) for row in samples) for samples in groups.values()}
    if expected_horizon is not None and horizons != {expected_horizon}:
        raise ValueError("Representative time series duration does not match the sweep")
    fig, axes = plt.subplots(3, 1, figsize=(10, 10), sharex=True)
    labels = (("control_fraction", "Control fraction", (0, 1)),
              ("mean_religion", "Mean religion", (0, 1)),
              ("mean_dependency", "Mean dependency", (0, 1)))
    for regime, samples in groups.items():
        samples.sort(key=lambda row: int(row["tick"]))
        caption = (f"{regime}: eff={float(samples[0]['missionary_effectiveness']):.2f}, "
                   f"intol={float(samples[0]['royal_intolerance']):.2f}, "
                   f"seed={samples[0]['seed']}")
        for ax, (column, ylabel, limits) in zip(axes, labels):
            ax.plot([int(row["tick"]) for row in samples],
                    [float(row[column]) for row in samples], label=caption)
            ax.set_ylabel(ylabel)
            ax.set_ylim(*limits)
            ax.grid(alpha=.25)
    axes[0].legend(fontsize=8, loc="upper left")
    axes[-1].set_xlabel("Tick")
    fig.suptitle("Representative observed outcome trajectories")
    fig.tight_layout()
    figure.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(figure, dpi=180)
    plt.close(fig)
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw", type=Path, default=Path("results/raw/foundation_sweep.csv"))
    parser.add_argument("--xml", type=Path, default=Path("experiments/foundation_sweep.xml"))
    parser.add_argument("--name", default=NAME,
                        help="Experiment name in the XML/CSV metadata")
    parser.add_argument("--timeseries", type=Path,
                        default=Path("results/raw/representative_timeseries.csv"))
    parser.add_argument("--processed", type=Path, default=Path("results/processed"))
    parser.add_argument("--figures", type=Path, default=Path("results/figures"))
    args = parser.parse_args()
    raw_rows = validate(args.raw, args.xml, args.name, True)
    horizons = {int(float(row["ticks"])) for row in raw_rows}
    if len(horizons) != 1:
        raise ValueError("Do not aggregate runs with different durations")
    horizon = horizons.pop()
    summaries = summarize(raw_rows)
    if len(summaries) != 49 or any(row["n"] != 20 for row in summaries):
        raise ValueError("Expected 49 complete cells with n=20")
    write_csv(args.processed / "cell_summary.csv", summaries)
    write_csv(args.processed / "tipping_points.csv", tipping_points(summaries))
    write_csv(args.processed / "representative_selection.csv",
              select_representatives(raw_rows, summaries))
    make_heatmaps(summaries, args.figures, horizon)
    plotted = plot_timeseries(args.timeseries, args.figures / "regime_timeseries.png",
                              horizon if args.timeseries.is_file() else None)
    print(f"PASS: tick {horizon}; 49 cell summaries and two uncertainty figures; "
          f"representative plot {'written' if plotted else 'pending measured time series'}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError) as error:
        raise SystemExit(f"FAIL: {error}") from error
