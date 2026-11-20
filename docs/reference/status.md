# Implementation status

This is the one page that describes what is implemented today. Every other
page describes ActQL 0.1 as designed: the guarantees in the specification and
the product surface the rest of the documentation shows. Use this page to
check whether a feature runs in your environment before you depend on it.
The ceilings every Program runs under are on [Runtime limits](limits.md).

## Status by environment

| Mark | Status | Meaning |
| --- | --- | --- |
| ✔ | **Implemented** | Runs in that environment; covered by the repository's checks. |
| ◐ | **Experimental** | Runs, but the surface or its limits may still change before 0.1. |
| ○ | **Planned** | Defined in the specification and shown in the documentation; not yet executable in that environment. |
| — | Not applicable | The feature has no meaning in that environment or for that Connector. |

| Feature | CLI | Node | Python | Remote Host | ActQL Cloud |
| --- | --- | --- | --- | --- | --- |
| SQL and Pipe queries over local values | ✔ | ✔ | ◐ | ✔ | ○ |
| `init` with a mock template (`deal-review-mock`, `churn-risk-mock`) | ◐ | — | — | — | — |
| `run`, `approve`, `reject`, `status` | ◐ | — | — | — | — |
| `check` | ◐ | ◐ | ○ | ○ | ○ |
| `explain`, `explain --verbose`, `explain --run` (source-free Programs) | ◐ | ○ | ○ | ○ | ○ |
| `actql-explanation/0.1` JSON | ○ | ○ | ○ | ○ | ○ |
| `connect` / `startSource` / `wait` / `result` / `attach` | — | ✔ | ○ | ✔ | ○ |
| Mock profile (`"profile": "mock"`, `--profile mock`) | ◐ | ◐ | ○ | ○ | ○ |
| Pushdown to a Connector | ◐ | ◐ | ○ | ◐ | ○ |
| Cross-source joins in DuckDB | ◐ | ◐ | ○ | ◐ | ○ |
| `INFER` with a model task | ◐ | ◐ | ○ | ◐ | ○ |
| `EFFECT … UPDATE TARGET … MAPPING …` (long form) | ◐ | ◐ | ○ | ◐ | ○ |
| `EFFECT … COMMAND` postlude (long form) | ◐ | ◐ | ○ | ◐ | ○ |
| `CREATE [OR REPLACE] TABLE` | ◐ | ◐ | ○ | ◐ | ○ |
| `EFFECT UPDATE … ID …` (short form) | ◐ | ◐ | ○ | ○ | ○ |
| `EFFECT UPSERT / DELETE … ID …` (short forms) | ○ | ○ | ○ | ○ | ○ |
| `EFFECT INSERT`, `EFFECT STORE`, `EFFECT COMMAND … ID …` (short forms) | ○ | ○ | ○ | ○ | ○ |
| `contents` sources (`content_ref`) | ◐ | ◐ | ○ | ○ | ○ |
| `LIST_FILES`, `SERIALIZE`, `STORE` of content | ○ | ○ | ○ | ○ | ○ |
| SQL `INSERT` / `UPDATE` / `DELETE` statement Effects | ○ | ○ | ○ | ○ | ○ |
| Checkpoints and approval | ◐ | ◐ | ○ | ◐ | ○ |
| `--stop-before commit` / `stopBefore` | ◐ | ◐ | ○ | ○ | ○ |
| Reconciliation of unknown outcomes | ◐ | ◐ | ○ | ◐ | ○ |
| Named Results and delivery | ◐ | ✔ | ◐ | ✔ | ○ |
| `NEAREST` shorthand and vector functions | ○ | ○ | ○ | ○ | ○ |
| Graph construction, `MATCH` and graph operations | ○ | ◐ | ○ | ◐ | ○ |
| Event operations | ○ | ◐ | ○ | ◐ | ○ |
| Local Host (embedded) | ✔ | ✔ | ◐ | — | — |
| Remote Host over HTTPS | — | ✔ | ✔ | ✔ | ○ |

"Node" is the `@actql/node` package; "Python" is the `actql` package. The
CLI column covers the native `actql` command.

## v0.0.2, the Initial Developer Preview

v0.0.2 publishes the `actql` CLI and the `@actql/node` library on npm for
macOS arm64 and Linux x64/glibc. Python packages are not distributed in this
preview, and ActQL Cloud is not part of it; the Python column above describes
the repository, not a package you can install.

The CLI and Node columns above were checked on 2026-11-18 against the
published 0.0.2 packages on macOS (arm64) with Node 24, using the two mock
templates and Programs that read no Connector. Live providers and Linux were
not part of that check. The Remote Host and ActQL Cloud columns and the
Connectors table describe the repository.

### What runs

- **Mock templates on the CLI.** `actql init --template deal-review-mock` and
  `--template churn-risk-mock` create a project that needs no credentials.
  `actql run` reads the mock Connectors, takes the mock answers for `INFER`
  and stops at a Checkpoint with a Preview of the records about to change.
  `approve` ends the Run `succeeded`, `reject` ends it `cancelled`, and
  `actql result <run> --result updates` reads the named Result.
- **The same from Node.** `connect({mode: 'local', profile: 'mock'})`,
  `startSource` with `stopBefore: 'commit'`, `wait`, `approve` and
  `result(name)` complete both templates. Read-only Programs over the mock
  Connectors, including a join of two of them, run through `client.aql`.
- **Programs that read no Connector.** `actql sql`, `actql aql`, `check`,
  `explain` (also `--verbose`, `--json` and `--run`) and `run` work on the
  CLI, and `sql`, `aql` and `check` from Node.

### Known limits

- **One model Run per CLI project.** After a project has run one Program with
  `INFER`, the next such `actql run` in the same project fails with
  `ACTQL_E_CLEANUP_PENDING`. Run `actql init` again in a new directory for
  each Run. Programs without `INFER` keep working. ([#3637](https://github.com/actql/actql/issues/3637))
- **`approve` from Node can answer `LocalSigningOriginalConflict`** when it
  is called immediately after `wait()` returns `waiting_checkpoint`. Calling
  `approve` again completes the Run. ([#3638](https://github.com/actql/actql/issues/3638))
- **The CLI and `@actql/node` keep separate Local state.** A state directory
  created by one cannot be opened by the other, so a Run started from code
  cannot be approved from the CLI in this preview. After the CLI has applied
  a write to a project's mock data, Runs from Node in that project end
  `needs_reconciliation`; use separate projects for the two.
  ([#3639](https://github.com/actql/actql/issues/3639), [#3641](https://github.com/actql/actql/issues/3641))
- **`check` on Programs with an Effect.** On the mock profile `check` returns
  `Undetermined` (`unresolved_protected`) for a Program with a short-form
  `EFFECT`, the two templates included. Read-only Programs are verified.
  ([#3640](https://github.com/actql/actql/issues/3640))
- **`explain` and plans.** `explain` works for Programs that read no
  Connector. Programs that read a Connector or contain an Effect are refused,
  and `explain --run` has no plan for their Runs. `client.plan()` does not
  return a plan in this preview. `explain --json` prints `actql-plan-view/0.1`.
  ([#3643](https://github.com/actql/actql/issues/3643), [#3644](https://github.com/actql/actql/issues/3644))
- **Effects on the mock profile.** Mock Connectors declare record `UPDATE`
  only, and an `UPDATE` has to set every field the target declares. On the
  CLI, Effects run in the template shape, `INFER` followed by `UPDATE`.
- **Read-only Programs over mock Connectors** run from Node and do not run on
  the CLI. ([#3642](https://github.com/actql/actql/issues/3642))
- **Saved Results** can be read back when the Result is named `main`,
  `answer` or `updates`. ([#3644](https://github.com/actql/actql/issues/3644))
- **Graph operations and `sequence`** run from Node. The CLI refuses them.
- **`actql init`** comes from the npm launcher and is not listed by
  `actql --help`; `actql init --help` describes it. `actql status` needs a
  Run ID. ([#3644](https://github.com/actql/actql/issues/3644))

## Native CLI platforms

| Platform | Packaged runtime requirement | Distribution examples and qualification |
| --- | --- | --- |
| Linux x64/glibc | glibc **2.38 or newer**, including for `actql --version`; the bundled Local Crypto raises the minimum above that of the executable alone | Debian 13 meets the minimum; Debian 12 (glibc 2.36) is unsupported. The Debian 12 refusal and Debian 13 Local workflow were observed with x64 containers emulated on an arm64 host; those observations are not native-host qualification. |
| macOS arm64 | The current release qualification environment is macOS 26; earlier minimum support requires the final artifact ABI and installed acceptance | Intel Macs, Windows and musl Linux are outside the release. |

The Native npm package intentionally has no install-time platform-check script,
download or compiler. An install can succeed on an older glibc; execution then
refuses with exit 64. Compatibility checks remain at the launcher, including
when npm lifecycle scripts are disabled. The exact release manifest retains
the artifact-specific ABI and library requirements. See the
[CLI reference](../cli.md) and [Native package](../../packages/native-cli/README.md).

## SQL collection profile

The collection syntax follows the [compatibility profile](sql-compatibility.md):
explicit local order, existing NULL exclusion, and a candidate-key witness for
`ARRAY_AGG`. `IGNORE NULLS` is optional syntax, not a switch to another NULL
policy. Keyed scalar and grouped calls have focused Common compiler/execution
coverage. This does not establish acceptance of an unkeyed literal-CTE query,
or new ordinary installed-package acceptance on every environment. The ordered
unkeyed form retains `UnresolvedOrder`; the unordered form retains its named
syntax refusal. Final-candidate public Result and cause propagation must be
qualified separately from these component checks.

## Python backends and platforms

This is the canonical implementation matrix for the Python package READMEs.
The overview's Python column describes the standard `actql` product; the shared
facade also exposes Remote operations that its Local backend does not implement.
Experimental Local marks below cover only the finite cases stated here, not all
queries, connectors or recovery. Documentation elsewhere describes the v0.1 target.

| Backend | OS / architecture | Required packages | Open / connect | Normal Run and Result | Saved | Cancel / Checkpoint | Known limits and evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Ordinary Local (in-process Wasmtime / DuckDB) | macOS 11+ arm64; Python 3.11+ | `actql`, same-cohort `actql-sdk` and `actql-local-runtime` | `actql.open`, `Client.open`, `AsyncClient.open`; no diagnostic resource argument | Experimental source-free, Effect-free, checkpoint-free SQL and Result | Finite separate-process lookup/attach/read evidence; not general recovery | Core-owned cancel/lookup-cancellation routes; Checkpoint list/review/resolve suppliers are not connected | Candidate evidence below; no blanket connector, repeated-read, pressure or performance acceptance |
| Candidate Ordinary Local on Linux | Linux x86-64/glibc 2.28+; Python 3.11+ | Same-cohort `actql`, `actql-sdk` and `actql-local-runtime` | Same public Local entry points; normal installed CI candidate below | Finite source-free SQL, typed parameters, Result and first close | Sync/async separate-process lookup/attach/read | Finite active cancellation, same cancellation lookup and Saved read; Checkpoint suppliers are not connected | Accepted on Ubuntu 24.04 at the exact candidate below; not a published Linux release or every supported glibc host |
| Ordinary Local on other platforms | Linux arm64, musl, Windows and other macOS architectures | No matching normal runtime installation accepted | Unverified | Unverified | Unverified | Unverified | Refuses unsupported Local platforms; Remote remains available where its dependencies are supported |
| Optional owned-Native preparation | Requires matching original physical suppliers | Matching private Native/runtime cohort in addition to its original preparation | Incomplete supplier; refuses without its original funding | Not established by ordinary Local evidence | Not established | Not established | Separate from ordinary platform startup; no fallback to diagnostic resources |
| Remote HTTPS Client | Python 3.11+ where its Python dependencies are supported; platform combinations require their own acceptance | `actql-sdk` only, or the standard `actql` facade | `Client.connect` / `AsyncClient.connect` to an existing Host | Shared wire Client; execution depends on the selected Host | Explicit lookup/attach/read depends on retained Host history | Shared Client routes exist; Host support and current authorization are still required | No Local engine required; no automatic resend, redirect or Local fallback; full Checkpoint/recovery acceptance is incomplete |

The installed Local operation dispatcher currently connects `connect`, `check`,
`lookup-submission`, `attach`, `submit-intent`, `status`, restricted `wait`, `read`,
`delivery-attempt`, `cancel` and `lookup-cancellation`. A connected route is not
an acceptance result. Named submission, Checkpoint operations and reconciliation are not
implemented there. Explicit `wait(since=...)` and nonterminal conditions refuse
rather than being ignored. These limits must not be inferred from the shared
Remote facade's method list. See the actual
[Local dispatcher](../../packages/python-sdk/src/actql_sdk/_local_product.py)
and [Client](../../packages/python-sdk/src/actql_sdk/_async.py).

### Python candidate evidence and its limits

The existing normal-wheel observations remain tied to their original candidates:

- `7629cfd0edd4d819ecbf387c1b417d7d7e984001`: clean three-wheel installation,
  public import, fresh Local `open`, `SELECT 1 AS id` returning `[{"id": 1}]`,
  and explicit Client close on macOS arm64.
- `fd878cec04aa6c95ffcc5481cb8fa5efbf7720ab`: fresh `SELECT 23 AS id`, close,
  then a separate-process reopen/attach/read of the original Result returning
  `[{"id": 23}]` without a new Program or compilation. This finite Saved case
  does not establish repeated reads, general crash recovery or responsiveness.
- `c52904d3de6239d728c6c4da1f70a0d98ca41c47`:
  [Linux normal-wheel CI](https://github.com/actql/actql/actions/runs/44490051224/job/135444478666)
  passed its full installed baseline on Ubuntu 24.04, including independent
  installation audits, sync/async initial execution and separate-process Saved
  reads, typed parameters, invalid-input refusal followed by healthy execution,
  active cancellation with the same original cancellation lookup, and first
  close. Physical stop may remain `unknown`; cancellation acceptance does not
  imply a physical-stop ACK. The same normal wheels also passed the selected
  Python 3.11.0 and 3.15.2 compatibility consumers. Those boundary-version
  consumers run installation audits and the health/typed-query case, not the
  entire baseline. This Linux observation does not qualify the Darwin job.

These are development-candidate observations, not a published release or a
rerun on current main. Cold status/wait, full public Local `check` acceptance,
top-level `connect`, Mock and repeated-Host pressure remain incomplete or
unverified. The [legacy release-install verifier](../../scripts/test-python-release-install.mjs)
currently selects only `darwin-arm64`. The current
[normal-wheel CI producer and installed acceptance](../../scripts/ci-python-wheels.py)
selects `darwin-arm64` or `linux-x64`; the
[consumer fixture](../../scripts/fixtures/python-product-installed.py) requires
real public execution and separate-process Saved reads, not a metadata fallback.

The boundary audit at `203439fda18649ce7d94b3e45245f726d220423f` passed 30
focused Node SDK HTTP/loopback tests and Python/Core scalar ABI plus Native
C/ctypes declaration freshness checks. The HTTP tests include real sockets and
some transport doubles; they do not execute the Python Local runtime or prove
actual durable Host composition. Declaration consistency does not prove compiled
exports, native execution, cleanup ACK or performance. No normal-wheel campaign
was rerun for that audit. New release candidates require their own matching
source, artifacts and independent acceptance.

## Connectors

Every Connector page describes the full v0.1 surface: reads, record
Effects, tables and content, operations, Preview and reconciliation. The
columns say what runs today.

| Connector | Read | Record Effects | Tables and content | Operations | Preview and reconciliation |
| --- | --- | --- | --- | --- | --- |
| DuckDB | ✔ | ◐ insert, update | ○ | — | ○ |
| Local files | ✔ | ○ | ◐ store rows, long form | ○ | ○ |
| Google Cloud Storage | ◐ | ○ | ◐ upload, long form | ○ | ○ |
| Salesforce | ◐ | ◐ single-record update | ○ | ○ | ○ |
| Google Sheets | ◐ | ◐ append | ○ | ○ | ○ |
| GitHub | ◐ | ◐ create | ○ | ○ | ○ |
| Snowflake | ○ | ○ | ○ | ○ | ○ |
| BigQuery | ○ | ○ | ○ | ○ | ○ |
| HubSpot | ○ | ○ | — | ○ | ○ |
| Slack | ○ | ○ | ○ | ○ | ○ |
| Notion | ○ | ○ | ○ | ○ | ○ |
| kintone | ○ | ○ | ○ | ○ | ○ |
| Tableau | ○ | ○ | ○ | ○ | ○ |
| Google Drive | ○ | ○ | ○ | ○ | ○ |
| Gmail | ○ | ○ | ○ | ○ | ○ |
| Google Calendar | ○ | ○ | — | ○ | ○ |
| Amazon S3 | ○ | ○ | ○ | ○ | ○ |

"Preview and reconciliation" means the apply-time condition check
(`full_diff` with a conflict outcome) and the evidence-based lookup of a lost
reply that each Connector page describes.
