# Experimental results

The existing measured baseline experiment asks whether missionary effectiveness can overcome royal
intolerance and yield stable Foundation control while all other controls remain
at their documented defaults. The preregistered grid uses missionary
effectiveness 0.10–0.40 in 0.05 increments and royal intolerance 0.20–0.80 in
0.10 increments. Each of the 49 cells has 20 runs of 450 ticks. Run `n` uses seed
`100000 + n`, giving 980 distinct and repeatable seeds.

## Pilot and final design decision

Pilot evidence is kept separately under `results/pilot/`. The first pilot used
the four specified range corners with three repetitions. Mean final control was
zero in three corners and 0.022 at effectiveness 0.40/intolerance 0.20. A second,
pre-production boundary pilot tested effectiveness 0.40, 0.45 and the slider
maximum 0.50 against intolerance 0, 0.10 and 0.20, with five repetitions per
cell. Its largest cell mean was 0.067.

The final grid was therefore not shifted after inspecting outcomes. There is no
wider legal missionary-effectiveness range, and changing staffing or other fixed
defaults would answer a different question. Keeping the specified grid also
avoids presenting a post-hoc search as a confirmatory sweep. The pilots show
that even the most favorable legal boundary does not approach widespread
control under default staffing; the final range still captures clear changes in
religion, trade profit and rare local control.

## Observed results

No tested royal-intolerance level has a cell whose mean control fraction reaches
0.50, the prespecified operational tipping criterion. The estimated tipping
point is therefore **not observed** throughout the grid. The strongest cell is
missionary effectiveness 0.40 and royal intolerance 0.20: mean control fraction
0.0283, sample standard deviation 0.0329, and 95% Student t interval
[0.0129, 0.0437]. This corresponds to an average of 0.85 controlled worlds out
of 30, far below stable system-wide control. Across all 980 runs, 105 ended with
at least one controlled world, the maximum in any run was three worlds, and no
run ended with a controlled kingdom.

Higher effectiveness and lower intolerance still produce the most favorable
observed outcomes. At 0.40/0.20, mean cumulative net trade profit is 216.74
credits, mean religion is 0.285 and mean dependency is 0.074. The maximum-profit,
maximum-religion and maximum-dependency cells are all this same configuration.
At the opposite corner, 0.10/0.80, mean religion is 0.0049 and mean dependency
is 0.0083. Twenty-seven cells show some nonzero mean control, but none forms the
large regime change hypothesized in advance.

Under default populations of 12 missionaries and 12 traders, influence usually
does not accumulate enough to sustain the model's five-tick leverage threshold
across many worlds. Royal resistance further reduces admission and increases
losses. This explains the weak gradient without implying that the model has a
universal critical value. The representative plot labels the strongest measured
trajectory “highest observed,” rather than calling it successful.

Each confidence interval is `mean ± t(0.975, 19) × s / sqrt(20)` with
`t = 2.0930240544`. Intervals are not clipped to the theoretical outcome bounds.
Zero-variance cells correctly have zero-width intervals. The annotated heatmap
shows mean and CI half-width in every cell; its colors span the observed range so
the small differences remain visible. The adjacent uncertainty heatmap shows CI
half-widths directly.

## Reproduction

### NetLogo GUI

1. Open `model/foundation.nlogo` in NetLogo 6.4.x and choose Tools → BehaviorSpace.
   The model embeds `Foundation Baseline Sweep (450 ticks)` and `Foundation
   Extended Sweep (1000 ticks)`. Alternatively, import
   `experiments/foundation_duration_sweeps.xml`.
2. Select one experiment and click **Run**. Leave plot updates off for the sweep.
3. Enable table output and choose a new, unmistakable filename such as
   `results/raw/foundation_sweep_450_rerun.csv` or
   `results/raw/foundation_sweep_1000.csv`. Never select an existing evidence file.
4. Confirm 20 repetitions and 980 planned runs, then start. The experiment sets
   a positive `tick-limit` itself; the Interface's unlimited default is irrelevant.
5. Audit the CSV and analyze it with the commands below. The CSV metadata records
   experiment identity, and columns record parameters, run number, final tick,
   active duration, outcomes, and the derived random seed.

### WSL headless execution

The paired definitions use the same 7×7 factors, 20 repetitions, fixed controls,
reporters, and seed `100000 + behaviorspace-run-number`. NetLogo 6.4 interprets
a zero time limit as zero executed steps. Each definition therefore gives
BehaviorSpace the same 450 or 1000 value as `tick-limit`, while its exit condition
also references `active-tick-limit`. The validator rejects any mismatch, so there
is no competing horizon and the BehaviorSpace controller finishes cleanly.

```bash
bash scripts/run_behaviorspace.sh \
  /home/adam/tools/NetLogo-6.4.0-64 \
  experiments/duration_smoke_test.xml \
  'Foundation Duration Smoke Test' \
  /tmp/foundation-duration-smoke.csv 1

python3 scripts/validate_results.py /tmp/foundation-duration-smoke.csv \
  experiments/duration_smoke_test.xml \
  --name 'Foundation Duration Smoke Test'

bash scripts/run_behaviorspace.sh \
  /home/adam/tools/NetLogo-6.4.0-64 \
  experiments/foundation_duration_sweeps.xml \
  'Foundation Baseline Sweep (450 ticks)' \
  results/raw/foundation_sweep_450_rerun.csv 4

bash scripts/run_behaviorspace.sh \
  /home/adam/tools/NetLogo-6.4.0-64 \
  experiments/foundation_duration_sweeps.xml \
  'Foundation Extended Sweep (1000 ticks)' \
  results/raw/foundation_sweep_1000.csv 4
```

These are full 980-run commands; run the smoke/validation commands first. The
runner refuses to overwrite a CSV or provenance sidecar.

```bash
python3 scripts/validate_results.py results/raw/foundation_sweep_450_rerun.csv \
  experiments/foundation_duration_sweeps.xml \
  --name 'Foundation Baseline Sweep (450 ticks)' --production

python3 scripts/validate_results.py results/raw/foundation_sweep_1000.csv \
  experiments/foundation_duration_sweeps.xml \
  --name 'Foundation Extended Sweep (1000 ticks)' --production

python3 scripts/analyze_experiments.py \
  --raw results/raw/foundation_sweep_450_rerun.csv \
  --xml experiments/foundation_duration_sweeps.xml \
  --name 'Foundation Baseline Sweep (450 ticks)' \
  --timeseries /tmp/no-450-timeseries.csv \
  --processed results/processed/450-rerun --figures results/figures/450-rerun

python3 scripts/analyze_experiments.py \
  --raw results/raw/foundation_sweep_1000.csv \
  --xml experiments/foundation_duration_sweeps.xml \
  --name 'Foundation Extended Sweep (1000 ticks)' \
  --timeseries /tmp/no-1000-timeseries.csv \
  --processed results/processed/1000 --figures results/figures/1000

python3 scripts/run_representatives.py \
  /home/adam/tools/NetLogo-6.4.0-64 --duration 1000 \
  --selection results/processed/1000/representative_selection.csv \
  --xml experiments/representative_timeseries_1000.xml \
  --exports results/raw/representative_exports_1000 \
  --output results/raw/representative_timeseries_1000.csv

python3 scripts/analyze_experiments.py \
  --raw results/raw/foundation_sweep_1000.csv \
  --xml experiments/foundation_duration_sweeps.xml \
  --name 'Foundation Extended Sweep (1000 ticks)' \
  --timeseries results/raw/representative_timeseries_1000.csv \
  --processed results/processed/1000 --figures results/figures/1000
```

Compare matching factor cells across the two `cell_summary.csv` files; do not
pool durations into one cell mean. Run numbers map to the same seeds, so paired
run-level comparisons are also valid. Longer runs can differ because they permit
more visits, policy cycles, decay, substitution, recruitment, and recovery. With
identical settings and seed, the 1000-tick trajectory must match the 450-tick run
through tick 450; only the extended continuation is new.

### Historical 450-tick evidence

Run from the repository root. Each exporter refuses to overwrite existing raw
evidence, so choose a fresh output name when repeating a run.

```bash
bash scripts/run_behaviorspace.sh \
  /home/adam/tools/NetLogo-6.4.0-64 \
  experiments/smoke_test.xml 'Foundation Smoke Test' \
  /tmp/foundation-smoke.csv 1

bash scripts/run_behaviorspace.sh \
  /home/adam/tools/NetLogo-6.4.0-64 \
  experiments/foundation_sweep.xml \
  'Foundation Religious-Economic Tipping Point' \
  /tmp/foundation-sweep.csv 4

python3 scripts/validate_results.py \
  results/raw/foundation_sweep.csv experiments/foundation_sweep.xml --production

python3 -m pip install -r requirements-analysis.txt
python3 scripts/analyze_experiments.py
```

`scripts/run_representatives.py` regenerates the representative XML and replays
the selected seeds into a fresh export directory. The checked-in raw CSVs are
the actual NetLogo 6.4.0 exports. Their provenance JSON files contain commands,
elapsed time and SHA-256 hashes; the analysis never fills or simulates missing
observations.

```bash
python3 scripts/run_representatives.py \
  /home/adam/tools/NetLogo-6.4.0-64 \
  --exports /tmp/foundation-representative-exports \
  --output /tmp/foundation-representative-timeseries.csv
```

## Limits of inference

The 0.50 tipping criterion and the local leverage/control thresholds are model
definitions. The topology, political decisions, admission formulas and
coefficients are artificial abstractions inspired by fiction. Twenty repetitions
measure stochastic variation within this implementation, not historical or
external uncertainty. The coarse parameter grid can miss narrow changes between
tested values, and this two-factor design does not estimate interactions with
staffing, trade strength, technology decay or domestic substitution. Results
support conclusions about this calibrated model under fixed defaults, not causal
claims about real societies.
