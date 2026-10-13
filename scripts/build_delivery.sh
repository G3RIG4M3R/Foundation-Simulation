#!/usr/bin/env bash
# Compile the LaTeX report and package it with the existing presentation.
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/foundation-delivery.XXXXXX")"
trap 'rm -rf -- "$build_dir"' EXIT

cd "$repo_root/report"
if ! latexmk -pdf -interaction=nonstopmode -halt-on-error \
    -outdir="$build_dir" foundation_report.tex > "$build_dir/build.log" 2>&1; then
    cat "$build_dir/build.log" >&2
    exit 1
fi
cp "$build_dir/foundation_report.pdf" foundation_report.pdf

cd "$repo_root"
mkdir -p dist
zip -q "$build_dir/Foundation_Simulation_Submission.zip" \
    model/foundation.nlogo \
    experiments/tipping_confirmatory.xml \
    report/foundation_report.pdf \
    presentation/foundation.pptx \
    presentation/foundation.pdf
mv "$build_dir/Foundation_Simulation_Submission.zip" dist/
printf '%s\n' 'Built LaTeX report and five-file submission ZIP.'
