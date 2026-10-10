# Foundation: Religion, Trade & Control

An agent-based simulation inspired by Isaac Asimov's Foundation, developed for
a university Collective Intelligence assignment.

The model explores how missionary effectiveness and royal intolerance affect
non-military influence through religion, technology, and trade.

Target: NetLogo 6.4.x, with a self-contained `.nlogo` model.

Open `model/foundation.nlogo` in NetLogo, choose **Simulation Duration**, then
click `setup`. The slider defaults to 0 (unlimited); finite choices are
100–3000 ticks in steps of 50. Use `go-once` for one tick or `go` to run to a
captured positive limit. Changing the duration during a run takes effect only
after the next `setup`, so a run's horizon cannot change silently. The
`view-mode` chooser selects planet
coloring; click `refresh view` when paused. Changing the view does not advance
time or affect the simulation. The three time-series plots adapt to the captured
duration; the religion histogram retains its 0–1 distribution axis.

With the bundled installation used for this project, start the model with:

```bash
/home/adam/tools/NetLogo-6.4.0-64/bin/NetLogo model/foundation.nlogo
```

For a repeatable run, enter `random-seed 123 setup` in the Command Center before
clicking `go`. To explore the model, change one or more sliders, click `setup` to
create a fresh galaxy with those settings, then run again. Useful comparisons
include low/high missionary effectiveness, low/high royal intolerance, and
changing trader numbers or trade attractiveness. Keep the seed fixed to isolate
the parameter effect; change the seed to study stochastic variation.

Nine sliders control duration, missions, trade, royal intolerance, technology wear and
local substitution. The Interface shows religious influence, economic dependency,
government restrictions and effective Foundation control through twelve monitors,
three time-series plots and a religion histogram. Capital rings and policy labels
remain visible across all four views. The Info tab explains the controls, model
rules, ODD summary and fictional assumptions.

See [the verification protocol](tests/test_protocol.md) for reproducible NetLogo
6.4.x checks and GUI inspection steps. The completed BehaviorSpace workflow,
measured results and interpretation are documented in
[results/README.md](results/README.md). In NetLogo, open Tools → BehaviorSpace and
load `experiments/foundation_duration_sweeps.xml` to select the reproducible
450-tick baseline or 1000-tick extended sweep. The original measured 450-tick
results and their matching legacy XML remain unchanged. GUI and command-line
instructions are in the results documentation.

Licensed under the [MIT License](LICENSE).
