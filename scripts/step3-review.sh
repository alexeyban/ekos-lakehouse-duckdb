#!/bin/bash
# Step 3 — review and sign-off, from the command line (the console's Review page runs the same
# commands). Every decision carries its reason; the rules are written out here so a reader can
# disagree with one. The deciding person is $DEMO_REVIEWER (`--as`).
#
#   scripts/step3-review.sh           decide, then sign off every subject
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . stack/demo.env; set +a
: "${DEMO_RUN_DIR:=runs/$(date +%F)}"; export DEMO_RUN_DIR
LH=("$EKOS_LAKEHOUSE_BIN" --project idemduck)
BY="${DEMO_REVIEWER:-claude-agent (demo rehearsal)}"
run() { scripts/run.sh "$@" >/dev/null; }

run step3-review-before "${LH[@]}" review list

# ── Scope: the sales, purchasing and receivables subset (plan, design decision 3) ───────────────
mapfile -t in_scope < <(grep -vE '^\s*(#|$)' project/scope-in.txt)
mapfile -t all_tables < <("${LH[@]}" review show scope --json | python3 -c '
import json, sys
for r in json.load(sys.stdin)["rows"]: print(r["facts"]["table"])')
# The published marts (step 8 adds their DuckDB file to the project) are this pipeline's output.
mapfile -t marts < <(find project/marts -name '*.md' -printf '%f\n' | sed 's/\.md$//')
out=(); outputs=()
for t in "${all_tables[@]}"; do
  if [[ " ${in_scope[*]} " == *" ${t,,} "* ]]; then continue; fi
  if [[ " ${marts[*]} " == *" ${t,,} "* ]]; then outputs+=("$t"); else out+=("$t"); fi
done
run step3-scope-in "${LH[@]}" review scope "${in_scope[@]}" --in --as "$BY" \
  --reason "sales, purchasing and receivables: the marts' subject (project/scope-in.txt)"
run step3-scope-out "${LH[@]}" review scope "${out[@]}" --out --as "$BY" \
  --reason "outside the sales, purchasing and receivables subset of this demo (project/scope-in.txt)"
if ((${#outputs[@]})); then
  run step3-scope-marts "${LH[@]}" review scope "${outputs[@]}" --out --as "$BY" \
    --reason "a gold mart this pipeline publishes (the DuckDB marts file): an output, never extracted again"
fi

# ── Conflicts: decided by rule (EKOS `annotate resolve --rule`, a dry run first) ────────────────
rule() {  # name, conflict_type, decision JSON, rationale → project/rules/<name>.json
  local file="$PWD/project/rules/$1.json"
  mkdir -p project/rules
  python3 -c 'import json,sys; print(json.dumps({"name": sys.argv[1], "rationale": sys.argv[4],
    "match": {"conflict_type": sys.argv[2]}, "decision": json.loads(sys.argv[3])}, indent=2))' "$@" > "$file"
  run "step3-rule-$1-dry" "${LH[@]}" annotate resolve --rule "$file"
  # a rule that matches nothing in this run (the dry run says so) is not applied: EKOS refuses an empty rule
  if grep -q ': 0 open conflict(s) matched' "$(ls -t "$DEMO_RUN_DIR"/*"step3-rule-$1-dry.txt" | head -1)"; then return 0; fi
  run "step3-rule-$1" "${LH[@]}" annotate resolve --rule "$file" --apply --as "$BY"
}
rule code-ahead model_column_missing '"both_valid"' \
  "The code is iDempiere's master (release iD13) and the database the iD11 seed: columns the code declares and the database lacks are migrations not yet applied. Each side describes its own release; the lakehouse reads the database."
rule code-ahead-tables model_table_missing '"both_valid"' \
  "Tables of later releases (iD13) the iD11 database has not been migrated to. Each side describes its own release."
rule no-model-class table_without_model '{"pick_source": "database"}' \
  "The table exists in the database. Translation (_trl), log and access tables have no generated model class in iDempiere; the database is the authority on what exists."
rule app-enforced mandatory_but_nullable '"both_valid"' \
  "iDempiere enforces 'mandatory' in the application (the model class), not with NOT NULL in the database. Both are true; the lakehouse types the column as the database does, nullable."
rule unused-branch code_vs_data '"both_valid"' \
  "The code handles a value the data does not hold today. Nothing contradicts: the branch is unused in this database, which the profile shows."

# ── Duplicate definitions: one at a time, the later migration script replaces the earlier ───────
while read -r id pick; do
  run "step3-duplicate" "${LH[@]}" conflicts resolve "$id" --pick "$pick" --as "$BY" \
    --note "a later migration script redefines the table; the latest definition is the one applied"
done < <("${LH[@]}" conflicts list --type duplicate_definition --status open --json | python3 -c '
import json, sys
for c in json.load(sys.stdin):
    # the last claim (scripts sort by name, which starts with the date) that holds the definition EKOS chose
    picks = [n for n, cl in enumerate(c["claims"], 1) if cl["value"] == c["chosen_by_ekos"]]
    if picks: print(c["id"], picks[-1])')

source scripts/step3-items.sh   # identity, relationships, PII: decided item by item (written after reading them)

# ── Sign-off: every subject, on the digest of what was shown ─────────────────────────────────────
run step3-review-decided "${LH[@]}" review list
mapfile -t subjects < <("${LH[@]}" review list --json | python3 -c '
import json, sys
d = json.load(sys.stdin)
for s in (d["subjects"] if isinstance(d, dict) else d): print(s["subject"])')
for s in "${subjects[@]}"; do
  digest=$("${LH[@]}" signoff show "$s" --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["digest"])')
  run "step3-signoff-$s" "${LH[@]}" signoff approve "$s" --digest "$digest" --as "$BY" \
    --note "demo rehearsal: decisions by rule, scripts/step3-review.sh"
done
run step3-workflow "${LH[@]}" workflow status
