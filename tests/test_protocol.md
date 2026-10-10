# Verification protocol

## Configurable duration checks

Run the focused NetLogo 6.4.0 regression before the longer cumulative suite:

```bash
python3 scripts/check_duration.py /home/adam/tools/NetLogo-6.4.0-64
```

It checks the saved interactive default of 0 with a 250-tick external test
horizon, then runs actual 100-, 450-, 1000-, and 2000-tick simulations; checks exact stop
ticks and the `go-once` guard; changes the slider during an active run; performs
a second setup with a new duration; exports every plot; verifies all time-series
X ranges and terminal points while leaving the histogram at 0–1; and compares
identically seeded 450/1000 traces through tick 450. It also audits the embedded
and standalone paired BehaviorSpace definitions. This is a small validation set,
not either 980-run production sweep.

## Environment check

Run from the repository root with Python 3 and an installed NetLogo 6.4.x:

```bash
python3 scripts/check_netlogo.py /home/adam/tools/NetLogo-6.4.0-64
```

The check must return exit code 0 and report NetLogo 6.4.x, two complete runs,
eight rows covering ticks 0–3, and zero agents. Compilation errors, missing
executables, empty/metadata-only output, incomplete rows, wrong versions,
duplicate steps, and unexpected dimensions must fail. The fixture is an
installation probe, not a scientific model or a Foundation experiment.

For direct inspection, choose a fresh output path and run:

```bash
/home/adam/tools/NetLogo-6.4.0-64/NetLogo_Console --headless \
  --model tests/fixtures/runtime_probe.nlogo \
  --setup-file tests/fixtures/runtime_probe.xml \
  --experiment 'Runtime probe' --threads 1 \
  --table /tmp/foundation-runtime-probe.csv
```

## Galaxy initialization checks

```bash
python3 scripts/check_model.py /home/adam/tools/NetLogo-6.4.0-64 --stage 1
```

This appends `tests/stage1_checks.nls` to a temporary copy of the model and runs
the checks in NetLogo. Production `foundation.nlogo` remains self-contained.
The checks cover world dimensions and seam crossing, population and placement,
initial distributions, repeated setup, deterministic seed replay, rendering
purity, bounded placement failure, invalid-state rejection, and the tick limit.
Seeds 1, 2, 3, 42, and 101 each run with missionary/trader counts 12/12, 0/12,
12/0, 0/0, and 40/40. Every run reaches 450 ticks; additional calls cannot
advance time. Temporary CSV output must contain the explicit success flag and
a valid final state; an empty or partial export fails.

For GUI verification, open `model/foundation.nlogo`, press `setup`, verify the
four labeled capitals and Terminus, then press `go-once` and confirm tick 1.
Run `go` through tick 450 and verify that its forever button stops. Settings
must show -32 through 31 on both axes with both wrapping checkboxes enabled.
Save/reopen the model and repeat. Verify the eight slider defaults and all
four chooser modes, using a tick to refresh colors. Both visitor breeds now move.

## Missionary checks

```bash
python3 scripts/check_model.py /home/adam/tools/NetLogo-6.4.0-64 --stage 2
```

This runs the cumulative galaxy checks followed by `tests/stage2_checks.nls`.
The earlier placeholder-only assertion is now a stationary planet identity
check; initialization, reset, placement, bounds and horizon checks remain.

| Check | Coverage |
| --- | --- |
| S2-A | Population, valid references, skill bounds, exploration/weighted choice, empty destinations |
| S2-B | Speed bound, movement, exact arrival and shortest travel across both seams |
| S2-C | One outcome per arrival, no repeat visit while stationary or detained |
| S2-D | Zero effectiveness, exact conversion formula, saturation and state bounds |
| S2-E | Admission/execution formulas, pure reporters, policy bounds, distinct detention/death branches |
| S2-F | Temple threshold, embargo construction/repair block, repression dismantling, bounded repair |
| S2-G | Zero missionaries and complete execution both run to tick 450 with recruitment target zero |
| S2-H | Full 450-tick traces replay seed 123, differ for 124, and survive view changes unchanged |

Controlled visit fixtures search for RNG seeds that reach acceptance, detention
or execution. These are branch tests, not experimental samples or calibration.
Fixtures restore normal initialization using `setup`. The diagnostic run uses
seed 101, 12 missionaries, zero traders and default effectiveness/intolerance;
it prints actual positions, modes, targets and cumulative outcomes at ticks
1, 50, 150 and 450. Parameter corners test 40 missionaries, effectiveness 0/.5
and intolerance 0/1. Every traced tick checks bounds, population accounting,
cumulative counters and absence of trade income. No scientific conclusions
should be drawn from these diagnostic runs.

For a GUI check, open the production model, use the Command Center to run
`set initial-traders 0 random-seed 101 setup`, then click `go-once`. Verify
cyan missionaries have moved away from Terminus. Advance to ticks 50 and 150
to inspect traveling/detained missionaries. `go` should stop at 450. The Info
tab describes the current rules, including government decisions and paid recruitment.

## Trader and network checks

```bash
python3 scripts/check_model.py /home/adam/tools/NetLogo-6.4.0-64 --stage 3
```

This runs all earlier checks and `tests/stage3_checks.nls`
in a temporary model. The Stage 1 clock checks now verify the treasury/profit
identity; zero-trader cases still require zero revenue and routes. The isolated
Stage 2 tests continue with zero traders, preserving their original invariants.

| Check | Coverage |
| --- | --- |
| S3-A | 450 ticks without traders; trade expansion without missionaries |
| S3-B | Exact admission formula, policy/parameter corners, monotonic religion effect, RNG purity |
| S3-C | 100 independent seeds at zero religion and favorable demand; real accepted visits without conversion |
| S3-D | Single sale attribute deltas, no repeated payment, bounded values, zero-size admissions |
| S3-E | Rejected visitors detained or executed, full waiting periods, no benefits, extinction safety |
| S3-F | Undirected route creation/reinforcement, exact aging, removal, single decay per tick, pure styling |
| S3-G | 1.5/2.25 movement, both seams, .15 threshold, safe route removal while traveling |
| S3-H | Exact revenue for one/two visits, tick reset, full-run treasury/profit/income reconciliation |
| S3-I | Actual default-seed 101/102/103 diagnostics, 450-tick invariants, replay and slider corners |

Branch fixtures find seeds for acceptance, detention and execution; these are
not scientific samples. The independent secular-trade fixture uses seeds 0–99
without selecting outcomes. Integration uses complete numeric snapshots for
seed 123 replay, seed 124 variability and view-mode independence. All trace
observations must leave the simulation RNG unchanged. Additional runs cover
40 agents of each breed with trade attractiveness 0/1 and royal intolerance 0/1.

Accepted zero-size trades increment accepted-visit counters but change no
market state, revenue or route strength. Route age is time since creation.
Existing weak routes affect targeting; only strength >= .15 speeds travel.
The secular expansion test disables domestic substitution to isolate trade's
contribution; Stage 4 separately tests the combined environmental dynamics.

For GUI verification, open the production model with defaults, enter
`random-seed 101 setup`, and run to ticks 50 and 150. Wait for each command to
finish before starting another. Inspect moving white traders and blue routes.
Use `go` to reach 450; check `model-valid?` and the cumulative sale/rejection/death
counts. For a visual fixture, set two route strengths to .10 and .90, invoke
`update-appearance`, and compare line brightness/thickness. Restore with setup.

## Technology and economy checks

```bash
python3 scripts/check_model.py /home/adam/tools/NetLogo-6.4.0-64 --stage 4
python3 scripts/check_economy.py /home/adam/tools/NetLogo-6.4.0-64 /tmp/foundation-economy-evidence
```

Use `--stage 4` to run the cumulative economic regression suite. It runs all Stage 1–3 regressions and
`tests/stage4_checks.nls` using a temporary self-contained model. The production
model never includes the test fixtures. Choose a fresh scenario output directory;
the exporter refuses to overwrite existing evidence.

| Check | Coverage |
| --- | --- |
| S4-A | Exact wear, long-run clipping, Terminus exclusion and deterministic local updates |
| S4-B | Temple/religion/policy eligibility, inclusive .60 threshold, combined wear/maintenance clipping |
| S4-C | Sale consumption, regeneration, faster demand under damage, saturation at 1 |
| S4-D | No substitution at zero effort, wealth-scaled alternatives, gradual independence without conversion |
| S4-E | Matched open/embargo worlds, no immediate penalty, delayed infrastructure and wealth losses |
| S4-F | Reopening alone gives no instant benefit, missionary/trade repairs, high-condition wealth recovery |
| S4-G | Six 2450-update seed/corner runs and four 2000-update mixed corners; all states validated |
| S4-H | Repeated accepted secular trades cross .45 dependency without conversion; missions do not add dependency |

The long-run checks execute 450 normal ticks, confirm `go` and `go-once` stop,
then exercise update helpers another 2000 times with the clock held at 450.
Both all-minimum and all-maximum slider configurations replay seed 123 exactly
and differ for seed 124. Mixed wear/substitution corners retain high dependency
when effort is zero. A separate full-run comparison verifies the scheduler
applies environmental changes exactly once before visits. State checks include
wealth, infrastructure, dependency and the bounded `previous-policy-wealth`
snapshot. Initialization stores a population-weighted kingdom mean on capitals;
policy decisions refresh that snapshot; isolated environmental updates preserve it.

The scenario exporter runs these controlled initial conditions with seed 101:
all external worlds have religion .9, dependency .85, health .8, wealth 80,
demand .7, trust .2, hostility/taboo 0 and a temple. Decay is .01, intolerance
0, and no missionaries are present. Prosperity has 40 actual traders and open
policies. Dependency trap has no traders and forced embargo. Alternative
industry has the same embargo/no-trader conditions and independence effort 1.
Effort is otherwise 0. These isolated regressions use `go-economic-scenario`,
which holds policies and religious state fixed and omits recruitment. Full
endogenous politics is exercised separately by the Stage 5 scenarios.

Each scenario runs twice, exporting all 451 observations. CSV auditing requires
exact run/step coverage, finite bounded metrics, valid states, and identical
replays. `samples.csv` contains ticks 0, 50, 150, 300 and 450; full CSVs, fixture
XML and SHA-256 hashes accompany it. The XML refers to the temporary test model;
rerun the exporter to reconstruct it. These deliberately controlled mechanism
demonstrations are not the Stage 7 parameter sweep or evidence of a tipping point.

For manual inspection, open the production model, run `random-seed 101 setup`,
then observe `mean-tech-health`, `mean-tech-demand`, `mean-wealth` and
`technology-crisis-planets` in the Command Center as ticks advance. Set both
visitor counts to zero before setup to isolate environmental changes. The Info
tab describes the update order and all economic rules. Full plots and monitors
are checked separately below; headless CSV checks do not verify GUI behavior.

## Validation as behavior is introduced

Use actual NetLogo 6.4.x execution for compilation, state bounds, deterministic
seed replay, repeated setup, toroidal placement/travel, and scheduler checks.
The production horizon is 450 ticks; a second call after the horizon must not
advance time. Test empty populations, clamping, rejection/death, transaction
atomicity, decaying links, and policy hysteresis as mechanisms are introduced.
Helpers can be stress-tested separately without changing the production horizon.

Audit BehaviorSpace metadata and data rows, exact configuration/run coverage,
finite values, and terminal ticks. Analyze only real CSV exports. Record seeds,
settings, model/XML hashes, and any exclusions with scientific evidence.

GUI checks require opening the actual model: exercise all buttons and controls,
verify wrapping settings, inspect agent appearance, observe live time series and
histograms, and save/reopen. Capture screenshots or direct observations. A
headless result does not establish GUI correctness.

Classify each check as PASS, FAIL, or NOT RUN, with a reason for any omission.

## Government and effective control checks

```bash
python3 scripts/check_model.py /home/adam/tools/NetLogo-6.4.0-64 --stage 5
python3 scripts/check_politics.py /home/adam/tools/NetLogo-6.4.0-64 /tmp/foundation-politics-evidence
```

Stage 6 is the default cumulative suite. `--only` runs just the selected stage
while compiling all fixture dependencies. Earlier integration checks now include
paid replacements in population conservation and subtract recruitment costs from
net profit. Isolated extinction fixtures set replacement targets to zero; Stage 5
also checks extinction with no funds and later recovery. No prior event, movement,
probability, route, economy or initialization check is removed.

| Check | Coverage |
| --- | --- |
| S5-A | Population-weighted R/D/T/W/H, capital policy synchronization, other-government isolation, tick 0/10 cadence |
| S5-B | Rising influence, actual mission/sale effects, intolerance, strict restriction/embargo thresholds and dependency guard |
| S5-C | Oscillation around threshold, lower release boundary, independent local entry/release gaps |
| S5-D | Inclusive 2-unit wealth drop and .60 dependency, one-step concessions, snapshot refresh, exact 20-tick cooldown |
| S5-E | Mission/trade admission penalties, failed expansion and delayed dependent-world embargo losses |
| S5-F | Exact religious decline/local persistence, causal temple removal, hostility drift and bounds |
| S5-G | Exact leverage, inclusive .58, fifth consecutive tick, immediate reset, secular control and Terminus exclusion |
| S5-H | Population weighting rather than headcount, mandatory capital, reversible 0–4 kingdom control, pure reporters |
| S5-I | Ten-tick recruitment, two-per-breed caps, once-only costs, scarce funds/partial recruitment, detention and late funded recovery |
| S5-J | Default seeds 1/2/3/42/101, every slider endpoint, all-minimum/maximum, scenario runs and five 2450-update stress runs |

Policy choices left open by the specification are explicit: kingdom embargoes
persist until the lower restriction release threshold or crisis; cooldown blocks
escalation only; an already-open government remains open during a continuing
measured crisis without extending cooldown; independent embargo releases below .80 and restriction below .65;
dependency gates embargo entry; missionaries receive recruitment funds first.
Open hostility decreases only when above baseline. No coefficients are calibrated.

The scenario exporter records all 451 ticks for six configurations: default,
failed expansion (hostility/taboo 1, religion/dependency/trust 0, intolerance 1,
substitution 0), favorable stable control (40 of each visitor, effectiveness .5,
attraction 1, intolerance/substitution 0, wear .005), political resistance
(religion .9, dependency .5, trust .8, temple present, hostility/baseline .8,
taboo .3, intolerance 1, substitution 0), and all slider minima/maxima.
All remaining settings use defaults; initial states are ordinarily sampled except
where explicitly overridden. These are mechanism demonstrations, not a sweep or
proof of a historical tipping point.

Each configuration runs seed 123 twice and 124 once. Audits require 8118 complete,
finite, valid rows, exact replay, seed variation, monotonic counters and financial
identities. `samples.csv` records both seeds at ticks 0, 50, 150, 300 and 450,
including control, religion, dependency, health, wealth, casualties, treasury,
profit, recruitment costs and policy counts. Source/XML/data hashes accompany
CSV evidence. Output directories must be fresh. Reconstruct temporary fixture
models by rerunning the exporter; production remains self-contained.

The stress tests preserve the 450-tick production limit. After normal runs, they
exercise update helpers another 2000 times at the fixed horizon. Policy and
recruitment guards prevent repeated decisions/spending at the same tick; full
450-tick runs exercise interval timing and cooldowns normally. Earlier economic
stress cases cover both simultaneous slider corners.

GUI inspection remains separate: in the production model observe capital policy,
previous-policy-wealth, policy-cooldown-until, controlled-planets and
controlled-kingdoms while running; change to the control view to see current
influence. The following checks cover the completed interface.

## Interface, plots and documentation checks

```bash
python3 scripts/check_model.py /home/adam/tools/NetLogo-6.4.0-64 --stage 6
python3 scripts/check_interface.py /home/adam/tools/NetLogo-6.4.0-64 /tmp/foundation-interface-evidence
```

The first command runs all six stages, including earlier seed, slider endpoint,
economic, political and long-running helper regressions. Add `--only` to isolate
Stage 6. Its rendering checks cover colors, shapes, policy labels, RNG/state
purity, setup resets, single stepping, the 450-tick stop and a complete seeded
replay with changing views.

The interface exporter requires a fresh destination. It checks exact slider
names/ranges/defaults/steps, button commands and forever flags, the chooser,
monitor expressions and Info sections. It then executes seed 123 for 450 ticks
with plots enabled, plots enabled while changing views, and plots disabled.
All 1353 recorded states must agree exactly, including every monitor and the
detailed simulation trace. Monitor precision affects display only.

Actual plot exports are compared point by point against reporter values.
Histogram checks require 30 worlds, exclude Terminus, and test values 0, .5 and
1 explicitly. Religion = 1 belongs in the last of ten bins; only the value passed
to the histogram is nudged below 1. A controlled fixture verifies the first four
ticks have zero control and the fifth has 30 controlled worlds. Repeated setup
must reset all four plots. Source, XML and measured CSV hashes accompany the
evidence. Plot execution is explicitly enabled for these checks; ordinary
BehaviorSpace experiments do not need it.

| Check | Verification |
| --- | --- |
| S6-A | Nine sliders including Simulation Duration, chooser, core buttons, pure refresh button; actual GUI widget operation and save/reopen |
| S6-B | Setup reset, go-once advances exactly one tick, forever go pauses/resumes and stops at 450; prior slider corner runs |
| S6-C | Twelve evaluated monitors, three live time series, one ten-bin distribution; actual exports and GUI inspection |
| S6-D | All kingdom colors, capital rings, gold Terminus, gray independents, cyan missionaries, white traders and evolving blue routes |
| S6-E | Identical full seeded traces with changing views and with/without plots; repeated redraw preserves RNG and state |
| S6-F | Info describes every parameter, scheduling, ODD concepts, metrics, fictional assumptions and references |
| S6-G | Actual Interface screenshots and rendered Info review, separately from headless evidence |

For GUI verification, open `model/foundation.nlogo` in NetLogo 6.4.x. Read Info
and reproduce a run using its instructions. Exercise each slider, then restore
the documented defaults. Click setup and check tick zero and reset charts;
click go-once and check tick one. Start go, stop it before 450, and verify the
tick remains unchanged while paused. Resume and check automatic termination at
450. At about ticks 100 and 200, inspect agents/routes and every chart/monitor.
Select all four views and use refresh view while paused; the tick must not move.
Check colors against the legends and identify policy R/E labels when present.
Save a temporary copy outside the repository, close and reopen it, and check
that widget names, values and button behavior persist. Capture actual screenshots
and review Info rendering, including defaults and references. A smaller window
may require scrolling; approximately 1300 by 980 pixels shows the full interface.

For exact seeded screenshots, the Command Center can run `random-seed 123 setup`
and `repeat 100 [go]` with default sliders. GUI test fixtures may also call these
commands in a temporary startup procedure, but screenshots of monitor values
must be taken after that job finishes: GUI monitor refresh is asynchronous.
Record any GUI step not performed as NOT RUN; headless checks cannot replace it.

## BehaviorSpace experiment and analysis checks

Run the smoke experiment twice before production, then compare rows by run number
because parallel BehaviorSpace output order is not guaranteed:

```bash
bash scripts/run_behaviorspace.sh /home/adam/tools/NetLogo-6.4.0-64 \
  experiments/smoke_test.xml 'Foundation Smoke Test' /tmp/foundation-smoke.csv 1
python3 scripts/validate_results.py /tmp/foundation-smoke.csv experiments/smoke_test.xml
```

The final measured export can be audited and analyzed with:

```bash
python3 scripts/validate_results.py results/raw/foundation_sweep.csv \
  experiments/foundation_sweep.xml --production
python3 -m pip install -r requirements-analysis.txt
python3 scripts/analyze_experiments.py
```

The validator requires exactly 980 terminal rows, 49 parameter cells, 20 runs
per cell, run IDs 1–980, seeds 100001–100980, tick 450, all planned settings and
all required reporters. It also verifies state bounds, model validity and the
treasury/profit identity. It never imputes missing results.

`cell_summary.csv` must contain 49 rows. For an independent arithmetic check,
recompute one cell with the sample standard deviation (`n - 1`) and
`t(0.975, 19) = 2.0930240544`. The final figures must be regenerated from the
CSV and visually inspected. `run_representatives.py` replays the three selected
production seeds for all 451 ticks; their terminal control values must match the
selected production records exactly.

In the NetLogo 6.4 GUI, open Tools → BehaviorSpace, import
`experiments/foundation_sweep.xml`, and verify that the experiment is listed as
`Foundation Religious-Economic Tipping Point`. Inspect 20 repetitions, 450 steps,
the two seven-value factors, fixed defaults and end-state-only metrics. Do not
save experimental output over the checked-in raw CSV.
