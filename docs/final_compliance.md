# Final assignment compliance audit

Specification: `docs/Assignment 1.pdf`, pages 1–4, Collective Intelligence,
Autumn 2026 (Tamás Takács). Final experiment: `experiments/tipping_confirmatory.xml`.
The original delivery plan is numbered Stage 8; the requested final work is Stage 9.
Its historical 7×7 / 450-tick reporting design is superseded by the measured
5×3 / 1,000-tick confirmation. Historical evidence remains separate.
Audit date: 11 October 2026.

| Category | Evidence and verification | Status / remaining limits |
| --- | --- | --- |
| Originality and Modeling (12) | `model/foundation.nlogo`: three interacting breeds; regenerating demand, degrading technology and evolving routes; saturating conversion, state-dependent admission, political hysteresis and reversible five-tick leverage. Complete ODD in Info and report page 1. Cumulative stages 1–6 runtime checks passed. | PASS for inspected requirements. Original fictional rules rather than a library reskin; independent similarity assessment remains the instructor's responsibility. |
| Implementation Quality (8) | Modular setup/go/helpers; 64×64 world wraps both axes; nine exact sliders, setup/go-once/go, twelve monitors, three time series and religion histogram. Current GUI exports `presentation/media/interface-{0000,0500,1000}.png` visually inspected: controls legible, plots populated, histogram visible, agents and control colors distinct. | PASS for source, runtime and inspected interface. Physical mouse interaction with buttons, live Info-tab navigation and save/reopen in the student's NetLogo environment remain recommended manual checks. |
| Experimentation (12) | Final XML: traders {8,12,16,20,24} × attractiveness {.6,.8,1}; twenty repetitions, seeds 500001–500300, 1,000 ticks. `scripts/validate_delivery.py` independently checks every fixed setting, run ID, cell count, raw hash, t intervals for control and kingdom-count means, Wilson intervals for widespread probability. Annotated heatmap and three genuine regime traces appear on report page 2. | PASS. df=19 for confirmation; duration pilot corrected to df=4 for five observations. Intervals estimate simulation variability, not empirical uncertainty. |
| Analysis and Interpretation (5) | Separate duration pilot, factorial screen and adaptive boundary search justify the chosen grid (`results/tipping_point_investigation/README.md`). Report distinguishes continuous mean, threshold-crossing probability and ≥50% operational classification; favorable settings, transient near-boundary behavior, fictional rules and fresh-seed future validation are disclosed. | PASS for documented scientific interpretation; does not establish a mathematical phase transition or persistent widespread control from terminal values. |
| Presentation (3) | `presentation/foundation.pptx` and `.pdf`: six identical slide layouts, classroom-sized result labels; genuine 21-frame GUI GIF embedded on slide 3, with measured stills in both formats. `presentation/rehearsal.md` and PPTX notes target 5:30. All slides rendered and inspected; overlap defects corrected. | Artifacts PASS. Actual timing, clarity during live delivery, projector readability and PowerPoint GIF playback require student rehearsal. |

## Verification performed

All commands below completed successfully on the current model with NetLogo 6.4.0:

```bash
python3 scripts/check_model.py /home/adam/tools/NetLogo-6.4.0-64
python3 scripts/check_duration.py /home/adam/tools/NetLogo-6.4.0-64
python3 scripts/check_interface.py /home/adam/tools/NetLogo-6.4.0-64 /tmp/foundation-final-interface-audit
python3 scripts/validate_results.py results/raw/foundation_sweep.csv experiments/foundation_sweep.xml --production
MPLCONFIGDIR=/tmp/foundation-matplotlib .venv/bin/python scripts/analyze_tipping_investigation.py
.venv/bin/python scripts/capture_demonstration.py /home/adam/tools/NetLogo-6.4.0-64
.venv/bin/python scripts/build_delivery.py
.venv/bin/python scripts/validate_delivery.py --netlogo-home /home/adam/tools/NetLogo-6.4.0-64
```

- Cumulative checks covered agent construction, wrapping and travel, empty/extinct
  populations, state bounds, sale/mission separation, recruitment accounting,
  government cadence/hysteresis, each parameter endpoint, combined extremes,
  repeated setup, seed replay and display independence. The historical test
  fixture's explicit 450-tick runs are regression checks, not a new model default.
- Duration checks measured exact finite stops at 100/450/1,000/2,000, a 250-tick
  externally bounded unlimited prefix, mid-run slider isolation, setup capture,
  go-once at the limit, plot axes and matching seeded 450/1,000 prefixes.
- Interface plot audit passed: plotted, unplotted and changing-view traces are
  identical; plot values match raw metrics, histogram boundary counts include
  religion 1, all plots reset, and actual monitor reporters compile/evaluate.
- The historical experiment still validates as 980 runs, 49 cells ×20, tick 450.
  Its raw CSV was not overwritten or rerun.
- The confirmatory model, XML and CSV hashes still match the recorded provenance.
  Existing provenance's generic seed label is incorrect for the investigation;
  the hashed XML and measured seed column are authoritative. Historical sidecars
  remain intact; new wrapper provenance derives its label from the actual setup.
- GUI demonstration: settings exactly match the above-boundary representative
  seed 500207, every 50th tick from 0 to 1,000. All 21 captured control values
  match the recorded raw trajectory; final control is 19/30 with two kingdoms.
  View switching preserves control and go-once does not advance beyond 1,000.
  Capture metadata is `presentation/media/capture_provenance.json`.
- The report has exactly two A4 pages, both rendered and visually inspected;
  heatmap CIs and control trajectories use measured data and readable labels.
  All six presentation pages were rendered; every PPTX background image is
  pixel-identical to the corresponding PDF rendering. The additional GIF is
  intentionally animated in PPTX and represented by its initial poster in PDF.
- The ZIP contains exactly five required files, passes CRC checks, extracts
  successfully and matches repository files byte for byte. Its extracted model
  compiles without supplementary files. A one-cell/repetition copy of the final
  XML (same first-cell settings/setup/seed) runs to 1,000 with plots enabled and
  reproduces seed 500001's recorded outcomes. The full 300-run suite was not rerun.
- Python compilation passed. No agent prompts, local plans, Git metadata,
  virtual environment, caches or datasets are in the ZIP. Git changes are limited
  to scientific documentation, reporting corrections and final delivery artifacts.

## Before submission

1. Replace the permitted author placeholder in `report/author.txt`, rebuild and
   validate. Check any additional course authorship/AI declaration requirements.
2. Rehearse the six slides to approximately 5–6 minutes. Check GIF playback in
   PowerPoint slideshow mode; use the genuine GIF separately if needed.
3. Open the extracted `.nlogo` in the student's NetLogo 6.4.x GUI, click setup,
   go-once and go, inspect views/plots/Info, and import the final XML. Automated
   runtime and captured GUI checks do not replace local usability confirmation.
4. Upload the ZIP manually. No university-platform action was performed.

The assignment permits optional presentation but caps the score at 20/40 without
presenting. No score is predicted. The deliverable formats and automated checks
pass; author identity and live-presentation acceptance remain manual.

## Rebuild

```bash
.venv/bin/pip install -r requirements-delivery.txt
MPLCONFIGDIR=/tmp/foundation-matplotlib .venv/bin/python scripts/analyze_tipping_investigation.py
.venv/bin/python scripts/build_delivery.py
.venv/bin/python scripts/validate_delivery.py --netlogo-home /home/adam/tools/NetLogo-6.4.0-64
```

The builder reuses captured GUI media, generates the two-page report and six-slide
PPTX/PDF, and packages only the five required files. PowerPoint slide text uses
shared rendered layouts to preserve appearance; edit the builder to change it.
Speaker notes remain editable in PowerPoint. Recapture is optional and requires
JPype1 plus access to the local display.
