# Foundation: Religion, Trade & Control

An original university agent-based modeling project inspired by Isaac Asimov's
Foundation. The research question is how missionary effectiveness and royal
intolerance affect stable, non-military influence over neighboring worlds.
Religion and technological dependency are distinct mechanisms. Any threshold
or regime change must be measured, not assumed.

Current status: repository and runtime preparation only. The Foundation model
has not been implemented, and no simulation results are available. The target
is a self-contained NetLogo 6.4.x `.nlogo` file.

| Directory | Purpose |
| --- | --- |
| `model/` | Self-contained Foundation model |
| `experiments/` | BehaviorSpace experiment definitions |
| `scripts/` | Runtime checks and, later, experiment/analysis tools |
| `tests/` | Reproducible checks and manual test protocol |
| `tests/evidence/` | Scientific validation evidence, when available |
| `results/raw/` | Unmodified measured experiment exports |
| `results/processed/` | Summaries derived from measured data |
| `results/figures/` | Figures derived from measured data |
| `report/` | Final report, at most two PDF pages |
| `presentation/` | Planned presentation in PPTX and PDF |
| `docs/` | Environment, assignment requirements, and model limitations |

Run the installation check using [environment instructions](docs/netlogo_environment.md).
See [assignment requirements](docs/assignment_requirements.md),
[model limitations](docs/model_limitations.md), and the
[verification protocol](tests/test_protocol.md). Empty directories are reserved
for future deliverables; they do not represent completed work.

The project retains its [MIT license](LICENSE). The instructor's assignment and
Asimov's fiction are separate sources, not covered by this project's license.
