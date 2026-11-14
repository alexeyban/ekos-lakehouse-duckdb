# EKOS Lakehouse + DuckDB demo. Paths and local-only credentials: stack/demo.env.
#
#   make demo-up      the stack: source, SeaweedFS, Polaris, Trino (Dagster and Superset later)
#   make project      the EKOS project in the demo's home, from project/ekos.toml.in
#   make demo-run     steps 1–9 from the command line, every command logged under runs/<date>/
#   make demo-reset   everything down, volumes and the demo home dropped: back to before step 1

SHELL := /bin/bash
include stack/demo.env
export

COMPOSE := docker compose -f stack/docker-compose.yml --env-file stack/demo.env
LH      := $(EKOS_LAKEHOUSE_BIN) --project idemduck
IDEMPIERE_SRC  ?= $(HOME)/PycharmProjects/idempiere
IDEMPIERE_DOCS ?= $(EKOS_DEMO_DATA)/src/idempiere-docs
export IDEMPIERE_SRC IDEMPIERE_DOCS

.PHONY: seed venv demo-up project orchestrator bi mcp demo-run demo-reset status

seed:            ## the iDempiere 12 seed (GardenWorld), dumped once from a running iDempiere database
	@test -s $(EKOS_DEMO_DATA)/seed/idempiere.dump || { echo "put a pg_dump -Fc of iDempiere at $(EKOS_DEMO_DATA)/seed/idempiere.dump"; exit 1; }

venv:            ## dbt-duckdb and duckdb on the host, for `lakehouse gold publish`
	test -x $(EKOS_DEMO_DATA)/venv/bin/dbt || { python3 -m venv $(EKOS_DEMO_DATA)/venv && \
	  $(EKOS_DEMO_DATA)/venv/bin/pip install -q dbt-duckdb==1.11.1 duckdb==1.5.6 dbt-trino==1.10.6 trino==0.340.0 pyyaml; }

demo-up: seed
	$(COMPOSE) up -d --wait lh-source lh-seaweedfs lh-polaris lh-trino
	$(COMPOSE) ps --format '{{.Service}}\t{{.Status}}'

project: venv    ## the project in the demo's EKOS home (never in the iDempiere checkout)
	test -f $(EKOS_LH_PROJECT)/ekos.toml || $(EKOS_LAKEHOUSE_BIN) project add idemduck --source $(IDEMPIERE_SRC)
	envsubst '$$IDEMPIERE_SRC $$IDEMPIERE_DOCS $$EKOS_LH_PROJECT $$EKOS_DEMO_DATA' < project/ekos.toml.in > $(EKOS_LH_PROJECT)/ekos.toml
	mkdir -p $(EKOS_LH_PROJECT)/pipeline/.lakehouse/marts
	@# step 8's `database add gold` wrote into ekos.toml: once the marts are published, add it again
	test ! -f $(EKOS_LH_PROJECT)/pipeline/.lakehouse/marts/marts.duckdb || $(LH) database add gold --kind duckdb \
	  --owner gold_idem --profile p1 --path $(EKOS_LH_PROJECT)/pipeline/.lakehouse/marts/marts.duckdb
	$(EKOS_LAKEHOUSE_BIN) project list

orchestrator:    ## Dagster over the generated pipeline (after step 7's generate)
	$(COMPOSE) --profile orchestrator up -d --force-recreate lh-dagster   # the binary is a bind-mounted file: a rebuilt one needs a new container

mcp:             ## EKOS's MCP server for Superset (read-only tools; token from demo.env)
	@umask 077; printf '%s' "$(EKOS_MCP_TOKEN)" > $(EKOS_DEMO_DATA)/mcp.token
	nohup $(LH) mcp serve --http 127.0.0.1:8711 --token-file $(EKOS_DEMO_DATA)/mcp.token \
	  > $(EKOS_DEMO_DATA)/mcp.log 2>&1 & echo $$! > $(EKOS_DEMO_DATA)/mcp.pid
	scripts/mcp-warm.sh

bi: mcp          ## Superset (EKOS fork) on 127.0.0.1:18098
	$(COMPOSE) --profile bi up -d superset
	scripts/superset-init.sh

demo-run:
	scripts/demo-run.sh

status:
	$(COMPOSE) --profile orchestrator --profile bi ps --format '{{.Service}}\t{{.Status}}'

demo-reset:      ## stops everything and drops the stack's volumes and the demo's EKOS home
	-test -f $(EKOS_DEMO_DATA)/mcp.pid && kill $$(cat $(EKOS_DEMO_DATA)/mcp.pid) && rm -f $(EKOS_DEMO_DATA)/mcp.pid
	$(COMPOSE) --profile orchestrator --profile bi down -v
	scripts/reset-home.sh
