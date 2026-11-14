#!/bin/bash
# The generated Dagster code location starts its schedules RUNNING (bronze hourly, maintenance).
# During a demo run they start loads between steps: a load writes run reports to the ledger, which
# clears the MCP server's answer cache, and a scheduled sync fails while step 3 is being re-signed.
# Stop both; the state is kept in DAGSTER_HOME (the project home), so a new container keeps it.
set -euo pipefail
url="${DAGSTER_URL:-http://127.0.0.1:53200}/graphql"
gql() { curl -sf "$url" -H 'content-type: application/json' -d "$1"; }
states=$(gql '{"query":"{ schedulesOrError(repositorySelector:{repositoryLocationName:\"definitions.py\", repositoryName:\"__repository__\"}) { ... on Schedules { results { name scheduleState { id selectorId status } } } } }"}')
python3 -c '
import json, sys
for s in json.loads(sys.argv[1])["data"]["schedulesOrError"]["results"]:
    st = s["scheduleState"]
    if st["status"] == "RUNNING":
        print(s["name"], st["id"].split("::")[0], st["selectorId"])' "$states" |
while read -r name origin selector; do
  gql "{\"query\":\"mutation { stopRunningSchedule(scheduleOriginId: \\\"$origin\\\", scheduleSelectorId: \\\"$selector\\\") { __typename } }\"}" >/dev/null
  echo "stopped schedule $name"
done
