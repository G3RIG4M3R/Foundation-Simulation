# Tipping-point investigation

## Conclusion

The model can produce widespread Foundation control within its legal parameter
space, but the original missionary-effectiveness × royal-intolerance experiment
did not reach the relevant region. The clearest transition is an
economic-dependency boundary controlled jointly by trader population and trade
attractiveness under favorable missionary access. The continuous control
fraction rises smoothly; the binary operational outcome (`control-fraction >=
0.50`) changes rapidly over a narrow part of that gradient. This is evidence for
an operational stochastic threshold, not proof of a mathematical phase
transition.

At trade attractiveness 0.60, the confirmatory probability of widespread final
control was 0/20 with 12 traders (95% Wilson interval 0.000–0.161), 10/20 with 16
traders (0.299–0.701), and 20/20 with 20 traders (0.839–1.000). Mean control and
95% Student-t intervals were respectively 0.387 [0.364, 0.409], 0.497 [0.460,
0.533], and 0.605 [0.577, 0.633]. At attractiveness 0.80 the boundary shifted
left: 8 traders produced 0/20 widespread runs, while 12 produced 16/20 (Wilson
0.584–0.919). Thus the approximate boundary is 12–20 traders, moving downward
as attractiveness increases.

## What was run

All settings stayed within the Interface slider ranges, all automated runs had
a finite horizon, and no behavioral rule or control threshold was changed.
The historical 980-run Stage 8 dataset was validated and not rerun. The
configured 1,000-tick Stage 8 extension had not previously been executed. A
smaller paired duration study was more useful before committing to another
49-cell sweep.

Scientific evidence retained for this investigation comprises 740 runs:

| Phase | Design | Repetitions | Runs | Horizon | Seeds |
| --- | --- | ---: | ---: | ---: | --- |
| Duration pilot | 5 durations (450–3,000), effectiveness 0.50, intolerance 0, default staffing/economy | 5 paired | 25 | 450–3,000 | 200001–200005 per duration |
| Mechanism screen | 2-level factorial over missionary/trader staffing, attractiveness, decay, religion-trade weight, substitution | 3 | 192 | 1,000 | 300001–300192 |
| Adaptive boundary | 11 trader counts × 4 attractiveness values | 5 | 220 | 1,000 | 400001–400220 |
| Confirmation | 5 trader counts × 3 attractiveness values | 20 | 300 | 1,000 | 500001–500300 |
| Representative replay | Below/on/above-boundary confirmatory seeds | 1 | 3 | 1,000 | 500003, 500121, 500207 |

The retained scientific batches took about 307 seconds (5.1 minutes) of
measured NetLogo wall time on this machine. Validation, diagnostics, plotting,
and one preserved but superseded 192-run export are additional. The latter is
`raw/mechanism_screening.csv`; it is excluded because a strict validity reporter
rejected seven harmless floating-point sums of `100.00000000000001`.
`raw/mechanism_screening_audited.csv` is its complete rerun after adding a
1e-12 tolerance to that validation predicate only. Trajectories and behavioral
rules were unchanged.

## Findings by phase

Duration helped substantially but gradually. With default populations and the
most favorable effectiveness/intolerance pair, mean final control increased
from 0.047 at tick 450 to 0.253, 0.313, 0.413, and 0.493 at ticks 1,000, 1,500,
2,000, and 3,000. Three of five runs were widespread at tick 3,000. Religion
rose earlier than control, while dependency climbed from 0.092 to 0.514. Time is
therefore a limiting factor, but the five-point curve does not show a sharp
temporal jump.

The mechanism screen identified traders as the strongest staffing lever. Its
marginal mean control was 0.526 at 12 traders and 0.707 at 40, versus 0.611 and
0.622 at 12 and 40 missionaries. Higher attractiveness and religion-trade
weight also helped; eliminating substitution helped more modestly. Decay over
the tested 0.005–0.015 contrast had almost no marginal effect. These are
screening associations from a factorial design, not isolated causal estimates.

The adaptive grid then showed a broadly monotone diagonal boundary. With no
traders, control was zero despite mean religion around 0.74. Higher trader count
and attractiveness raised technological dependency, which supplies 35% of
planet leverage and also supports trade trust. In confirmation, mean dependency
at attractiveness 0.60 rose from 0.224 (8 traders) to 0.404 (12), 0.535 (16),
and 0.645 (20). The corresponding widespread probabilities were 0, 0, 0.5,
and 1. This separates the economic mechanism from missionary conversion alone.

The representative below-boundary run never crossed 0.50. The boundary run
first crossed at tick 967 and was widespread for 26 of 1,001 recorded states,
so its terminal classification was not yet strongly persistent. The
above-boundary run first crossed at tick 620, remained widespread for all final
100 ticks, and ended at 0.633 control with two controlled kingdoms. Terminal
probability should therefore be read alongside persistence, especially on the
boundary.

## Confirmatory design for submission

The recommended university experiment is `tipping_confirmatory.xml`. It varies
exactly two hyperparameters: initial/target traders (8, 12, 16, 20, 24) and
trade attractiveness (0.60, 0.80, 1.00). It fixes duration 1,000, missionary
effectiveness 0.50, royal intolerance 0, missionaries 12, decay 0.015,
religion-trade weight 0.80, substitution 0.15, and view mode `kingdom`. Each of
15 cells has 20 unique seeds. Primary reporters are control fraction and
controlled kingdoms; religion, dependency, profit, trades, deaths, clock, seed,
and model validity provide mechanism and audit evidence.

Use `figures/control_heatmap.png`,
`figures/widespread_probability_heatmap.png`, and
`figures/transition_curves.png` as the main figures. The duration and
representative plots are useful supporting figures. Continuous outcomes use
Student-t intervals; binary outcomes use Wilson score intervals.

## Reproduction

From the repository root, with the existing analysis environment:

```bash
python3 scripts/run_behaviorspace.py \
  /home/adam/tools/NetLogo-6.4.0-64 \
  experiments/tipping_confirmatory.xml \
  'Confirmatory trader-attractiveness tipping grid' \
  /tmp/foundation-confirmatory.csv 4

MPLCONFIGDIR=/tmp/foundation-matplotlib \
  .venv/bin/python scripts/analyze_tipping_investigation.py
```

The runner refuses to overwrite evidence, so reproduction must use fresh output
paths. To reproduce every checked-in raw batch, substitute the corresponding
XML, experiment name, and output path shown in each provenance JSON. The
analysis command intentionally reads the audited files under this directory.

## Artifacts and limitations

- `raw/`: actual NetLogo tables and SHA-256 provenance sidecars.
- `processed/duration_summary.csv`: paired duration results.
- `processed/screening_marginal_summary.csv`: exploratory marginal effects.
- `processed/boundary_search_summary.csv`: adaptive-grid summaries.
- `processed/confirmatory_cell_summary.csv`: t intervals and Wilson intervals.
- `processed/representative_persistence.csv`: crossing/persistence diagnostics.
- `figures/`: five generated plots.

The transition is conditional on maximum missionary effectiveness, zero royal
intolerance, high religion-assisted trade admission, and a 1,000-tick horizon;
it is not a universal critical trader count. The confirmatory grid estimates
terminal behavior, not the probability of remaining widespread for a specified
future duration. Twenty repetitions leave wide binomial intervals near 0.5,
and the coarse four-trader spacing cannot locate a unique critical value.
Kingdom control is also stricter than planet control because it requires a
controlled capital and 60% population-weighted control. A future extension
should record per-tick threshold occupancy for every confirmatory run and add
independent validation cells at 14 and 18 traders without reusing these seeds.
