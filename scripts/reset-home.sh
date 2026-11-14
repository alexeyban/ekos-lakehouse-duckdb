#!/bin/bash
# Back to before step 1: the demo's EKOS home (project, ledger, pipeline, marts) is moved aside to
# $EKOS_DEMO_STATE/trash/home-<time> (same disk, so the move is instant), never deleted, so an earlier run can still be read.
set -euo pipefail
: "${EKOS_HOME:?}" "${EKOS_DEMO_STATE:?}"
if [[ -d "$EKOS_HOME" ]]; then
  mkdir -p "$EKOS_DEMO_STATE/trash"
  dest="$EKOS_DEMO_STATE/trash/home-$(date +%Y%m%dT%H%M%S)"
  mv "$EKOS_HOME" "$dest"
  echo "moved the demo home to $dest"
else
  echo "no demo home at $EKOS_HOME"
fi
