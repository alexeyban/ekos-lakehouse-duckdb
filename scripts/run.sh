#!/bin/bash
# Runs one demo command and keeps its record: runs/<date>/<NN>-<label>.txt holds the command as
# typed, its output, the exit code and the time it took. Every number in the README, the book and
# the video comes from these files.
#
#   scripts/run.sh <label> <command...>
set -uo pipefail
# dbt-duckdb and duckdb for the commands that run on the host (make venv): the same versions as the Dagster image.
[[ -n "${EKOS_DEMO_DATA:-}" ]] && export PATH="$EKOS_DEMO_DATA/venv/bin:$PATH"
label="${1:?label}"
shift
run_dir="${DEMO_RUN_DIR:-runs/$(date +%F)}"
mkdir -p "$run_dir"
n=$(find "$run_dir" -maxdepth 1 -name '*.txt' | wc -l)
log="$run_dir/$(printf '%03d' $((n + 1)))-${label}.txt"
{
  printf '$ %s\n' "$*"
  printf '# started %s\n\n' "$(date -u +%FT%TZ)"
} > "$log"
start=$(date +%s)
"$@" 2>&1 | tee -a "$log"
code=${PIPESTATUS[0]}
end=$(date +%s)
printf '\n# exit %s, %ss\n' "$code" "$((end - start))" >> "$log"
echo "→ $log (exit $code, $((end - start))s)"
exit "$code"
