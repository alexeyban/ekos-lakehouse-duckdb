#!/bin/bash
# Where the demo keeps its files on this machine. The one place the paths are decided: the Makefile
# imports them (`paths.sh --print`), the scripts source this file, docker compose gets them from the
# environment those two set.
#
# Defaults put everything under ${XDG_DATA_HOME:-~/.local/share}/ekos-duckdemo. To use other disks,
# copy stack/local.env.example to stack/local.env (git-ignored) and set what differs; a variable
# already set in the environment wins over both. Paths must not contain spaces.
_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
[[ -f "$_here/local.env" ]] && . "$_here/local.env"

# Seed dump, Python venv, source checkouts, snapshots, the MCP token: read often, written rarely.
: "${EKOS_DEMO_DATA:=${XDG_DATA_HOME:-$HOME/.local/share}/ekos-duckdemo}"
# The EKOS home (ledger, pipeline repository, marts) is written heavily: put it on the fastest disk
# (a first commit took 64 min on NVMe and over 2 h on a SATA SSD).
: "${EKOS_DEMO_STATE:=$EKOS_DEMO_DATA/state}"
: "${EKOS_HOME:=$EKOS_DEMO_STATE/home}"
: "${EKOS_LH_PROJECT:=$EKOS_HOME/data/default/idemduck}"

# The source checkouts `make sources` clones (the project reads the first two; images are built
# from the last two).
: "${IDEMPIERE_SRC:=$EKOS_DEMO_DATA/src/idempiere}"
: "${IDEMPIERE_DOCS:=$EKOS_DEMO_DATA/src/idempiere-docs}"
: "${EKOS_LAKEHOUSE_SRC:=$EKOS_DEMO_DATA/src/ekos-lakehouse}"
: "${SUPERSET_SRC:=$EKOS_DEMO_DATA/src/ekos-superset}"

# The ekos-lakehouse binary: on PATH, else the one `make lakehouse` builds. An absolute path, since
# the Dagster container bind-mounts it.
if [[ -z "${EKOS_LAKEHOUSE_BIN:-}" ]]; then
  EKOS_LAKEHOUSE_BIN="$(command -v ekos-lakehouse || true)"
  : "${EKOS_LAKEHOUSE_BIN:=$EKOS_LAKEHOUSE_SRC/target/release/ekos-lakehouse}"
fi

# Dagster runs as the host user, because it writes the project's ledger.
: "${EKOS_LH_UID:=$(id -u)}"
: "${EKOS_LH_GID:=$(id -g)}"

# Images the stack runs; `make images` builds these tags.
: "${DAGSTER_IMAGE:=ekos-duckdemo/dagster:1.13.26}"
: "${SUPERSET_IMAGE:=ekos-duckdemo/superset:4.1.1-ekos}"

_vars=(EKOS_DEMO_DATA EKOS_DEMO_STATE EKOS_HOME EKOS_LH_PROJECT IDEMPIERE_SRC IDEMPIERE_DOCS
  EKOS_LAKEHOUSE_SRC SUPERSET_SRC EKOS_LAKEHOUSE_BIN EKOS_LH_UID EKOS_LH_GID DAGSTER_IMAGE SUPERSET_IMAGE)
export "${_vars[@]}"
if [[ "${1:-}" == "--print" ]]; then
  for _v in "${_vars[@]}"; do printf '%s=%s\n' "$_v" "${!_v}"; done
fi
unset _here _v _vars
