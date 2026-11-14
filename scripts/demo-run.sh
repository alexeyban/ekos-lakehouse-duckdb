#!/bin/bash
# The whole demo from the command line, steps 1–9 in the order they depend on each other, every
# command logged by scripts/run.sh under $DEMO_RUN_DIR (default runs/<date>-pass<N>). The console
# and Superset run the same commands; this is the record the README, the book and the video use.
#
#   scripts/demo-run.sh             from the stack up (after `make demo-reset` for a clean pass)
#   scripts/demo-run.sh --from 6    resume at a step (the earlier ones done in this home)
#
# Step 4 needs the plan of step 5 (requirements are resolved against it), so 5 runs before 4.
# Nothing here decides for the analyst except what RUNLOG.md says the rehearsal decided: the
# review rules (scripts/step3-review.sh), the PII list (scripts/step3-items.sh), the three marts
# (project/marts/), and the answer to step 4's questions (the description file).
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . stack/demo.env; set +a
export IDEMPIERE_SRC="${IDEMPIERE_SRC:-$HOME/PycharmProjects/idempiere}"
export IDEMPIERE_DOCS="${IDEMPIERE_DOCS:-$EKOS_DEMO_DATA/src/idempiere-docs}"
from=0
[[ "${1:-}" == "--from" ]] && from="${2:?step}"
if [[ -z "${DEMO_RUN_DIR:-}" ]]; then
  n=1; while [[ -d "runs/$(date +%F)-pass$n" ]]; do n=$((n + 1)); done
  DEMO_RUN_DIR="runs/$(date +%F)-pass$n"
fi
export DEMO_RUN_DIR
LH=("$EKOS_LAKEHOUSE_BIN" --project idemduck)
L=("${LH[@]}" lakehouse)
BY="${DEMO_REVIEWER:-claude-agent (demo rehearsal)}"
MARTS=(sales_by_category_month open_receivables_by_age purchase_spend_by_vendor)
run() { scripts/run.sh "$@" >/dev/null; }
step() { echo "── step $1: $2"; }
at() { (( from <= $1 )); }

# The ledger, from build to commit. The console's Init & compile resolves with --force: an open
# identity conflict is listed for review instead of stopping the run.
compile_all() {  # label prefix
  run "$1-build" "${LH[@]}" build
  run "$1-recover" "${LH[@]}" recover
  run "$1-resolve" "${LH[@]}" resolve --force
  run "$1-compile" "${LH[@]}" compile
  run "$1-commit" "${LH[@]}" commit --yes
}

if at 0; then
  step 0 "the stack and the project"
  make demo-up project
fi

if at 1; then
  step 1 "analyse: code, documentation, the live database"
  compile_all step1
  run step1-database-test "${LH[@]}" database test idempiere-db
fi

if at 2; then
  step 2 "the source-estate documentation"
  run step2-docs "${L[@]}" docs generate
fi

if at 3; then
  step 3 "review and sign-off"
  scripts/step3-review.sh
fi

if at 5; then
  step 5 "the extraction plan (before step 4: requirements resolve against it)"
  run step5-plan "${L[@]}" plan
  run step5-extraction-show "${L[@]}" extraction show
  run step5-extraction-approve "${L[@]}" extraction approve --as "$BY" \
    --note "the proposed load modes, each with its reason"
  run step5-generate "${L[@]}" generate
fi

if at 4; then
  step 4 "requirements: one mart from plain words, two from descriptions"
  # The local model drafts from the words; EKOS resolves every term or asks back. The draft and
  # its questions are logged; the analyst's answer is the description file, used as written.
  run step4-draft-text "${L[@]}" requirements draft --mart sales_by_category_month \
    --text "revenue by product category and month" --as "$BY" || true
  for m in "${MARTS[@]}"; do
    run step4-draft-file "${L[@]}" requirements draft --mart "$m" --file "$PWD/project/marts/$m.md" --as "$BY"
    run step4-approve "${L[@]}" requirements approve --mart "$m" --as "$BY" --note "every term resolved"
  done
fi

if at 6; then
  step 6 "bronze and silver through Dagster"
  make orchestrator
  for _ in $(seq 1 60); do curl -sf -o /dev/null http://127.0.0.1:53200/server_info && break; sleep 5; done
  scripts/dagster-schedules-off.sh
  run step6-run "${L[@]}" run --wait
fi

if at 7; then
  step 7 "gold marts on DuckDB, reconciled with silver"
  for m in "${MARTS[@]}"; do
    run step7-propose "${L[@]}" marts propose --mart "$m"
    run step7-merge "${L[@]}" marts merge --mart "$m" --as "$BY" --note "generated from the approved requirement"
    run step7-build "${L[@]}" marts build --mart "$m" --wait
    run step7-reconcile "${L[@]}" marts reconcile --mart "$m"
  done
fi

if at 8; then
  step 8 "the marts in EKOS, then three questions in Superset"
  make project                                  # adds `gold` (the marts file) to the project
  compile_all step8
  run step8-database-test "${LH[@]}" database test gold
  scripts/step3-review.sh                       # the marts are an output: scoped out, re-signed
  make bi                                       # MCP server (warmed), Superset, its init
  run step8-ask-a python3 scripts/ask.py "Revenue by product category per month this year"
  run step8-ask-b python3 scripts/ask.py "Revenue by customer and product category this year" || true
  run step8-ask-c python3 scripts/ask.py "How many employees does each warehouse have?" || true
  # (b) needs the customer: a change to the mart, approved and rebuilt, then the question again.
  m=sales_by_category_month
  run step8b-edit "${L[@]}" requirements edit --mart "$m" --as "$BY" --term customer \
    --value "c_bpartner.name via c_invoiceline.c_invoice_id, c_invoice.c_bpartner_id" --dimension
  run step8b-approve "${L[@]}" requirements approve --mart "$m" --as "$BY" \
    --note "Ask could not answer revenue by customer: customer added as a dimension"
  run step8b-propose "${L[@]}" marts propose --mart "$m"
  run step8b-merge "${L[@]}" marts merge --mart "$m" --as "$BY" --note "customer added"
  run step8b-build "${L[@]}" marts build --mart "$m" --wait
  run step8b-reconcile "${L[@]}" marts reconcile --mart "$m"
  compile_all step8b
  scripts/mcp-stop.sh               # the server reads the ledger as it was at its start
  make mcp
  run step8-ask-b-after python3 scripts/ask.py "Revenue by customer and product category this year"
fi

if at 9; then
  step 9 "a dashboard, and whether it can be trusted today"
  run step9-ask-dashboard python3 scripts/ask.py --dashboard \
    "A dashboard for the CFO: revenue by product category per month, open receivables by customer, and purchase spend by vendor"
  run step9-sync "${L[@]}" dashboards sync
  run step9-status "${L[@]}" dashboards status
  run step9-publish-health "${L[@]}" dashboards publish-health
fi

run workflow-final "${LH[@]}" workflow status
echo "done: $DEMO_RUN_DIR"
