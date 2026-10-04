# Verification protocol

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

## Repository boundaries

Check the working tree, index, and staged content before every commit:

```bash
git status --short
git ls-files
git diff --cached --name-only
git diff --cached
git diff --check
git diff --cached --check
```

Stage explicit project paths. Private coordination material stays outside Git;
local exclusions are clone-specific. Keep scientific documentation, attribution,
reproducible tests, and measured results reviewable. Never rewrite history or
invent output to make a check pass. Inspect submission archives independently.

## Foundation validation when a model exists

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
No Foundation or GUI acceptance criterion has been executed at repository setup.
