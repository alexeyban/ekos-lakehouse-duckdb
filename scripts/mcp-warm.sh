#!/bin/bash
# Superset's first call to EKOS (the compiled schema of the marts, `ekos_ossie_export`) reads the
# whole ledger when the MCP server is cold: about 35 s, longer than Superset waits (30 s). This
# makes that call once; the answer is then cached until the ledger changes.
set -euo pipefail
: "${EKOS_DEMO_DATA:?}"
token_file="$EKOS_DEMO_DATA/mcp.token"
for _ in $(seq 1 20); do
  curl -s -o /dev/null http://127.0.0.1:8711/mcp && break
  sleep 1
done
body='{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"ekos_ossie_export","arguments":{"status":"all","max_datasets":500,"database":"gold"}}}'
start=$(date +%s)
curl -sf -m 300 -o /dev/null -X POST http://127.0.0.1:8711/mcp \
  -H "Authorization: Bearer $(cat "$token_file")" -H 'content-type: application/json' \
  -H 'accept: application/json' -d "$body"
echo "mcp: warm ($(($(date +%s) - start)) s)"
