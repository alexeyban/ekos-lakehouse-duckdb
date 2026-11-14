#!/bin/bash
# The pipeline's schedule, changed the way the plan says it is changed: `bronze-schedule` in the
# project's ekos.toml, the extraction plan proposed again and approved with the reason (the schedule is
# part of the plan's digest), the pipeline regenerated, Dagster recreated, and its schedules started.
#
#   scripts/schedule.sh fast      every 10 minutes, for a recorded take (the video says so)
#   scripts/schedule.sh hourly    back to the project's own schedule
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . stack/demo.env; set +a
export IDEMPIERE_SRC="${IDEMPIERE_SRC:-$HOME/PycharmProjects/idempiere}"
export IDEMPIERE_DOCS="${IDEMPIERE_DOCS:-$EKOS_DEMO_DATA/src/idempiere-docs}"
what="${1:?usage: scripts/schedule.sh fast|hourly}"
case "$what" in
  fast) cron="*/10 * * * *"; why="every 10 minutes for the recorded take (the project's own schedule is hourly)" ;;
  hourly) cron="0 * * * *"; why="back to the project's hourly schedule after the take" ;;
  *) echo "fast or hourly" >&2; exit 2 ;;
esac
toml="$EKOS_LH_PROJECT/ekos.toml"
grep -q '^bronze-schedule = ' "$toml" || { echo "$toml has no bronze-schedule line" >&2; exit 1; }
sed -i "s|^bronze-schedule = .*|bronze-schedule = \"$cron\"|" "$toml"
L=("$EKOS_LAKEHOUSE_BIN" --project idemduck lakehouse)
BY="${DEMO_REVIEWER:-claude-agent (demo rehearsal)}"
scripts/run.sh schedule-plan "${L[@]}" plan >/dev/null
scripts/run.sh schedule-approve "${L[@]}" extraction approve --as "$BY" --note "schedule: $why" >/dev/null
scripts/run.sh schedule-generate "${L[@]}" generate >/dev/null
make --no-print-directory orchestrator
for _ in $(seq 1 60); do curl -sf -o /dev/null http://127.0.0.1:53200/server_info && break; sleep 5; done
scripts/dagster-schedules-on.sh
echo "schedule: $cron ($why)"
