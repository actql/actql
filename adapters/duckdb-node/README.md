# Private DuckDB transport

This optional Node transport pins `@duckdb/node-api` to `1.5.5-r.4`. It is an
internal building block, not a Program SQL API or a standalone ActQL Host.
The [execution boundary](../../docs/design/duckdb-relation-execution.md) separates
MoonBit semantic matching and validation from Node native resource management.

Native predicates currently support the restricted numeric/boolean comparison
subset, not string predicates. A supported string expression may instead use
the separately selected broad acquisition plus Local residual; unsupported native
execution is not silently retried after failure.

File compatibility is evaluated by opening the authorized file read-only with
the pinned Neo build. The current connection fixtures create and reopen files
with that build; they do not establish a cross-release storage compatibility
matrix. DuckDB's [storage documentation](https://duckdb.org/docs/current/internals/storage)
distinguishes engine releases from selected storage versions and enabled features.
An incompatible file must fail explicitly; this adapter never automatically
converts, upgrades or rewrites the source database.

Ordering is limited to the supported single real-table scan with `SELECT` and
`WHERE` in one consistent read view. `preserve_insertion_order=true` alone is
not a universal deterministic-order guarantee. The applicable
[DuckDB order-preservation rules](https://duckdb.org/docs/current/sql/dialect/order_preservation)
do not extend that claim to joins or grouping. Relative row order and duplicates
must survive chunking; no ActQL total-order witness is created and
`source_order_cid` remains null.

The native two-receipt baseline transfers the entire validation scan plus the
selected result. It is not a transfer-saving optimization, and total execution
time superiority or inferiority has not been established. Both receipts,
validation, conversion and retention belong in candidate costs.

Install and exercise the real database transport:

```sh
npm ci --prefix adapters/duckdb-node --ignore-scripts
npm test --prefix adapters/duckdb-node
```

The Linux workflow installs pinned MoonBit and Neo, records the revision and
runtime environment, then executes these tests. A workflow definition is not a
successful run. Report GitHub Actions runs and local Linux-container runs
separately, with revision/environment and observed outcomes. The first integrated
real-backend increment requires an actual Linux verification run; no push is
required if a local Linux environment is used. An uninspected Actions history
does not establish that the workflow has never run.

The repository's pinned MoonBit must be installed with `moon` on PATH and
`MOON_HOME` set for the generated-SQL conformance test. That test runs the
MoonBit completed-capture fixture, imports its exact generated parameters into
an isolated real DuckDB database, executes the generated filter/select SQL and
checks independently fixed output. The small fixture is serialized for testing;
the trusted `runFixedCompute` port reads one parameter row at a time. Its import
row/cell limits are separate from session transfer limits and logical guards.
The port must be backed by the exact MoonBit `FixedCompute` preparation, not
Program-supplied SQL or a deserialized claim of completed input.

This connection test does not yet turn the native result into MoonBit completed
output or issue acquisition capture evidence. Its result chunks remain
provisional until both the transport cleanup and the receiving semantic checks
have succeeded.

`runNativeAcquisition` sequences catalog metadata, validation scan and native
query on the same read-only transaction. Its port must supply MoonBit-generated
commands and perform the actual metadata, value and guard checks. A failed or
cancelled run aborts provisional receivers and cannot restart the same port.
The real native-read test uses generated SQL with a lifecycle test double for
these receiving callbacks; it verifies sequencing, two separate transport
measurements, empty receipts and cleanup, not full MoonBit admission or evidence
issuance. Integrating those callbacks and the two-receipt capture verifier remains
required for end-to-end acquisition conformance.

The additional MoonBit receiving conformance test builds `duckdb_conformance`, a
JS-only fixed test fixture using public checked entrances. It calls the portable
`NativeReceiving` and physical value-admission implementation in the same process
as Neo. It rejects discarded invalid scan values, nullability violations,
lossy integers and views before native filtering, and covers empty results.
The fixture exports no completion constructor or evidence issuer; it is not a
general Host entry point. Receiving applies explicit per-record canonical byte
and native output-row ceilings with a cumulative physical measurement budget
across both receipts. `measure_native_demand` then measures retained operands
under an explicit additional physical budget. For the restricted eager
comparison it obtains exact true/false/NULL counts from operand nullness and SQL
output counts, without Local predicate replay. The returned measurement must
match the exact live receiver; it is not a substitute for SQL/read-view evidence.
Selected fragment/consumer contracts, product completion and capture still
require their product integration. The original lifecycle-double test remains
useful for injecting receiver failures independently of semantic validation.

The receiving fixture also hashes the retained validation/native row sequences
in MoonBit and compares them with fixed independent canonical preimages. Receipt
bytes count typed row JSON, not transport frames. These owned digests are not
process-evidence records and do not grant capture authority.

`runBroadAcquisition` executes catalog metadata and the complete known-column
scan in one read-only transaction. Its MoonBit `BroadReceiving` port admits
physical cells once and retains their immutable payloads through the engine's
bounded `AdmittedInput` builder. The sealed `CapturedRows` is input material,
not a successful observation: transport cleanup, guarded Local residual and
capture verification must still succeed. The portable integration test passes
this input through the existing query receipt and Local filter/select completion
path, including an expression unsupported by the native predicate compiler.
The real Node test also runs the retained broad input through the existing
guarded Local filter/select driver and checks the completed output CID against
a fixed preimage. It verifies retry with fresh execution limits after an output
guard failure. Contract bodies come from the engine's adopted fixed fixture and
are admitted against its pins, not implicitly upgraded to a newer registry.
This is still a fixed conformance entry, not the complete acquisition evidence,
capture and subsequent consumer path in a production Host.

For owned query integration, `query_planning.prepare_duckdb_query` takes an
existing canonical requirement and Host-selected schema/table names. Its broad
scan feeds the receiver above; `execute_duckdb_broad_residual` applies the guards
from that exact requirement rather than accepting replacement logical limits.
The native preparation accessor reports compiler/root-ceiling compatibility
only; it is not yet a validated runnable offer or source-access authorization.

`prepare_capability_registry` creates bounded, owned Host registrations. Pass
an acquisition-enabled registration to `mock_acquisition_candidate` or
`duckdb_broad_candidate`, then pass `prepared_acquisition_candidate(prepared)`
to the same `choose_acquisition_candidate(registry, requirement, ...)` comparison.
Only the matching `PreparedAcquisition[T]` can recover the selected typed payload
through `acquisition_choice_payload`; there is no common Mock/DuckDB enum.
`mock_acquisition_strategy` enters the existing mock driver without re-ranking.
The DuckDB factory requires
eight disjoint work scopes exposed by `duckdb_broad_work_at`; missing estimates
remain unknown. The proposed choice retains its provider binding for Host
dispatch. This comparison does not perform I/O, issue capture evidence, or
retry a failed native query as a broad scan.

Registry names are diagnostic, not source authority or semantic identity. An
equal declaration in another registry is rejected. Closing a registry blocks new proposals/recovery without
releasing completed upstream observations.

For a completed input, `prepare_fixed_compute_request(ProducerRead)` binds the
exact receiving owner. `local_fixed_compute_candidate` and
`duckdb_fixed_compute_candidate` use Compute-enabled registrations from the same
registry, and `choose_fixed_compute_candidate` compares their complete inventories.
`execute_local_fixed_compute` runs the selected Local preparation through ordinary
producer admission. `fixed_compute_choice_payload` recovers the selected typed
DuckDB import/query preparation for the isolated Node Compute transport.

Local cost slots 0–4 are preparation, input admission, computation, output
retention and cleanup. DuckDB slots 0–7 are session/table setup, import transfer,
import conversion, native computation, result transfer, result conversion,
retention and cleanup. Missing slots remain unknown; none of these estimates
is a hard limit or evidence that selected consumer contracts were enforced.
The real fixed-Compute fixture uses this comparison before SQL execution, with
independent expected rows. It still serializes a tiny test input: native result
admission into product completion is not demonstrated by transport success alone.

The private `DuckDBBroadAttempt` API orders metadata, chunk admission, receipt
sealing, transport settlement and guarded residual execution. A Host coordinator
must acknowledge settlement only after `runBroadAcquisition` has returned
successfully, not from its `finishReceipt` callback. On transport or cleanup
failure it aborts the attempt. The lifecycle is one-shot and does not issue
capture evidence; it must not be exposed as an untrusted cleanup-attestation API.

`retain_duckdb_broad_attempt` then measures and retains the exact scan and
completed output under a shared canonical byte/node allowance. Its usage reports
received wire bytes, retained wire bytes and measured nodes, not allocator usage
or transport-frame size. `duckdb_broad_retention_matches` requires the exact live
attempt association; a digest or cancelled attempt cannot stand in for it.
Evidence issuance and observation capture still follow this retention boundary.

The portable broad issuer is `prepare_duckdb_query_issuer`, followed by
`prepare_issued_duckdb_broad_attempt` with the selected owned candidate.
`issue_duckdb_broad_records` and `capture_duckdb_broad_query` require retained
execution and a live trusted transport verifier; the ordinary consumer connection
is `bind_captured_duckdb_broad_input`. IDs, JSON and matching content are not
alternative constructors. These are internal Host APIs, not untrusted plugin
registration or a public authorization interface.

`runBroadQuery(grant, prepare, limits, signal)` in `broad-query.mjs` coordinates
actual source settlement with that bridge. The trusted synchronous `prepare`
factory receives an exact transport verifier and returns `{attempt, port,
complete, bindInput, abort, close}`. Install the verifier on the MoonBit issuer;
`port.finishReceipt` must return the same opaque attempt. `complete` runs the
MoonBit settlement/residual/retention/issuance/capture operations synchronously,
and `bindInput` uses the captured-input API. It performs no new source access.
The returned handle exposes the opaque observation, `bindInput` and idempotent
`close`; a failed consumer does not close it. The factory and these callbacks
must not come from Program data.

This is a low-level trusted assembly API, not yet the standard product Host
entry. That entry must install the verifier through its own trusted bridge and
must not accept a verifier/factory override from Program data or ordinary
Connector registration. Product examples and CLI code must not import the fixed
`duckdb_conformance` exports or test catalogs. The conformance package exercises
the implementation; it is not the application's runtime configuration.

`test/issued-broad-query.test.mjs` connects real DuckDB to the actual MoonBit
issuer in one process through the fixed `duckdb_conformance` fixture. It starts
at public `program_check.check`, selects the registered broad candidate, and
checks records and the complete observation against independently composed
expectations. It covers empty input, nullable unused columns, duplicate/order
preservation, rejected non-finite unused values, premature issuance, cancellation,
output/artifact exhaustion, and consumer retry after the source file changes.
The fixture is not a general Host entry point. Native two-receipt capture and
DuckDB Compute product completion are separate integration requirements; this
broad-path test does not establish them. The smaller coordinator lifecycle-double
test remains useful for isolated transport cleanup checks.

Tests create their own files under ignored `_build/duckdb-fixtures`, exercise
exact scalar transport, existing-file read-only access, isolated Compute,
cumulative transfer bounds, native memory exhaustion, cancellation and cross-process file locks. They
delete only their own uniquely created fixture directories. A passing transport
test does not establish end-to-end ActQL acquisition/capture conformance. The
resource-pressure fixture uses a native hash aggregation only to exhaust memory;
it does not add ActQL aggregate execution support.

## Private protocol

On the MoonBit side, `duckdb_native_candidate` uses the common acquisition
comparison with eleven disjoint work slots (`duckdb_native_work_at`), including
both actual row transfers. `prepare_duckdb_native_attempt` accepts only the exact
selected typed candidate and binds its common acquisition guards. Its metadata,
receipt and measurement operations preserve the receiver's full-scan checks and
one-shot failure semantics. `measure_duckdb_native_attempt` requires settled
transport and produces owned diagnostic measurements, not execution records or a
captured observation.

The portable native issuer starts with `admit_query_two_receipt_contract` and
`prepare_duckdb_native_issuer`, then binds authority before access through
`prepare_issued_duckdb_native_attempt`. After exact live transport verification,
`issue_duckdb_native_records` checks retention and emits both receipts and all
three records atomically. `capture_duckdb_native_query` creates the separate
two-receipt observation; `verify_duckdb_native_observation` requires its live
issuer, exact attempt and issued-set handles. Portable tests compare all preimages
and aggregate artifact boundaries against independent expectations. Real Node
bridge integration and the native producer/consumer product completion path
remain required. The document/CID is not an alternative success constructor.

`authorizeLocalDatabase` is called by explicit trusted Host setup, not by a
Program resource decoder. The opaque grant authorizes a path to a trusted local
file. It is not a snapshot identity or a malicious-file sandbox.

`withSourceDatabase` opens a fresh read-only transaction; `withComputeDatabase`
opens a separate in-memory database. Their callbacks receive a command operation,
not a native connection. Commands must be generated by the trusted MoonBit
adapter. The SQL statement-kind allowlist and disabled external access provide
additional restrictions, not a replacement for that trust boundary.

Each command binds parameters and delivers immutable column chunks provisionally.
Only successful session resolution, after native settlement and resource cleanup,
indicates transport completion. That completion is still not ActQL evidence or
permission to publish an observation. Errors cannot be caught inside the callback
to turn a failed command into a successful session. Unawaited commands prevent
success and are settled before cleanup.

Values use primitive physical payloads: signed decimal integer strings, decimal
coefficient strings, raw date/timestamp ticks and hexadecimal floating-point bits.
Naive timestamps remain distinct from instants. MoonBit performs type matching
and shared value admission; Node must not normalize strings or round values.
The MoonBit `duckdb_adapter` also emits exact prepared parameters from admitted
scalar values for fixed-input import.

The transport-byte ledger measures UTF-8 JSON frames for parameter arrays, field
metadata and column chunks. SQL bytes have a separate bound. These figures are
not native IPC traffic, canonical value bytes, logical work, allocator capacity
or process RSS. Row/cell/byte budgets are cumulative across commands in a session.
DuckDB memory configuration does not impose a hard whole-process memory ceiling.

Cancellation is cooperative: request, native settlement and cleanup are distinct.
There is no forced process-termination deadline or reusable connection pool.
Neither successful transport nor a read-only connection validates source schema,
full-scan obligations, native expression compatibility, ownership or capture;
those belong to the MoonBit execution and evidence integration.
