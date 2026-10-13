# Foundation: Religion, Trade & Control

An agent-based simulation inspired by Isaac Asimov's Foundation, developed for
a university Collective Intelligence assignment.

The selected final study asks how trader population and trade attractiveness
affect non-military Foundation control through technological and economic
dependency. The earlier missionary-effectiveness × royal-intolerance experiment
is retained as historical evidence.

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

## Final deliverables and reproduction

The final configuration is [tipping_confirmatory.xml](experiments/tipping_confirmatory.xml):
15 cells × 20 independent repetitions, 1,000 ticks. See the
[investigation](results/tipping_point_investigation/README.md) for measured results,
raw/processed data, fixed controls and the full fresh-output run command.
The 50% criterion defines widespread terminal control; this is an operational
stochastic threshold, with smoothly increasing mean control, rather than a
proven mathematical phase transition.

- [Two-page report](report/foundation_report.pdf)
- [LaTeX report source](report/foundation_report.tex)
- [PowerPoint](presentation/foundation.pptx) and [slide PDF](presentation/foundation.pdf)
- [Rehearsal script](presentation/rehearsal.md) and genuine GUI GIF in `presentation/media/`
- [Assignment compliance and QA evidence](docs/final_compliance.md)
- Submission package: `dist/Foundation_Simulation_Submission.zip`

```bash
.venv/bin/pip install -r requirements-delivery.txt
MPLCONFIGDIR=/tmp/foundation-matplotlib .venv/bin/python scripts/analyze_tipping_investigation.py
./scripts/build_delivery.sh
.venv/bin/python scripts/validate_delivery.py
```

Install the LaTeX build tools on Ubuntu with
`sudo apt install texlive-latex-recommended texlive-latex-extra texlive-fonts-recommended lmodern latexmk zip`.
Edit `report/foundation_report.tex` for report content and `report/author.txt`
for its author identity. The build script compiles the two-page A4 report with
LaTeX and refreshes the submission ZIP, using the existing PowerPoint and slide
PDF. It does not regenerate the presentation or its animated GIF.
To compile only the report, run `cd report && latexmk -pdf foundation_report.tex`.

Optional GUI recapture needs a
local display and `.venv/bin/python scripts/capture_demonstration.py
/home/adam/tools/NetLogo-6.4.0-64`.
No university upload is performed.
