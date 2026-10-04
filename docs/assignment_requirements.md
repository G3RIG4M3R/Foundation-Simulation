# Assignment requirements and provenance

Source: Tamás Takács, *First Assignment — Agent-Based Modeling Task*, Collective
Intelligence, Autumn 2026, semester 2026/27/1, `Assignment 1.pdf`, four pages.
The original PDF is retained outside this repository. It is credited to Tamás
Takács (2026) under CC BY-NC-ND 4.0. This document summarizes the requirements;
the original assignment is authoritative.

## Model and interface (pages 1–2)

- An original phenomenon, research question, and hypothesis.
- A two-dimensional grid, wrapping on both axes, from 20×20 to 128×128.
- At least two interacting breeds, three agent attributes, three globals,
  one dynamic environment process, and one non-trivial mechanism.
- At least five adjustable controls; `setup`, `go-once`, and `go` buttons.
- At least three monitors/plots, including a time series and a distribution.
- Modular procedures and comments, with purpose, behavior, interactions, and
  parameters explained in the Info tab.

## Experiments and delivery (pages 2–4)

- Sweep two parameters over justified ranges, with 20 seed-varied repetitions
  per configuration and two outcome measures.
- Export CSV; calculate each cell's mean and 95% confidence interval.
- Include a heatmap or contour with uncertainty information and representative
  time series for the observed regimes. Identify any estimated tipping point.
- Submit one ZIP containing the self-contained `.nlogo`, BehaviorSpace `.xml`,
  and a PDF mini report of at most two pages: model summary followed by
  experiments, results, takeaway, and limitations.
- Presentation is planned. Deliver both PDF and PPTX; the assignment recommends
  5–6 minutes and 5–6 slides, including a GIF or short video demonstration.
  Without presenting, the maximum score is 20/40.

The scoring categories are originality/modeling (12), implementation (8),
experimentation (12), analysis (5), and presentation (3).

## Scientific choices and integrity

The 64×64 world, 31 planets, four kingdoms, 450-tick horizon, numerical rules,
and eventual 7×7 parameter grid are project choices, not assignment mandates.
The hypothesis does not guarantee a tipping point or a successful Foundation.

The PDF prohibits superficial library reskins and substantial overlap with
library models, past solutions, or other students' work. No Models Library
implementation is used. Preserve citations, licensing, and reproducible data.

Development uses AI assistance for repository setup, code, documentation, and
verification. The student must review and understand submitted work. The
supplied PDF does not specify an AI-use disclosure format; any additional
course or university policy still applies. This statement is not a claim that
the instructor has approved AI use.
