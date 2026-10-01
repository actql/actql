# dbt-to-ActQL compatibility probe

This probe checks whether a real dbt project can compile models that use `ref()`
and Pipe syntax into text that ActQL's existing public Local and HTTP paths
accept unchanged.

The probe submits each compiled file byte for byte as dbt wrote it. Nothing
re-renders or rewrites it. It records the stage where each case stops.

It is a manual probe, not a CI job:

```sh
npm ci
npm run probe:dbt-compat
```

The run needs Python 3.13 (`ACTQL_PROBE_PYTHON`, default `python3.13`), network
access for the wheel installation, a MoonBit toolchain to pack the Client
packages, and `openssl`.

Evidence goes to `_build/dbt-compat-evidence/<time>-<id>/`. It is written before
the disposable environment is removed. The environment holds the Python venv,
the dbt project copies and the ActQL installation, about 357 MiB.

A failed run keeps both the evidence and the environment. Setting
`ACTQL_TEST_PRESERVE_SCRATCH=1` keeps the environment after a successful run.

## What these results cover

The results hold only for this combination:

| Component | Version / identity |
|---|---|
| Python | 3.13.11 (Homebrew, darwin-arm64) |
| dbt-core | 1.11.15 |
| dbt-duckdb | 1.11.0 |
| dbt-adapters / dbt-common / duckdb (Python) | 1.24.5 / 1.39.0 / 1.5.6 |
| Lock | `requirements.txt`: 54 wheels, `--require-hashes --only-binary :all:` |
| ActQL | The revision under test. Packed `@actql/*` tarballs are hashed in `summary.json` and printed at the end of each run. |
| Node | 22.23.2 |

The probe makes no claim about dbt Fusion / v2, the `dbt` or `dbt-oss`
packages, other adapters, other dbt versions, `dbt run`, or materialization.

## Result

The table shows the reference run at the PR head on darwin-arm64. Every case
had the same outcome on Local and HTTP.

| Case | Model | Format | Outcome | Where it stops |
|---|---|---|---|---|
| `pipe-ref` | `FROM ref |> WHERE id > 1 |> SELECT id, amount` | `aql-text` | Named Result. Rows, schema, NULL and stream completion match. | — |
| `pipe-ref-ordered` | the same with `|> ORDER BY id DESC` | `aql-text` | Named Result in the expected order | — |
| `select-cte` (control) | `with c as (select … from ref where amount > 10) select … from c` | `sql` | Named Result | — |
| `ephemeral-select-into-select` | SELECT model over a SELECT ephemeral | `sql` | Named Result | — |
| `ephemeral-pipe-into-pipe` | Pipe model over a Pipe ephemeral | `aql-text` | `ClientProgramInvalidInput` | ActQL parsing: `Expected SELECT` at 3:1, the Pipe `FROM` inside dbt's injected CTE body |
| `ephemeral-select-into-pipe` | Pipe model over a SELECT ephemeral | `aql-text` | `ClientProgramInvalidInput` | ActQL parsing: `Expected SELECT` at 4:3, the Pipe `FROM` after dbt's injected `with … )` |
| `default-quoting` | `pipe-ref` compiled without the `quoting:` setting | `aql-text` | `ClientProgramInvalidInput` | ActQL parsing: `Expected identifier` at 1:6, at `"memory"` |
| `infer` | `FROM ref |> INFER \`model-task:risk.v1\` …` | `aql-text` | `ClientProgramUnsupported` | ActQL checking. The text parses and lowers. At this revision the shared checker has no `infer` owner, so it refuses the lowered `stages.1.steps.1` (the `infer` step) as an unsupported implementation. |

### Raw `dbt compile` output that runs on ActQL

With the settings below, raw `dbt compile` output reaches an ActQL Named Result.
The second column gives the setting for each requirement.

| Requirement | Setting |
|---|---|
| Identifier quoting | Project-level `quoting: {database: false, schema: false, identifier: false}`. The default dbt-duckdb quoting renders `"memory"."main"."stg_orders"`. ActQL lexes `"…"` as JSON text and rejects it as an identifier. All names in this project are lowercase ASCII, so leaving them unquoted does not change what they name. |
| Relation binding | The source profile's `queryAliases` binds the exact rendered name `memory.main.stg_orders`. The `memory` part comes from the compile-only `path: ':memory:'` in `profiles.yml`. That database is never opened and is not ActQL's data. The synthetic rows are in a separate DuckDB file that the source profile names. |
| Model shape | Either a Pipe model whose relations are all `ref()`s to non-ephemeral models, or a SELECT model, with or without CTEs and SELECT ephemerals. |
| Format | `aql-text` for Pipe models and `sql` for SELECT models. The caller chooses the format. dbt does not record it. |

### Unsupported cases

These cases are unsupported, and the boundary is ActQL parsing or checking, not
dbt.

- **Any ephemeral consumed by a Pipe model.** dbt injects ephemerals as
  `with __dbt__cte__x as (\n<body>\n) <model>`. ActQL accepts only a SELECT
  after a `WITH` list, so a Pipe model after the prefix is refused.
  - Minimal reproduction: `WITH c AS (SELECT id FROM memory.main.stg_orders) FROM c |> SELECT id`, which gives `Expected SELECT` at 1:51.
  - Control: the same text with `SELECT id FROM c` reaches a Named Result.
- **A Pipe ephemeral body.** A CTE body must be a SELECT.
  - Minimal reproduction: `WITH c AS (FROM memory.main.stg_orders |> SELECT id) SELECT id FROM c`, which gives `Expected SELECT` at 1:12.
- **dbt's default quoting.**
  - Minimal reproduction: `FROM "memory"."main"."stg_orders" |> SELECT id`, which gives `Expected identifier` at 1:6.
  - Controls: the unquoted form and ActQL's own `` `memory`.`main`.`stg_orders` `` both reach a Named Result.
- **INFER.** Parsing and lowering accept the dbt-rendered text. The shared
  checker at this revision does not implement `infer` and refuses it as
  unsupported. The repository states this in `src/query_program/infer_test.mbt`
  ("INFER Program admission is not common checker or execution support").
  - Minimal reproduction: the one-line INFER text in `cases.json` (`infer-plain`). It stops at the same lowered step as the dbt model.
  - A missing ModelTask provider is a separate, untested condition. The probe
    installs none, and the refusal happens before any provider would be
    consulted. Installing a provider would not, by itself, make this run.

The internal diagnostic (message, line and column, checked node) comes from the
in-process Local Client, which carries the Host's preparation issue. HTTP
returns the same public code without the diagnostic.

The minimal reproductions are hand-written texts that each differ from a
positive control in one construct. They run in every probe run on both
transports. They are not dbt output. The positive controls (`plain-pipe`,
`backtick-quoted-name`, `select-cte-into-select`) are checked for expected rows,
columns and stream completion like the baselines.

## How results are judged

- **Oracle.** The expected rows and columns in `cases.json` were written by hand
  from the synthetic source rows, not from ActQL output.
  - Source rows: `(1, 7) (2, 20) (3, 30) (3, 30) (4, 5) (5, NULL)`.
  - Expected columns: `id` number not-null, `amount` number nullable.
- **Row comparison.** Without `ORDER BY`, rows are compared as a multiset, so
  duplicate counts matter: the two `(3, 30)` rows must both appear.
  `pipe-ref-ordered` has an explicit `ORDER BY` and is compared in order.
- **NULL behaviour.** `pipe-ref` carries `(5, NULL)` through. `select-cte`
  removes it with `amount > 10`.
- **Empty source.** The rows are deleted and `pipe-ref` and `select-cte` run
  again. Each must return no rows and the same columns.
- **Streaming.** For every Named Result, `rows()` must end in state `complete`
  and match `all()`.
- **JSON Program comparison.** `programs/*.json` hold the same filter and
  projection written as JSON Programs. They agree with the dbt models, but they
  run on the same runtime, so the agreement is a front-end comparison, not an
  independent oracle.
- **Expected non-support versus failures.** The rules are in
  `scripts/fixtures/dbt-compat-judge.mjs` and tested by
  `scripts/dbt-compat-judge.test.mjs`, part of `check:distribution-client`.
  - Only a refusal at submission, with one of the Client submission codes, of
    an observe case is a finding (`unsupported`).
  - A Run that was admitted and did not succeed is `run-failed` and fails the
    probe, for observe cases as well as baselines and controls. It is a fault of
    the run, not a statement about what ActQL supports.
  - A baseline or control refused at submission is `baseline-failed`, and wrong
    rows, columns or stream state are `wrong-result`. Both fail the probe.
  - Any other error (connection, timeout, missing dependency) stops the run as a
    fault. It is written to `results.json` with the outcomes recorded before it.
- **Check of the comparison itself.** Changing one expected `(3, 30)` to
  `(3, 31)` made the run fail with `wrong-result` on both transports and kept
  the evidence and the environment.
- **Check of the Run-failure rule.**
  `ACTQL_DBT_PROBE_INJECT_RUN_FAILURE=<case>,…` is a test-only switch. It
  records the named cases' successful Runs as Run failures, marked `injected`
  in the evidence. Injecting the observe case `ephemeral-select-into-select` and
  the positive control `reproduction:plain-pipe` made the run fail with
  `run-failed` for both, on both transports. It exited 1 and kept the evidence
  and the environment.

## What `dbt compile` needs

dbt only renders the models. ActQL runs the compiled SQL.

- **Installed adapter and profile.** dbt loads the dbt-duckdb plugin and the
  `actql_probe` profile even though it opens no connection.
- **`--no-populate-cache`.** Without it, dbt opens a DuckDB connection to fill
  its relation cache from `information_schema`. With the default `:memory:` path
  that creates no file, and with a file path it creates the database. The probe
  checked the debug log: one `Opening a new connection` without the flag, none
  with it. Every run asserts 0, plus no `*.duckdb` file and no `.user.yml`.
- **Telemetry off.** `DBT_SEND_ANONYMOUS_USAGE_STATS=false` and `DO_NOT_TRACK=1`.
  `DBT_PARTIAL_PARSE=false` keeps every run a full parse.
- **No network at compile time.** On macOS the compile runs under
  `sandbox-exec` with `(deny network-outbound)`. That profile was confirmed to
  block outbound connections: `curl https://pypi.org/` inside it fails at name
  resolution. On other platforms the summary records the run as not
  network-isolated.
- **Installation uses the network.** `pip install` fetches the 54 hashed wheels
  from PyPI, about 40 s with a cold cache.
- **No `dbt --version`.** It contacts PyPI to check for updates, so the probe
  reads versions from package metadata instead.
- **Shape of the compiled output.**
  - dbt adds no comment or semicolon.
  - A `{{ config(...) }}` line leaves an empty first line.
  - Ephemeral injection produces `with __dbt__cte__<name> as (\n<body>\n) <model>`.
  - The manifest's `compiled_code` equals the file under `target/compiled/`.
  - `manifest-excerpt.json` keeps, for each case: `raw_code`, `compiled_code`,
    `relation_name`, `depends_on`, `extra_ctes`, checksum and the SHA-256 of the
    compiled bytes.

## Evidence kept for each run

The run keeps:

- the original projects;
- every compiled file;
- each command's argv (scratch path redacted), exit status, duration and output;
- the dbt debug logs;
- per-case outcomes, including rows, columns and diagnostics;
- the versions and package digests.

`summary.json` has `status: "passed"` only if all of these hold:

- the compile checks pass;
- no case is `baseline-failed`, `wrong-result` or `run-failed`;
- no fault occurred.

## Runtime and maintenance cost

The reference run (`9ecf2777c`, darwin-arm64) took 198 s. Across seven runs the
total was 105–334 s; the 334 s run was the injected-failure check on a loaded
machine. The two largest steps vary most between runs.

The steps of the reference run, with the range across runs:

| Step | Time |
|---|---|
| venv | 9 s (6–9) |
| pip install | 58 s (40–58; network, cold cache) |
| first `dbt compile` | 14 s (14–32; cold imports) |
| second `dbt compile` | 7 s (4–7) |
| `npm pack` × 5 + install | 33 s (19–33) |
| Local and HTTP cases | 75 s (48–75) |

Disk use is about 357 MiB of scratch, removed after a successful run, and about
270 KB of evidence.

Maintenance:

- **dbt 1.11 support ends soon.** dbt-core 1.11 is in critical support (security
  and installation fixes only) until 2026-12-18; 1.12 is in active support until
  2027-07-15 (https://docs.getdbt.com/docs/dbt-versions/core). Moving to 1.12
  changes the lock.
  - Since 1.12.0, dbt-core depends on `dbt-core-experimental-parser`, whose PyPI
    package is a small sdist that fetches a ~138 MB binary from GitHub releases
    at build time (https://pypi.org/project/dbt-core/).
  - So `--only-binary :all:` with a PyPI-only hash lock no longer covers the
    installation.
  - This was checked on 2026-10-01 on darwin-arm64 with Python 3.13.11 and uv.
- **1.12.5 output for these models.** dbt-core 1.12.5 with dbt-duckdb 1.11.0
  compiled all eight probe models byte-identically to 1.11.15. That was checked
  once, from an unlocked install, on 2026-10-01. It is not a general
  equivalence claim, and the runner does not repeat it.
- **Coupling to ActQL fixtures.** The source profile is built the same way as
  `scripts/fixtures/packed-public-query.mjs`: same environment fixture, policy
  profile and capability CID. If those fixtures change, this probe fails at
  connection or source binding, which is a fault, not a finding.
- **Lock regeneration.** `requirements.txt` is regenerated with the command in
  its header and is tied to Python 3.13.

## Limits and follow-ups

The probe did not implement any of these.

1. **WITH followed by a Pipe query, and Pipe CTE bodies.** This is the parse
   boundary for every ephemeral used with Pipe. Changing it is a grammar
   decision; the reproductions are in `cases.json`.
2. **dbt's default double-quoted identifiers.** `"…"` is reserved for JSON text
   (Graph labels). Accepting the default quoting would need a lexing decision.
   Otherwise the documented quoting configuration remains a requirement.
3. **INFER.** Once shared `infer` checking and its Host execution path are
   adopted, provide a ModelTask provider and verify execution. This probe shows
   only that the dbt-rendered text parses, lowers and is refused by the shared
   checker at this revision.
4. **One relation per source profile.** An installed source profile binds one
   DuckDB table, so this probe covers models that read one relation. Models that
   `ref()` two relations were not tested.
