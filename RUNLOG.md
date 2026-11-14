# Run log

Every deviation, failure and fix of the demo runs, in order. Command output is in `runs/<date>-<pass>/`.

## 2026-11-14, rehearsal (pass 1)

- 11:16 Synthetic business for 2025-01-01 .. 2026-11-13 added to the source (`stack/source/20-synthetic.sql`):
  GardenWorld's own documents are from 2002–2003, so "this year" had no data. Sales 276 + 298 invoices,
  purchases 72 + 75, receipts/payments with allocations; every generated document's description starts
  with "synthetic (ekos-lakehouse-duckdb)". The first draft made purchases larger than sales; purchase
  quantities were reduced before it was applied.
- Step 1 `build` failed after 538 s (`runs/2026-11-14-pass1/001-step1-build.txt`): the project declared the
  marts file as a `[[databases]]` entry before step 7 had created it, and a live database that cannot be
  read stops the build. Fix in the demo's config: the marts database is added at step 8 with `database add`.
  EKOS finding (minor): for a missing file the message is "is not a DuckDB file"; it should say it does not exist.
- Step 1 `resolve` stopped on one identity conflict (`dual` is a view in some scripts and a table in others).
  The console's Init & compile runs `resolve --force` and `commit --yes` (EKOS `web/api/app/commands.py`):
  the conflict is listed and stays open for review. The command-line run now does the same.

## 2026-11-14 — the EKOS home moves to the NVMe disk

- Step 1 `commit` took 8260 s (2 h 18 min) with the home on /mnt/discd (SATA SSD), against 14 min for
  the same commit on NVMe in the scratch run: it writes 145,982 objects and waits on the disk.
- The home (1005 MB) was copied to /var/tmp/ekos-duckdemo/home (`cp -a`, `diff -rq` empty; only an
  old run log names the old path). `stack/demo.env` points EKOS_HOME and EKOS_LH_PROJECT there;
  `make project` re-rendered ekos.toml; Superset was recreated for the new marts mount.
- The old copy at /mnt/discd/ekos-duckdemo/home is kept until it is no longer needed.
- Step 3, first try: `annotate resolve --rule` takes a rule FILE; its help shows the JSON shape, so the
  script passed the JSON inline ("File name too long"). Rules are now files in project/rules/.
  (Minor EKOS finding: the help text reads as if the JSON itself were the argument.)
- Minor EKOS finding: conflict claims from the PostgreSQL source carry the path `oracle://idempiere-db/…`.
- `--rule` path: a `--project` run changes into the workspace root, so a relative path misses; the script passes an absolute one.
- Step 3 done (take 4 of the script): 6 of 6 subjects signed, 0 blocking. Rules decided 163 + 9 + 152 + 114
  conflicts; `unused-branch` matched none (no code_vs_data finding in this run) and is skipped when its dry
  run says so, since EKOS refuses a rule that decides nothing. Scope out narrowed conflicts to 54 in scope.
- Steps 2, 5, 4: `lakehouse docs generate` 309 pages; `lakehouse plan` 42 planned / 0 refused / 860 out of
  scope; extraction approved (28 incremental, 14 full, 26 masked); `generate` wrote 271 files.
  Step 4: `sales_by_category_month` drafted from the words "revenue by product category and month" by
  llama3 (61 s, local): the draft mixed order lines with invoice lines and filtered on a column that
  does not exist (`c_orderline.isinvoiced`); EKOS asked back. Answered with `requirements edit`
  (invoiced revenue, invoice month, category by name, completed customer invoices); EKOS then asked
  which of 3 key paths reaches c_invoice → `via c_invoiceline.c_invoice_id`. The other two marts from
  project/marts/*.md, resolved at once. All three approved.
- Step 6, first run (Dagster run 7e04db8b): `lakehouse__sync` failed, "the source model is not signed off".
  Cause in the demo's compose: lh-dagster did not mount the iDempiere checkout, so inside the container
  `--project idemduck` could not open its workspace root. Fix: the two source checkouts mounted read-only
  at the paths ekos.toml names. (EKOS finding, minor: the sync step reported "not signed off" while the
  real error, a missing workspace root, was only visible by running the command by hand.)
- Step 6, second run (e7d1a2cc): same error. The mount was needed but not the cause: definitions.py adds
  `--project` only when `.lakehouse/project.json` exists (an installed project) or EKOS_LH_PROJECT_NAME is
  set; without either it ran against the project directory's ekos.toml with a state directory that holds
  no sign-off. Fix in compose: EKOS_LH_PROJECT_NAME=idemduck.
- Step 6, third run (3618040b): sign-off passed; sync stopped on EKOS_SOURCE_PASSWORD not set in the container. Compose now passes it (the read-only role's local-only password).
- Step 6, fourth run (7df69f9f): the sync and every load ran; 18 steps succeeded, 25 failed "not green".
  c_invoice: V1 counts equal (729/729), V3 row digests equal, V2 min/max "differ" on description,
  poreference, createfrom, generateto, totallines, grandtotal. Cause (EKOS product code,
  migrate-validate `dialect::aggregate_query`): V2 takes min/max of each column's canonical TEXT form;
  PostgreSQL orders text by the database collation (en_US.utf8: punctuation ignored at the first level),
  Trino by code point. On the source: min(totallines::text) = '100.00', with COLLATE "C" = '10.80'.
  Same data, different order. STOPPED here for the user's decision (fix in EKOS, or a C-collated source).
- Fixed in EKOS a1d4ce0e (V2 min/max with COLLATE "C" on PostgreSQL); lakehouse rebuilt against it (cargo update -p ekos, uncommitted). Manual reconcile: c_invoice and c_payment green, control fired. Step 6 re-run follows.
- The first re-run after the fix (f9ef6192) still ran the OLD binary: a bind-mounted file keeps its inode, and the recreate command had failed silently (compose without IDEMPIERE_SRC, output cut by tail). `make orchestrator` now always recreates the container.
- Step 6, run b19ec5d0 (new binary): every bronze step green (42 tables + sync); `silver` failed: 255 dbt
  source tests errored "Schema 'bronze_idem_adempiere' does not exist", 1111 skipped. Cause: the generated
  dbt profile takes EKOS_LH_TRINO_HOST/PORT (default 58080), not ekos.toml's trino-url; 58080 here is the
  shared ekos-lakehouse stack's Trino. Checked its query history (261 queries since 15:35:36): reads only,
  no create/insert/drop/alter — nothing written there. Fix in compose: EKOS_LH_TRINO_HOST/PORT = 58180.
  (Lakehouse finding: the dbt profile should follow trino-url; the default port reaches whatever runs on 58080.)
- Step 6 run d883383f: SUCCESS, 45/45 steps; dbt 1366 nodes: PASS 1364, WARN 2, ERROR 0.
- Step 7, first build (5c1f2507): `gold_duckdb` failed, "starting /mnt/discd/ekos-duckdemo/venv/bin/dbt: No
  such file": ekos.toml named the HOST venv's dbt, and the build runs in the Dagster container. Fix: no
  dbt/python paths in ekos.toml (the defaults `dbt`/`python3` on PATH: the image has the same versions);
  scripts/run.sh puts the demo venv first on PATH for commands run on the host. marts.duckdb unchanged
  (the build went to marts.next.duckdb, as designed).
- Step 7 done: three marts proposed (nothing invented), merged, built through Dagster into DuckDB, reconciled
  with silver: revenue 319628.15; open_amount 47430.84 / 75 invoices; spend 116469.96 / 151 invoices —
  each mart total equal to silver (totals include the seed's 2002–2003 rows).
- EKOS bb2a21f2: code-vs-database conflicts compare only the application databases (holding a model table); claim paths name the engine. Lakehouse rebuilt against it. Re-commit, re-review, re-sign follow.
- Re-review after bb2a21f2: conflicts back to 152 tables without a model (the 3 marts no longer conflict);
  the engine-named claim paths reopened the rule-decided conflicts (21 blocking in scope): the same
  rules decided them again; the 3 mart tables scoped out as "a gold mart this pipeline publishes";
  6 of 6 signed. `lakehouse plan` again gives digest a8145c82 = the approved plan (the "changed since"
  was the plan read while the marts were undecided in scope). SonarCloud on bb2a21f2: OK, 0 issues.
- Step 8: `database add gold --kind duckdb --owner gold_idem` (census 3 = compiled 3); MCP server on :8711
  (38 tools). scripts/ask.py posts to Superset's /api/v1/ekos_ai/sql as the page does (JWT + CSRF token).
  Ask (a), try 1: EKOS's first call timed out at 30 s (MCP server still loading; warm: 1.7 s).
  Try 2: EKOS found the mart, qwen2.5-coder:3b wrote SQL EKOS checked, DuckDB refused the unqualified
  table (default schema `main`): the demo's superset_config lacked EKOS_AI_REQUALIFY (and the schema
  change needed a Superset restart). Set EKOS_AI_REQUALIFY = True.
- Ask (a) answered: 65 rows, sum 165396.45 = the mart's 2026 revenue. Ask (c) "How many employees does
  each warehouse have?" → status impossible (no table covers it). Ask (b) "Revenue by customer and
  product category this year" → status ok with 36 WRONG rows: the model joined sales_by_category_month to
  open_receivables_by_age on month (fan-out); EKOS flagged L002, the fork showed it as a warning only.
  User's decision: L002 blocks in the fork + the gold change shown by CLI. Fork fix a3ba59219c (branch
  ekos/fanout-join-blocks, 185 tests pass); image ekos-duckdemo/superset:4.1.1-ekos-a3ba592.
- Ask (b) with the fork fix → status impossible, nothing ran. Gold change by CLI: requirements edit
  (customer = c_bpartner.name via c_invoiceline.c_invoice_id, c_invoice.c_bpartner_id), approve, propose
  (24 atoms, nothing invented), merge, build, reconcile (319628.15 = silver); ledger refreshed (commit
  433 s); step 3 stayed signed. Ask (b) again → ok: one mart, no join, 36 rows, sum 165396.45 (2026 revenue).
- Two Ask tries failed "EKOS did not answer in time": ekos_ossie_export reads the whole ledger cold
  (34.5 s, Superset waits 30 s; warm 0.01 s), and Dagster's bronze_schedule (RUNNING by default, hourly)
  ran at 16:00 (failed: sync refused while step 3 was stale, the gate) and at 17:00 (success); its
  ledger writes cleared the MCP cache. Both schedules stopped (Dagster GraphQL stopRunningSchedule);
  `make mcp` now warms the export once. (EKOS finding: ossie export cost grows with the whole ledger.)
- Step 9: [extensions.lakehouse.dashboards] added (Superset as maria, password by variable name, database
  1 = marts, schema gold_idem, superset-header); `make project` re-adds `gold` when the marts file exists.
  Ask --dashboard built "CFO Dashboard" (id 1, 3 charts). `dashboards sync` recorded it; `status` said
  UNVERIFIED: every bronze/silver table "has no lakehouse fact". Cause (lakehouse health/src/dashboard.rs):
  a mart's reads are bare names (c_invoice), the facts are keyed adempiere.c_invoice. Fixed (a bare name
  = the one table of that name in the layer; two schemas → still unverified), 2 tests. Also re-recorded
  the RFC 0255 pins for the PostgreSQL reconcile SQL (EKOS a1d4ce0e's COLLATE "C"; 8 reconcile lines
  only). `status` → trusted, data as of 2026-11-14 17:01 UTC; `publish-health` wrote the certification
  ("EKOS (pipeline health)") and the header onto the dashboard.
