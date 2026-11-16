# EKOS Lakehouse + DuckDB demo. Local-only credentials: stack/demo.env; paths: stack/paths.sh
# (defaults under ~/.local/share/ekos-duckdemo, overridden by a git-ignored stack/local.env).
#
#   make sources      clone iDempiere, its docs, ekos-lakehouse and the Superset fork at the demo's commits
#   make lakehouse    build the ekos-lakehouse binary from that checkout (unless one is on PATH)
#   make images       build the Dagster and Superset images the stack runs
#   make demo-up      the stack: source, SeaweedFS, Polaris, Trino (Dagster and Superset later)
#   make project      the EKOS project in the demo's home, from project/ekos.toml.in
#   make demo-run     steps 1–9 from the command line, every command logged under runs/<date>/
#   make demo-reset   everything down, volumes and the demo home dropped: back to before step 1
#   make snapshot NAME=x / make restore NAME=x   the whole state after chapter 8, for chapter 9 (X12)

SHELL := /bin/bash
include stack/demo.env
$(foreach kv,$(shell bash stack/paths.sh --print),$(eval export $(kv)))
export

COMPOSE := docker compose -f stack/docker-compose.yml --env-file stack/demo.env
LH      := $(EKOS_LAKEHOUSE_BIN) --project idemduck

# The commits the recorded demo ran on (2026-11-15/16).
IDEMPIERE_REF  := 3355eb5fc9403c3827fcd8caf8eb92f78319430e
DOCS_REF       := d105057e3f381493654ceb1148af169801dd6bbc
LAKEHOUSE_REF  := 875a5a9
SUPERSET_REF   := ekos-4.1.1

.PHONY: paths sources lakehouse images seed venv demo-up project orchestrator bi mcp demo-run demo-reset status snapshot restore change-a change-b schedule-fast schedule-hourly

paths:           ## print the paths this machine uses
	@bash stack/paths.sh --print

# clone <url> <dir> <ref>: a full clone (EKOS reads the git history), checked out at <ref>
clone = test -d $(2)/.git || git clone $(1) $(2); git -C $(2) fetch -q origin && git -C $(2) checkout -q $(3)

sources:         ## the four checkouts, at the commits the demo ran on (iDempiere is a few GB with history)
	$(call clone,https://github.com/idempiere/idempiere.git,$(IDEMPIERE_SRC),$(IDEMPIERE_REF))
	$(call clone,https://github.com/idempiere/idempiere.github.io.git,$(IDEMPIERE_DOCS),$(DOCS_REF))
	$(call clone,https://github.com/alexeyban/ekos-lakehouse.git,$(EKOS_LAKEHOUSE_SRC),$(LAKEHOUSE_REF))
	$(call clone,https://github.com/alexeyban/ekos-superset.git,$(SUPERSET_SRC),$(SUPERSET_REF))

lakehouse:       ## ekos-lakehouse from the checkout (Rust toolchain needed); skipped when EKOS_LAKEHOUSE_BIN exists
	test -x $(EKOS_LAKEHOUSE_BIN) || cargo build --release --manifest-path $(EKOS_LAKEHOUSE_SRC)/Cargo.toml -p ekos-lakehouse
	$(EKOS_LAKEHOUSE_BIN) --version

images:          ## the Dagster image (ekos-lakehouse/deploy/dagster) and Superset with the EKOS module (the fork's Dockerfile.ekos)
	docker build -t $(DAGSTER_IMAGE) $(EKOS_LAKEHOUSE_SRC)/deploy/dagster
	docker build -t $(SUPERSET_IMAGE) -f $(SUPERSET_SRC)/Dockerfile.ekos $(SUPERSET_SRC)

seed:            ## the iDempiere 12 seed (GardenWorld), dumped once from a running iDempiere database
	@test -s $(EKOS_DEMO_DATA)/seed/idempiere.dump || { echo "put a pg_dump -Fc of iDempiere at $(EKOS_DEMO_DATA)/seed/idempiere.dump"; exit 1; }

venv:            ## dbt-duckdb and duckdb on the host, for `lakehouse gold publish`
	test -x $(EKOS_DEMO_DATA)/venv/bin/dbt || { python3 -m venv $(EKOS_DEMO_DATA)/venv && \
	  $(EKOS_DEMO_DATA)/venv/bin/pip install -q dbt-duckdb==1.11.1 duckdb==1.5.6 dbt-trino==1.10.6 trino==0.340.0 pyyaml; }
	@# RFC 0260: a mart edit's gates load these on the host (they are never auto-installed there)
	$(EKOS_DEMO_DATA)/venv/bin/python -c "import duckdb; duckdb.sql('INSTALL httpfs; INSTALL iceberg')"

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
	scripts/mcp-stop.sh
	$(COMPOSE) --profile orchestrator --profile bi down -v
	scripts/reset-home.sh

snapshot:        ## the stack volumes and the EKOS home under $(EKOS_DEMO_DATA)/snapshots/$(NAME)
	scripts/snapshot.sh $(NAME)

restore:         ## back to a snapshot: the current home goes to trash, the volumes are replaced
	scripts/restore.sh $(NAME)

SOURCE_SQL := $(COMPOSE) exec -T lh-source psql -U postgres -d idempiere -v ON_ERROR_STOP=1

change-a:        ## chapter 9 A: the ERP update (A1–A4) and the deleted drafts (A5), in the source only
	$(SOURCE_SQL) < stack/source/30-source-changes.sql
	$(SOURCE_SQL) < stack/source/31-deletes.sql
	@echo "applied in the source; the next scheduled run (or: $(LH) lakehouse run --wait) finds it"

change-b:        ## chapter 9 B: the loyalty customization (two tables, a routine) and its backfill
	$(SOURCE_SQL) < stack/source/custom/migration/postgresql/202611201000_XX-LOYALTY.sql
	$(SOURCE_SQL) < stack/source/custom/backfill.sql

schedule-fast:   ## the take's schedule (every 10 minutes): re-planned and approved with the reason, schedules on
	scripts/schedule.sh fast

schedule-hourly: ## back to the project's hourly schedule
	scripts/schedule.sh hourly
