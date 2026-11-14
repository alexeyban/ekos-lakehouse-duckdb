#!/bin/bash
# Starts the generated code location's schedules (the opposite of dagster-schedules-off.sh): for
# chapter 6 and chapter 9, where the pipeline runs on its schedule, not by hand.
set -euo pipefail
url="${DAGSTER_URL:-http://127.0.0.1:53200}/graphql"
gql() { curl -sf "$url" -H 'content-type: application/json' -d "$1"; }
states=$(gql '{"query":"{ schedulesOrError(repositorySelector:{repositoryLocationName:\"definitions.py\", repositoryName:\"__repository__\"}) { ... on Schedules { results { name scheduleState { status } } } } }"}')
python3 -c '
import json, sys
for s in json.loads(sys.argv[1])["data"]["schedulesOrError"]["results"]:
    if s["scheduleState"]["status"] != "RUNNING":
        print(s["name"])' "$states" |
while read -r name; do
  gql "{\"query\":\"mutation { startSchedule(scheduleSelector: {repositoryLocationName: \\\"definitions.py\\\", repositoryName: \\\"__repository__\\\", scheduleName: \\\"$name\\\"}) { __typename } }\"}" >/dev/null
  echo "started schedule $name"
done
