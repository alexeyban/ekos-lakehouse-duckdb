#!/bin/bash
# Back to a snapshot taken with scripts/snapshot.sh. The current EKOS home is moved to
# $EKOS_DEMO_STATE/trash (never deleted); the stack volumes are replaced by the saved ones.
# Then the services that were running at the snapshot start again, and the MCP server.
#
#   scripts/restore.sh <name>
set -euo pipefail
cd "$(dirname "$0")/.."
name="${1:?usage: scripts/restore.sh <name>}"
set -a; . stack/demo.env; set +a
export IDEMPIERE_SRC="${IDEMPIERE_SRC:-$HOME/PycharmProjects/idempiere}"
export IDEMPIERE_DOCS="${IDEMPIERE_DOCS:-$EKOS_DEMO_DATA/src/idempiere-docs}"
src="$EKOS_DEMO_DATA/snapshots/$name"
[[ -f "$src/MANIFEST" ]] || { echo "no snapshot at $src" >&2; exit 1; }
(cd "$src" && grep -E '^[0-9a-f]{64} ' MANIFEST | sha256sum -c --quiet) || { echo "snapshot $name is damaged" >&2; exit 1; }
compose=(docker compose -f stack/docker-compose.yml --env-file stack/demo.env --profile orchestrator --profile bi)

scripts/mcp-stop.sh
"${compose[@]}" down               # containers only; the volumes are replaced below
scripts/reset-home.sh
for v in $(scripts/volumes.sh); do
  docker volume rm -f "ekos-duckdemo_$v" >/dev/null
  docker volume create --label com.docker.compose.project=ekos-duckdemo \
    --label com.docker.compose.volume="$v" "ekos-duckdemo_$v" >/dev/null
  docker run --rm -v "ekos-duckdemo_$v:/v" -v "$src:/in:ro" alpine:3.20 tar -C /v -xf "/in/volume-$v.tar"
  echo "restored volume $v"
done
mkdir -p "$(dirname "$EKOS_HOME")"
tar -C "$(dirname "$EKOS_HOME")" -xf "$src/home.tar"
echo "restored the EKOS home"
services=$(sed -n 's/^services //p' "$src/MANIFEST")
"${compose[@]}" up -d --wait $services
[[ " $services " == *" superset "* ]] && make --no-print-directory mcp
echo "restored $name"
