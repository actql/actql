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
| `check`, `explain`, `run`, `approve`, `status` (convenience commands) | ○ | — | — | — | — |
| `explain --verbose`, `explain --run`, `actql-explanation/0.1` JSON | ○ | ○ | ○ | ○ | ○ |
| `connect` / `startSource` / `wait` / `result` / `attach` | — | ✔ | ○ | ✔ | ○ |
| Mock profile (`--profile mock`) | ○ | ○ | ○ | ○ | ○ |
| Pushdown to a Connector | ◐ | ◐ | ○ | ◐ | ○ |
| Cross-source joins in DuckDB | ◐ | ◐ | ○ | ◐ | ○ |
| `INFER` with a model task | ◐ | ◐ | ○ | ◐ | ○ |
| `EFFECT … UPDATE TARGET … MAPPING …` (long form) | ◐ | ◐ | ○ | ◐ | ○ |
| `EFFECT … COMMAND` postlude (long form) | ◐ | ◐ | ○ | ◐ | ○ |
| `CREATE [OR REPLACE] TABLE` | ◐ | ◐ | ○ | ◐ | ○ |
| `EFFECT UPDATE / UPSERT / DELETE … ID …` (short forms) | ○ | ○ | ○ | ○ | ○ |
| `EFFECT INSERT`, `EFFECT STORE`, `EFFECT COMMAND … ID …` (short forms) | ○ | ○ | ○ | ○ | ○ |
| `LIST_FILES`, `contents` sources (`content_ref`), `SERIALIZE`, `STORE` of content | ○ | ○ | ○ | ○ | ○ |
| SQL `INSERT` / `UPDATE` / `DELETE` statement Effects | ○ | ○ | ○ | ○ | ○ |
| Checkpoints and approval | ◐ | ◐ | ○ | ◐ | ○ |
| `--stop-before commit` / `stopBefore` | ○ | ○ | ○ | ○ | ○ |
| Reconciliation of unknown outcomes | ◐ | ◐ | ○ | ◐ | ○ |
| Named Results and delivery | ✔ | ✔ | ◐ | ✔ | ○ |
| `NEAREST` shorthand and vector functions | ○ | ○ | ○ | ○ | ○ |
| Graph construction, `MATCH` and graph operations | ◐ | ◐ | ○ | ◐ | ○ |
| Event operations | ◐ | ◐ | ○ | ◐ | ○ |
| Local Host (embedded) | ✔ | ✔ | ◐ | — | — |
| Remote Host over HTTPS | — | ✔ | ✔ | ✔ | ○ |

"Node" is the `@actql/node` package; "Python" is the `actql` package. The
CLI column covers the native `actql` command.

## Python backends and platforms

This is the canonical implementation matrix for the Python package READMEs.
The overview's Python column describes the standard `actql` product; the shared
facade also exposes Remote operations that its Local backend does not implement.
Experimental Local marks below cover only the finite cases stated here, not all
queries, connectors or recovery. Documentation elsewhere describes the v0.1 target.

| Backend | OS / architecture | Required packages | Open / connect | Normal Run and Result | Saved | Cancel / Checkpoint | Known limits and evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Ordinary Local (in-process Wasmtime / DuckDB) | macOS 11+ arm64; Python 3.11+ | `actql`, same-cohort `actql-sdk` and `actql-local-runtime` | `actql.open`, `Client.open`, `AsyncClient.open`; no diagnostic resource argument | Experimental source-free, Effect-free, checkpoint-free SQL and Result | Finite separate-process lookup/attach/read evidence; not general recovery | Local cancel/lookup-cancellation and Checkpoint list/review/resolve suppliers are not connected | Candidate evidence below; no blanket connector, repeated-read, pressure or performance acceptance |
| Ordinary Local on other platforms | Linux, Windows and other macOS architectures | No selected normal runtime wheel accepted by the current verifier | Unverified | Unverified | Unverified | Unverified | A portable Core or diagnostic source build is not a normal-wheel acceptance result |
| Optional owned-Native preparation | Requires matching original physical suppliers | Matching private Native/runtime cohort in addition to its original preparation | Incomplete supplier; refuses without its original funding | Not established by ordinary Local evidence | Not established | Not established | Separate from ordinary platform startup; no fallback to diagnostic resources |
| Remote HTTPS Client | Python 3.11+ where its Python dependencies are supported; platform combinations require their own acceptance | `actql-sdk` only, or the standard `actql` facade | `Client.connect` / `AsyncClient.connect` to an existing Host | Shared wire Client; execution depends on the selected Host | Explicit lookup/attach/read depends on retained Host history | Shared Client routes exist; Host support and current authorization are still required | No Local engine required; no automatic resend, redirect or Local fallback; full Checkpoint/recovery acceptance is incomplete |

The installed Local operation dispatcher currently connects `connect`, `check`,
`lookup-submission`, `attach`, `submit-intent`, `status`, restricted `wait`, `read`
and `delivery-attempt`. A connected route is not an acceptance result. Named
submission, cancellation, Checkpoint operations and reconciliation are not
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

These are development-candidate observations, not a published release or a
rerun on current main. Cold status/wait, full public Local `check` acceptance,
top-level `connect`, Mock and repeated-Host pressure remain incomplete or
unverified. The [normal-wheel verifier](../../scripts/test-python-release-install.mjs)
currently selects only `darwin-arm64`; the
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
