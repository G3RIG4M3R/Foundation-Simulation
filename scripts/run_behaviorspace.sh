#!/usr/bin/env bash
# Usage: run_behaviorspace.sh NETLOGO_HOME XML EXPERIMENT CSV [THREADS]
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 scripts/run_behaviorspace.py "$@"
