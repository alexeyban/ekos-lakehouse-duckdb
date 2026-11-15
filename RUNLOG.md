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
- 2026-11-14T17:50:53Z make demo-reset (user approved): 3 volumes removed, home moved to /var/tmp/ekos-duckdemo/trash/home-20261114T185047. Pass 2: scripts/demo-run.sh.
- 2026-11-14T19:06:40Z pass 2 step 4: approve refused, 1 open question (which key path reaches c_invoice). project/marts/sales_by_category_month.md lacked the answer pass 1 gave by hand; added `via c_invoiceline.c_invoice_id` to month. Resumed with --from 4.
- 2026-11-14T19:23:56Z pass 2 step 7: sales_by_category_month revenue 308227.75 (= silver), pass 1 had 319628.15. Same synthetic document counts (276/298 sales, 72/75 purchases) but other amounts: the product pick `ORDER BY random() LIMIT 1` drew a random number per row in scan order, so a different plan gave different products. The seed comment's 'every reset produces the same rows' was not true. Fixed in stack/source/20-synthetic.sql (one draw, product by id at that offset; template picks ordered). Pass 2 keeps its data; the fix is checked by two scratch restores.
- 2026-11-14T20:05:00Z pass 2 step 8b: `make mcp` failed (curl exit 7): the killed MCP server still held 127.0.0.1:8711, the new one could not bind, the warm-up reached the dying one. Fix in scripts/demo-run.sh: stop_mcp waits for the old process to exit. Rest of step 8 and step 9 run by hand with the script's commands.
- Pass 2 step 8: llama3 read "this year" as 2023 — Ask (a) 0 rows; Ask (b) after the customer change summed
  from 2023-01-01 (2025 + 2026). The fork's prompts never gave the date (pass 1 guessed 2026). With the
  user's decision, fixed in the fork: ekos-superset 1269830f9e (`<today>` in the prompt; relative periods
  from CURRENT_DATE; test). Image ekos-duckdemo/superset:4.1.1-ekos-1269830. Re-asked: (a) 65 rows, (b) 36
  rows, both summing to 159387.15 = the source's 2026 sales (c_invoice issotrx='Y', 2026, totallines).
  The first (a) re-ask timed out: steps 9's commands had changed the ledger, so the MCP server's export
  was cold again (the known 35–41 s ossie export against Superset's 30 s).
- Pass 2 results: step 6 Dagster run ac92d65d SUCCESS in 470 s, first try. Step 7 reconciled: revenue
  308227.75, open 44861.72 / 75, spend 111695.18 / 151 (amounts differ from pass 1: the synthetic data
  fix above). Step 8 (c) impossible; (b) before the change refused by L001 (no column customer).
  Step 9: CFO Dashboard trusted, data as of 2026-11-14 19:13 UTC, certification written.
  Workflow: 1, 3, 4, 5, 7 done; 2 partial (not published); 6 partial (40 built, 2 warn tests).
- Synthetic data fix checked: the seed restored into two scratch postgres:16 containers, the new
  20-synthetic.sql applied to each — identical rows (sales 567 invoices, totallines 323352.80; purchases
  143, 93821.45; md5 over every synthetic invoice and invoice line equal). The counts differ from pass 1/2
  (one random draw per product pick instead of one per candidate row shifts the sequence); the next pass
  is the first on these rows. Note: pass 1 applied the script by hand to a running source, pass 2 from the
  init script, which is the likeliest reason their plans (and products) differed.

## 2026-11-14, plan v2 (chapter 9) groundwork

- Polaris kept its catalog in memory: any restart (or a restore of the other volumes) lost every Iceberg
  table registration. Now `relational-jdbc` on a small PostgreSQL (`lh-polaris-db`, volume `polaris-data`),
  realm bootstrapped on first start (`POLARIS_PERSISTENCE_AUTO_BOOTSTRAP_TYPES`). Its schema must exist
  before Polaris connects (`stack/polaris/00-schema.sql`; without it: "no schema has been selected to create
  in"). Tested in scratch containers: a catalog survives a Polaris restart. Takes effect from the next reset.
- X12: `make snapshot NAME=x` / `make restore NAME=x` (scripts/snapshot.sh, restore.sh): stack stopped,
  4 volumes + the EKOS home as tars with a SHA-256 manifest under $EKOS_DEMO_DATA/snapshots/; restore moves
  the current home to trash. Not run yet (needs a stack with persistent Polaris).
- Scenario A: `stack/source/30-source-changes.sql` (A1 c_invoiceline.promocode added; A2 c_bp_group.value
  40 → 60; A3 c_order.poreference renamed po_reference; A4 m_product_category.name dropped, CASCADE drops the
  one view rv_fact_adaxa) and `31-deletes.sql` (A5: the 30 draft invoices, 66 lines, tax). Column choice:
  a type change needs a column no view uses (most iDempiere columns are in views; c_bp_group.value is not);
  for the drop, m_product_category.name (1 dependent view, read by the sales mart's category dimension and
  the dashboard's revenue chart) rather than c_bpartner.name (23 views, used by all three marts).
  The synthetic script now also makes 30 draft customer invoices (copies of the latest 30, docstatus DR);
  no mart reads drafts. Both scripts tested on a scratch restore; 30 of 748 invoice keys = 4.0% (< 5%).
- Scenario B: `stack/source/custom/` (migration 202611201000_XX-LOYALTY.sql: xx_loyalty_account,
  xx_loyalty_txn, xx_loyalty_post + trigger xx_loyalty_award on c_invoice; backfill.sql). Tested: backfill
  293 transactions / 18172 points; completing a draft posts one more (the trigger needed
  `SET search_path = adempiere` on the functions: a session without it did not find xx_loyalty_post).
- `make change-a`, `make change-b`.
- 2026-11-14T21:07:41Z user approved: make demo-reset (pass 2 volumes removed, home to trash), pass 3 with persistent Polaris and the drafts, then make snapshot NAME=chapter8.
- Pass 3 stopped in step 1 (user decision): the synthetic data gets 12 completed AR credit memos (doc type
  118) in 2026, so scenario C2 ("revenue must exclude credit memos") changes the total. Each credits one
  unit of the first line of a synthetic sales invoice; stored positive as iDempiere does; settled (ispaid Y).
  Their lines add 423.15 to 2026 sales lines on day one. Tested twice on scratch restores: identical.
  Also: demo.env names the variables the DuckDB edit gates read (RFC 0260), `make venv` installs DuckDB
  1.5.6's httpfs and iceberg extensions on the host (only 1.5.5's were there).
- Pass 3 restarted from `make demo-reset`.

## 2026-11-14/15, pass 3 (persistent Polaris, drafts and credit memos, Superset 1269830)

- All steps ran from `make demo-reset` without a hand fix. Step 1 commit 4164 s (pass 2: 2981 s). Step 6
  Dagster run 509 s. Step 7 reconciled: revenue 324286.35, open 36545.09 / 69, spend 100770.45 / 147.
- Step 8 (a): `DATE_TRUNC('YEAR', CURRENT_DATE)`, 66 rows, 173193.40 = 2026 invoice lines 172770.25 + the
  credit memos' 423.15 (counted as revenue: scenario C2's subject). (c) impossible. (b) after the customer
  change: 36 rows, 173193.40.
- Step 8 (b) before the change: **status failed**. The model's first draft joined two marts on month;
  EKOS's check rejected it. The repair kept a join between the marts (on DATE_TRUNC of both months) and
  wrote `'Unknown' AS customer` — a literal standing in for the column the mart lacks — and passed the
  check; DuckDB then refused `DATE_TRUNC('YEAR', '2026-01-01')`. Had it run, the answer would have been
  wrong. Product finding (fork/EKOS): a join between tables with no declared join, and a literal named as
  the column the question asks for, are not blocked. Pass 1: wrong fan-out rows; pass 2: refused (L001);
  pass 3: failed — three passes, three outcomes.
- Step 9: CFO Dashboard trusted, data as of 2026-11-14 23:21 UTC. Workflow 1, 3, 4, 5, 7 done.
- `make snapshot NAME=chapter8`: 71 s, 1.5 GB. After the stack restart Polaris kept the catalog
  (silver c_invoice 760 rows = 748 invoices + 12 credit memos). The snapshot did not restart the MCP
  server; fixed in scripts/snapshot.sh.

## 2026-11-15, chapter 9 scenario A dry run (from snapshot chapter8; ekos-lakehouse c4b0c51, RFC 0260)

Commands and output in runs/2026-11-15-chapter9/.
- `make change-a`, then `lakehouse run --wait` (the job the schedule starts; run df5bd78a, 520 s, SUCCESS):
  - A1 `c_invoiceline.promocode`: applied automatically (commit "apply 1 safe change(s)").
  - A2 `c_bp_group.value` varchar(40) → (60): **not reported**. The plan keeps `character varying(40)`;
    both map to Iceberg `varchar`, and the change is not recorded either. Finding (lakehouse): a
    source-only widening should be applied and listed as `widening`.
  - A3 `c_order.poreference` → `po_reference`: `rename`, proposed, c_order paused; impact "no gold mart
    reads it".
  - A4 `m_product_category.name` dropped: `drop`, proposed, table paused. Impact (RFC 0260 X1): gold
    `sales_by_category_month` dimension `product_category`, and dashboard `CFO Dashboard` (1) chart
    `Revenue by Product Category`. The silver line says "no compiled silver column reads it": the
    silver lookup reads a ledger compiled from the pipeline repository, which this project does not compile.
  - Dashboard: trusted → **unverified**, "silver/bronze adempiere.m_product_category is waiting for a schema
    change to be approved".
  - A5: the 30 drafts left silver with the next full load (c_invoice 760 → 730, 0 drafts).
    c_invoice, c_invoiceline and c_invoicetax load in full, so `lakehouse deletes` has no delete plan for
    them ("deletes leave with the replacement"). Key buckets and tombstones would need deletes on an
    incremental table with a delete plan (e.g. m_productprice).
- Maria's decision on A4: `requirements edit` product_category := m_product_category.value (search key),
  approve. Approval of the source changes = merging the proposal branches: the second merge conflicted in
  `.generated.json` (both branches built on the same HEAD); `git merge --abort`, `lakehouse sync` rebuilt
  it on the new HEAD (its impact now "no gold mart reads it"), merged.
- Mart: propose, merge; then `lakehouse run --wait` (run 8e432855, 510 s, SUCCESS: sync resumed both
  tables, bronze, silver, gold publish). Reconcile: revenue 324286.35 = silver. `dashboards sync` +
  `status`: CFO Dashboard **trusted** again, data as of 2026-11-15 00:41 UTC. Scenario A end to end, with the
  findings above (A2 silent, silver impact empty, A5 by full load, second proposal conflicts until a sync).

## 2026-11-15, chapter 9 scenario C dry run (from `make restore NAME=chapter8`, 1 min 55 s; runs/2026-11-15-chapter9c/)

- Restore checked: source has m_product_category.name again, 760 invoices in source and silver, pipeline at
  aab3274, dashboard trusted.
- C1 (additive) `marts edit --step 11 --add-measure quantity --definition "sum of c_invoiceline.qtyinvoiced"`:
  gates in DuckDB (RFC 0260 X7: "DuckDB plans the edited mart", grain unique in DuckDB), reconciliation in
  Trino, totals (X8): revenue no change, quantity 9402 (new). The plan's C1 ("discount amount and percent")
  is not expressible: GardenWorld's synthetic lines have no discount; quantity stands in.
- C2 (modifying) `--add-filter "c_doctype.docbasetype <> 'ARC'"`: EKOS asked which of 18 key paths reaches
  c_doctype, then which of 2; answered `via c_invoiceline.c_invoice_id, c_invoice.c_doctype_id`. Preview:
  revenue before 324286.35 → after 323863.20 (−423.15 = the 12 credit memos), quantity 9402 → 9390 (−12).
  Recorded with `--confirm`.
- Approve, propose, merge, build (Dagster 40 s), reconcile: revenue 323863.20, quantity 9390, both = silver.
- Difference from the plan: C1 is not "applied without a review": every edit, additive too, makes the
  requirement need approval again (the project sets require-signoff / require-plan-approval).
  Not tried: Ask about revenue afterwards "saying since when" (the 8b path refreshes the ledger and MCP).

## 2026-11-15, chapter 9 scenario B dry run (from `make restore NAME=chapter8`; runs/2026-11-15-chapter9b/)

- `make change-b`: migration + backfill (305 transactions, 18214 points).
- `lakehouse sync` failed: "permission denied for table xx_loyalty_account" — ekos_ro had SELECT on the
  tables of day one only. Demo fix: `GRANT SELECT` on the two tables and `ALTER DEFAULT PRIVILEGES … GRANT
  SELECT ON TABLES TO ekos_ro` (now in stack/source/10-idempiere.sh). Product finding: one unreadable new
  table fails the whole sync (in a scheduled run, every table).
- After the grant, sync **applied** both as `new_table`. Plan step 1 expected them to wait outside the
  approved scope; sync adds new tables to the deployed plan at once, also with require-plan-approval.
- `source add custom` + build/recover/resolve/compile/commit (X3): 6 + 345 + 15 + 44 + 460 s ≈ 14.5 min
  (the first analysis's commit alone: 4164 s). Ledger: Procedure xx_loyalty_post, Trigger xx_loyalty_award;
  `interaction matrix --table xx_loyalty_txn`: routine:xx_loyalty_post read + insert (declared).
- Review (X4): scope, conflicts, write-behaviour stale; a stale sign-off states its delta ("2 added, 0
  removed, 0 changed — e.g. xx_loyalty_account"); conflicts said "2 added, 33 changed". `review show` has no
  flag that lists only the changed items (`--undecided` lists old dismissed items).
- The demo's step-3 rules put the new tables out of scope. `review scope … --in`, then **before the scope
  was signed again, `lakehouse plan` planned every table of the source** (161 full, 741 incremental, out of
  scope 0): with the scope sign-off stale, the plan used no scope. Product finding: plan with a stale scope
  should keep the last signed scope or refuse. Nothing was approved from it. Scope-in also made conflicts and
  write-behaviour stale (signed again, 0 blocking).
- Plan (X5): exactly the two loyalty tables "new since the approval" (incremental, deletes audited weekly);
  the approval is still of the whole plan. Approve, generate.
- First run (a67dfc5e) FAILED in silver: Dagster still had the code location from before `generate`, so no
  bronze assets for the new tables, and dbt's silver models for them found no bronze table. `make
  orchestrator` (reload), second run b192a781 SUCCESS 460 s. Finding (demo + docs): after `generate`
  reload the code location; the silver build should not include models whose bronze has never loaded.
- Fourth mart `loyalty_points_by_group_month` from project/marts: resolved (4 terms, 0 questions), approved,
  proposed, merged, built (Dagster), reconciled: points 18214, transactions 305 = silver.
  Not done in this dry run: the chart on the dashboard.

## 2026-11-15, the chapter 9 gaps fixed, checked from `make restore NAME=chapter8` (runs/2026-11-15-fixes/)

Binary: ekos-lakehouse rfc0260 working tree built against the local EKOS working tree (RFC 0260 §2.5, not
committed yet); Superset image `4.1.1-ekos-l013` (the fork blocks L013). Restore 1 min 37 s.
- Gap 1 (Ask guard): chapter8 is after step 8b, so the mart has `customer` and (b) answered correctly 3 of 3
  (`SUM(revenue)` by customer and category from `sales_by_category_month`, `CURRENT_DATE`). The pass 3
  repair SQL through `sql check --dialect duckdb`: L002 (the `DATE_TRUNC` join), L013 (`'Unknown' AS
  customer`), L014 (`DATE_TRUNC('YEAR', '2026-01-01')`) — all three now reported; the fork blocks L002/L013.
- Gap 2: `make change-b` without the grant, `lakehouse sync`: "no changes" (exit 0; before: permission
  denied, sync failed). `lakehouse plan`: `REFUSED adempiere.xx_loyalty_account` / `xx_loyalty_txn`, "the
  source user may not read it (no SELECT privilege)", 42 tables planned.
- Gap 4, first half: after the grant, sync: "no changes" — the review never saw the two tables, so they are
  outside the signed scope (before: applied as `new_table` at once).
- Re-analysis (`source add custom`, build → commit): recover 325 s, commit 423 s, all exit 0.
- Gap 3: `review scope xx_loyalty_account xx_loyalty_txn --in` (scope sign-off now stale), `lakehouse
  plan`: 42 tables planned, "until then the plan keeps the deployed plan's tables" (before: all 902).
- Scope signed again (digest fb76c9b1…, the dry run's). Conflicts and write-behaviour were stale again: the
  no-model-class rule decided the 2 new `model_class` items, both signed again.
- Gap 4, second half: `lakehouse sync`: `waiting new_table adempiere.xx_loyalty_account` / `xx_loyalty_txn`,
  "not built before the plan has it" (require-plan-approval). `plan`: 44 tables; approved; `generate`.
- Gap 7: `generate` printed "Dagster reloaded the pipeline's code location"; `lakehouse run --wait` with no
  `make orchestrator`: run fb83afb7 SUCCESS 460 s (before: the first run failed in silver).
- Gap 8: C1 `marts edit --add-measure quantity`: "additive edit — the approval carries forward"; requirement
  `approved`; propose, merge, build, reconcile with no second approval: revenue 324286.35, quantity 9402, both
  = silver.
- Gaps 5 and 6 (`make change-a` on top of the above, then `lakehouse sync`): `applied widening
  adempiere.c_bp_group.value` (lock now `character varying(60)`), `applied new_nullable_column …promocode`;
  rename and drop proposed. Impact: "silver `adempiere__c_order.poreference` reads it", "silver
  `adempiere__m_product_category.name` reads it — tests: not_null", plus the gold dimension and the CFO
  Dashboard chart. The committing sync reloaded Dagster; `lakehouse run --wait` SUCCESS 470 s.
- State left: chapter 8 + B (loyalty tables loaded) + C1 + A's sync (two proposals open). `make restore
  NAME=chapter8` goes back. The earlier binary is kept as `target/release/ekos-lakehouse.c4b0c51`.

## 2026-11-15, the remaining chapter 9 items (runs/2026-11-15-fixes/ 042–059)

- First try of two proposals merged back to back (on the state above): still `CONFLICT in .generated.json`. Two
  causes: every proposal changes the manifest line of `lakehouse.lock.json`, and of the schema's single silver
  YAML. And a product bug found on the way: `generate --from-lock` (the installer's upgrade step) rendered silver
  **without step 3's masks** (my run committed unmasked models for ad_user, c_payment and others; the proposals
  then masked them again). Fixed in ekos-lakehouse (lock out of the manifest, one YAML per model, `--from-lock`
  takes the last plan's masks); stack restored to chapter8.
- `generate --from-lock` on chapter8: 44 files (42 per-model YAML, the per-schema one removed, the manifest), no
  silver SQL changed. `make change-a`, `sync` (2 proposals), both merged one after the other: no conflict.
- X5: whole plan approved; `extraction change` c_tax and c_uom to full; `approve --table adempiere.c_tax`;
  `generate`: "held: adempiere.c_uom: its change is not approved; the deployed version is kept", c_tax full,
  c_uom still incremental.
- X4: `review show scope --changed`: "nothing changed since the sign-off"; after `review scope c_job --in`:
  `[changed] c_job …`.
- Stack restored to chapter8 afterwards.

### 2026-11-15 — committed
- EKOS 973e0f7f (L013/L014, `review show --changed`, RFC 0260); Superset fork 63a734da01 (blocks L013).
  The image `4.1.1-ekos-l013` is retagged `4.1.1-ekos-63a734d` (same image) and the compose file names it.
