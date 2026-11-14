#!/bin/bash
# The stack's named volumes, from the compose file (one source of truth for snapshot and restore).
set -euo pipefail
cd "$(dirname "$0")/.."
sed -n '/^volumes:/,$p' stack/docker-compose.yml | sed -n 's/^  \([a-z0-9-]*\):.*/\1/p'
