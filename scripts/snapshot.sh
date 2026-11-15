#!/bin/bash
# X12: the whole demo state as one directory, so a chapter-9 scenario can be re-taken from the end of
# chapter 8 in minutes instead of the two-hour build. Saved: the four stack volumes (source database,
# SeaweedFS objects, Polaris's catalog, Superset's metadata) and the demo's EKOS home (project, ledger,
# generated pipeline, Dagster's state, the marts file). The stack is stopped while it is saved, so every
# part is from the same moment, and started again afterwards.
#
#   scripts/snapshot.sh <name>       → $EKOS_DEMO_DATA/snapshots/<name>/
set -euo pipefail
cd "$(dirname "$0")/.."
name="${1:?usage: scripts/snapshot.sh <name>}"
[[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "a snapshot name is letters, digits, . _ -" >&2; exit 2; }
set -a; . stack/demo.env; set +a
export IDEMPIERE_SRC="${IDEMPIERE_SRC:-$HOME/PycharmProjects/idempiere}"
export IDEMPIERE_DOCS="${IDEMPIERE_DOCS:-$EKOS_DEMO_DATA/src/idempiere-docs}"
dest="$EKOS_DEMO_DATA/snapshots/$name"
[[ -e "$dest" ]] && { echo "$dest exists: choose another name" >&2; exit 1; }
compose=(docker compose -f stack/docker-compose.yml --env-file stack/demo.env --profile orchestrator --profile bi)
running=$("${compose[@]}" ps --services --status running | sort | tr '\n' ' ')

scripts/mcp-stop.sh
"${compose[@]}" stop
mkdir -p "$dest"
for v in $(scripts/volumes.sh); do
  docker run --rm -v "ekos-duckdemo_$v:/v:ro" -v "$dest:/out" alpine:3.20 \
    tar -C /v -cf "/out/volume-$v.tar" .
  echo "saved volume $v"
done
tar -C "$(dirname "$EKOS_HOME")" -cf "$dest/home.tar" "$(basename "$EKOS_HOME")"
echo "saved the EKOS home"
{ echo "taken $(date -u +%FT%TZ)"; echo "services $running"
  (cd "$dest" && sha256sum ./*.tar); } > "$dest/MANIFEST"
"${compose[@]}" up -d --wait $running
# The MCP server was stopped with the stack: Superset's Ask needs it again.
[[ " $running " == *" superset "* ]] && make --no-print-directory mcp
du -sh "$dest"
