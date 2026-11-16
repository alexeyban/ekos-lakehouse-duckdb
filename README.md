# EKOS Lakehouse + DuckDB demo

An analyst takes an ERP she has never seen, [iDempiere](https://www.idempiere.org) on PostgreSQL, and
builds an Apache Iceberg lakehouse with gold marts in DuckDB and a CFO dashboard in Apache Superset. She
writes no pipeline code. On day two the ERP and the requirements change, and the lakehouse stays correct.

[EKOS](https://github.com/alexeyban/EKOS) is the control plane: it reads the ERP's code, its
documentation and its live database, and keeps what it learns in an evidence-backed ledger.
[EKOS Lakehouse](https://github.com/alexeyban/ekos-lakehouse) generates the pipeline from what a person
reviewed and signed. EKOS never moves a row. Everything runs on one machine, on open-source components.

**[RUNLOG.md](RUNLOG.md) is the real record**: every run, every number, every failure and every fix, in
order. Read it before trusting anything below.

## What it shows

**Day one, from nothing to a trusted dashboard**
1. Analyse iDempiere's code, documentation site and live database. No model calls; the database census
   equals what was compiled.
2. Review and sign six subjects: scope, personal data, conflicts, identity, write behaviour, glossary.
3. Extraction plan, approval, generated pipeline: extraction SQL, dbt models with tests, Dagster.
4. Three marts from the CFO's words. A local model drafts them; EKOS checks every term against the
   signed model and asks back when one is ambiguous.
5. Bronze and silver on Iceberg, each table reconciled with the source. Gold marts in one DuckDB file,
   each measure reconciled with silver before the file is published.
6. Superset with Ask (AI): one question answered, one refused, one answered after the analyst adds a
   dimension.
7. A dashboard whose header says whether the pipeline behind it is trusted, late or unverified.

**Day two, three changes**
- **A, an unannounced ERP update** (`make change-a`): a column added, one widened, one renamed, one
  dropped. The first two are applied; the other two pause only their own tables and become proposals
  that list what they affect, down to the dashboard chart. The dashboard turns unverified until a person
  decides.
- **B, a customization** (`make change-b`, [stack/source/custom](stack/source/custom/README.md)): two
  loyalty tables and a trigger. Only the difference is analysed and reviewed, and a fourth mart answers a
  loyalty question.
- **C, the CFO changes a number**: a measure added, then revenue redefined without credit memos.
  The before and after totals are shown, and the change is approved and dated.

## The stack

| Component | Role | Where |
|---|---|---|
| PostgreSQL 16 | iDempiere 12 source (GardenWorld + synthetic invoices for 2025–2026) | `127.0.0.1:55470` |
| SeaweedFS | S3 storage for Iceberg files | `127.0.0.1:58433` |
| Apache Polaris | Iceberg REST catalog | `127.0.0.1:58281` |
| Trino 483 | reads the source, writes bronze and silver | `127.0.0.1:58180` |
| dbt + Dagster | silver models on Trino, gold marts with dbt-duckdb; schedules | `127.0.0.1:53200` |
| DuckDB | one marts file, built beside the live one and swapped in after reconciliation | file |
| Superset 4.1.1 + EKOS module | dashboards and Ask (AI), [EKOS fork](https://github.com/alexeyban/ekos-superset/tree/ekos-4.1.1) | `127.0.0.1:18098` |
| EKOS console | the analyst's UI (local mode) | `127.0.0.1:18100` |
| EKOS MCP server | schema and SQL rules for Ask (AI), read-only | `127.0.0.1:8711` |

Every port is bound to loopback, and every credential in [stack/demo.env](stack/demo.env) is a local-only
default.

## Running it

You need Linux with Docker (Compose v2), git, `envsubst`, Python 3.12, a Rust toolchain (to build
ekos-lakehouse), and Ollama with `llama3` pulled (requirement drafts). iDempiere's full history is a few GB. Put the EKOS home on a fast disk: the first
analysis took 64 minutes on NVMe and over two hours on a SATA SSD.

```bash
make paths        # where everything goes; override in stack/local.env (copy stack/local.env.example)
make sources      # iDempiere, its docs site, ekos-lakehouse, the Superset fork, at the demo's commits
make lakehouse    # build ekos-lakehouse (skipped if it is on PATH)
make images       # the Dagster and Superset images
```

**The seed** is a `pg_dump -Fc` of an iDempiere 12 database with the GardenWorld sample company, placed
at `$EKOS_DEMO_DATA/seed/idempiere.dump` (`make seed` checks for it). It is not in this repository. Dump
the database of any iDempiere 12 installation right after its first start.
[stack/source/20-synthetic.sql](stack/source/20-synthetic.sql) adds this year's and last year's business
on top of it, deterministically. Every synthetic document's description starts with
`synthetic (ekos-lakehouse-duckdb)`.

Then:

```bash
make demo-up      # source, SeaweedFS, Polaris, Trino
make project      # the EKOS project in the demo's home, from project/ekos.toml.in
make demo-run     # steps 1–9 from the command line, every command logged under runs/<date>/
make orchestrator # Dagster over the generated pipeline (demo-run starts it at step 6)
export OPENCODE_API_KEY=...   # only for Ask (AI); see below
make bi           # the MCP server and Superset
```

`make demo-reset` takes everything down and moves the demo's EKOS home to `$EKOS_DEMO_STATE/trash`.
`make snapshot NAME=x` and `make restore NAME=x` save and restore the whole state, so day two can
start from the end of day one.

### The console instead of the command line

The video drives the same steps through the EKOS web console in local mode:

```bash
set -a; . stack/demo.env; . stack/paths.sh; set +a
EKOS_CONSOLE_MODE=local EKOS_CONSOLE_PORT=18100 "$EKOS_LAKEHOUSE_BIN" --project idemduck console start
"$EKOS_LAKEHOUSE_BIN" --project idemduck console open   # signs you in with a one-time code
```

The console comes with an EKOS installation. The recording ran it from an EKOS checkout
(`EKOS_CONSOLE_APP_DIR`, `EKOS_CONSOLE_UI_DIR`) with a fix that lets local mode record review decisions.
Until that fix is in an EKOS release, do step 3's review from the command line
(`scripts/step3-review.sh`, `scripts/step3-decide.sh`).

### Models

- **Steps 1–3 call no model.**
- **Requirement drafts** (step 4) use a local model through Ollama (`llama3`).
- **Ask (AI)** in Superset uses Claude Haiku 5.5 through [OpenCode Zen](https://opencode.ai/zen), which is
  metered. It needs `OPENCODE_API_KEY` in the shell that runs `make bi`; the compose file passes the
  variable's name, never its value. Use `EKOS_AI_MODEL_ZEN` for another model. Without a key, everything
  except Ask works.

## Repository layout

| Path | What |
|---|---|
| `stack/` | docker compose, the source's init scripts and synthetic data, Polaris, Trino, Superset config |
| `stack/paths.sh` | the only place paths are decided; `stack/local.env` overrides it |
| `stack/source/30-source-changes.sql`, `31-deletes.sql`, `custom/` | day two's changes A and B |
| `project/ekos.toml.in` | the EKOS project: three sources (code, docs, live database), semantics, lakehouse settings |
| `project/marts/` | the four mart descriptions, in words |
| `project/rules/`, `project/scope-in.txt` | the review decisions the rehearsal made, as stated rules |
| `scripts/` | `demo-run.sh` (steps 1–9), step 3 helpers, snapshots, schedules, `ask.py` |
| `RUNLOG.md` | every run, deviation, failure and fix |

## What is not shown, and what is open

- The analyst's clicks in the video were performed by a scripted browser (Playwright), not a person.
- A few steps are not in the console and run in a terminal: the platform setup, the git merges that
  approve a schema change, and the dashboard-state commands.
- Nothing wrote to the source during loads or reconciliation. The day-two changes ran between runs.
  Late commits and loading under concurrent writes were not tested. The delete audit for incremental
  tables is implemented in ekos-lakehouse but was not exercised here.
- The open findings are at the end of [RUNLOG.md](RUNLOG.md).

## Third-party code

iDempiere (GPL-2.0) and its documentation are cloned by `make sources`; neither is included here.
