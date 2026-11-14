#!/bin/bash
# Stops the demo's MCP server and waits until it has exited: a killed server holds its port until then,
# and a new one started earlier cannot bind (pass 2, step 8b).
set -euo pipefail
: "${EKOS_DEMO_DATA:?}"
pidfile="$EKOS_DEMO_DATA/mcp.pid"
[[ -f "$pidfile" ]] || exit 0
pid=$(cat "$pidfile")
if kill "$pid" 2>/dev/null; then
  for _ in $(seq 1 30); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
  kill -0 "$pid" 2>/dev/null && { echo "MCP server $pid did not stop" >&2; exit 1; }
fi
rm -f "$pidfile"
