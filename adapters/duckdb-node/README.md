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
separately, with revision/environment and observed outcomes. Claiming Linux
compatibility requires an actual verification run; defining the CI job alone is
not that evidence. No push is required if a local Linux environment is used. An uninspected Actions history
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

This low-level connection test does not turn the native result into MoonBit
completed output or issue acquisition capture evidence. Standard Host tests
separately cover those product boundaries. The transport's result chunks remain
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
only; by itself it is neither a validated runnable offer nor source-access
authorization. Candidate validation, Host authorization before access and
settled execution evidence before publication remain separate requirements.

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

For a completed input, `prepare_fixed_compute_request(ProducerRead, capacity)`
binds the exact receiving owner and an explicit `FixedComputeCapacity`: the
pinned consumer-capacity CID, common `max_rows`/`max_value_bytes`, and an optional
exact common fragment preparation. No implicit unlimited default is supplied.
An input row overflow fails even if the planned filter would remove every row.
Native candidates reject a selected common fragment until exact fragment
accounting is supported; they do not reinterpret it as Local-only.
This preparation is not itself a proof that all value/root guards have run.
`execute_local_fixed_compute` requires a separate `measurement` budget and
enforces common input/output value limits and demanded root ceilings through
the existing evaluator. Its measurement budget is cumulative across input and
output; retries supply a fresh budget without resetting the retained input.
`local_fixed_compute_candidate` and
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
The real fixed-Compute command fixture uses this comparison before SQL execution,
with independent expected rows. It serializes a tiny test input for command-level
diagnostics. The standard-Host conformance case additionally passes the actual
opaque native capture output into `ProducerRead` and the same candidate model,
then imports individual parameters into a separate DB without serializing the
whole input. Its Local result and DuckDB admitted receipt are each compared to
fixed expectations, not used as each other's oracle. Source-path removal during
this test verifies that import/residual work does not need a fresh source read.

The owned-input test exercises empty results, duplicates, receiver capacity
exhaustion, cancellation, repeat execution under fresh limits and upstream
revocation. It uses the shared physical decoder and `FixedComputeReceiving` for
actual returned chunks. The owned-input fixture measures complete input values
before import and output values after receipt settlement using the same bounded
engine measurement session. Exact owner/target/limits and one-use finishing are
checked without re-evaluating the predicate. The fixture also applies shared native demand measurement:
retained operands and the received result count determine predicate root bytes,
with no RHS demand for empty input. Neither measurement alone grants execution
success. The sealed receipt is still provisional, not a
`CompletedOutput`: the low-level transport driver does not itself grant trusted
completion. This fixture-backed driver is conformance code, not
the final standard Compute Host entry. Acquisition budget exemptions must not be
reused to waive a fixed consumer's selected contract.

The product MoonBit `DuckDBComputeAttempt` now coordinates selected candidate,
input measurement, result receipt, trusted settlement verification, demand and
output guards, and the actual engine `CompletedOutput`. Portable integration
tests bind that output to an ordinary checked consumer and cover failure and
revocation. The low-level verifier argument is trusted Host wiring. The standard
`runFixedHostCompute` entry uses this coordinator and installs the verifier
internally. The real owned-capture test exercises this product entry in addition
to the low-level diagnostic, while the source DB file is unavailable.

After `npm run build:host`, trusted application preparation supplies an opaque
`ComputeHostConfiguration` from `configure_compute_host`, containing the selected
candidate, exact consumer preparation, common capacity and physical allowances:

```js
import { runFixedHostCompute } from './host.mjs';
const result = await runFixedHostCompute(setup, sessionLimits, importLimits, signal);
try {
  const completed = result.output(); // bind with the ordinary checked producer API
  // result.usage, result.importedRows and result.importedCells describe transport.
} finally {
  result.close();
}
```

No source grant/connection, SQL callback, alternate runtime or verifier can be
passed to this entry. It imports only the owned completed input into a separate
memory DB. Completion requires actual settled port/callback/session provenance,
input/output capacity, demand measurement and retained output. Close revokes new
use of that output; independent consumers that already completed remain valid.
The setup may be reused for a fresh attempt and budget, not a restarted old
transport. This is source-checkout local Compute, not durable Run execution.

The standard fixed-Host conformance test additionally retains typed projected
outputs through product completion and an ordinary checked consumer. Text,
boolean, exact numeric values, DECIMAL, date and timestamp payloads include NULL
and duplicate rows. Local and DuckDB results are independently checked against
literal expected row identities, including foreign-owner and released-output
rejection. This does not broaden native predicates beyond their limited
numeric/boolean profile.

The scalar import transport fixture also starts with real engine-completed
values and the product import adapter, then checks exact real DuckDB round-trips
for text, boolean, number (including lossless large integers), DECIMAL(38,2),
date and millisecond-exact timestamp, with NULLs and duplicate values. Its
literal projection only observes stored parameters: this transport diagnostic
does not issue a semantic Compute completion or discharge consumer capacity.

`test/typed-host.test.mjs` exercises the standard native and broad acquisition
entries with an unused nullable column in each supported scalar family: text,
boolean, lossless BIGINT-to-number, finite DOUBLE, DECIMAL(38,2), date and
millisecond-exact TIMESTAMPTZ. Independent typed scan preimages determine the
expected access hashes; both strategies produce the same retained id projection
and checked consumer output. Lossy integers, noncanonical text, nonfinite numbers,
infinite dates and submillisecond timestamps in discarded rows still fail before
capture. This verifies full-scan admission of those fields, not native predicates
over strings/decimals/temporal values or unrestricted projections of every type.

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

This is a low-level trusted assembly API, not the standard product Host
entry. `runBroadHostQuery` installs the verifier through its own trusted bridge
and takes no verifier/factory override from Program data or ordinary
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
The fixture is not a general Host entry point. DuckDB Compute product completion
is a separate integration requirement; this broad-path test does not establish
it. The smaller coordinator lifecycle-double test remains useful for isolated
transport cleanup checks.

`runNativeQuery` uses the same private settlement/cleanup mechanism but requires
both validation and native receipts to retain the exact issued attempt. The
real `test/issued-native-query.test.mjs` connects the public CheckedProgram and
selected native attempt to SQL, admission, measurement, issuance and capture.
Its fixed setup calls the reusable MoonBit `duckdb_host` operations for receipt
management, completion and consumer binding; the Host package has no fixture or
catalog dependency. The low-level `start_native_host` verifier parameter remains
trusted runtime wiring, not a Program/Connector option. The standard native Node
entry described below installs verification internally.
Its independent observation oracle includes the two distinct receipt CIDs and
all three record CIDs. No Local predicate replay is used. It covers empty input,
NULL in an unused column, duplicate relative order, invalid discarded values,
output/artifact exhaustion, cancellation after either receipt and issuer release.
It also bridges the owned native output into the engine's real completion and
producer binding, then executes a checked consumer. Independent expected rows
determine the final content CID; consumer-budget failure permits retry from the
same successful capture without rerunning source SQL.

Tests create their own files under ignored `_build/duckdb-fixtures`, exercise
exact scalar transport, existing-file read-only access, isolated Compute,
cumulative transfer bounds, native memory exhaustion, cancellation and cross-process file locks. They
delete only their own uniquely created fixture directories. A passing transport
test does not establish end-to-end ActQL acquisition/capture conformance. The
resource-pressure fixture uses a native hash aggregation only to exhaust memory;
it does not add ActQL aggregate execution support.

## Private protocol

`runFixedCompute` uses a fresh attempt port for each invocation. It records
transport provenance only after the isolated Compute transaction and cleanup
succeed. The trusted bridge can check it with
`matchesFixedCompute(result, exactPort, exactReceiver)` and revoke it with
`releaseFixedCompute(result)`. A copied result, replacement receiver or another
port cannot pass. Failed/cancelled ports cannot restart; retry the immutable
completed input with a new port and fresh budgets. These checks do not issue an
ActQL completion or waive the pending semantic/guard/retention verification.

`prepare_fixed_compute_receiving`, `receive_fixed_compute_chunk` and
`finish_fixed_compute_receiving` provide the MoonBit result-admission boundary
for the exact compiled fixed-input plan. Metadata, cumulative physical limits and
separate retention limits are checked; sealed `FixedComputeReceipt` data is still
not successful Compute evidence. `abort_fixed_compute_receiving` invalidates that
receipt without revoking its upstream input. A source issuer revoked after a
producer view was created prevents new import/receiving operations, even though
the old immutable values may still be held in memory. Selected consumer capacity
enforcement and trusted completion remain separate from successful reception.

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
and aggregate artifact boundaries against independent expectations. The real Node
conformance bridge supplies settlement provenance to that same issuer. The
standard native Host entry uses that same issuer. The native producer/consumer bridge
uses `complete_duckdb_native_output` with an internally installed verifier. The
document/CID is not an alternative success constructor.

After transport settlement, the bridge calls
`complete_duckdb_native_capture(issuer, attempt, limits)`. This product operation
performs the measurement/retention/issuance/capture sequence and preserves typed
failures; the fixed fixture only supplies its test configuration. The separate
low-level operations remain useful for boundary conformance. Neither path accepts
a caller-supplied success boolean as a replacement for the issuer's live verifier.

For bounded row materialization after successful native capture, use
`materialize_duckdb_native_output` and `duckdb_native_output_rows`. They retain and
recheck the exact live observation, share immutable admitted values, and charge
new row containers under explicit conversion limits. Conversion failure leaves
the source observation available for retry with fresh limits; it does not rerun
SQL. The resulting `AdmittedOutputRows` is provisional engine material, **not**
`CompletedOutput` or a producer binding. Pass its owned `DuckDBNativeOutput` handle
to `complete_duckdb_native_output`, then use ordinary `bind_completed_input` and
consumer execution with fresh budgets. This second operation validates live
provenance and exact preparation ownership; no replacement verifier or rows are
accepted. A revoked source rejects new consumer admission, while consumer failure
does not destroy a successful source capture. The real native conformance case
checks final consumer CIDs against independently specified rows.

The engine's `prepare_trusted_output_port` is a trusted-runtime installation API,
not a safe public Connector or Program extension point. Do not expose it from an
untrusted Host interface; use the provider-specific bridge that fixes verification
internally. Standard acquisition and fixed-Compute assemblies have no conformance
dependency. Fixed-Compute uses the same trusted engine boundary with its own
requirement.

### Standard acquisition Host entries

With the pinned MoonBit toolchain on `PATH`, run
`npm run build:host --prefix adapters/duckdb-node`. Trusted MoonBit application
preparation uses `@duckdb_host.configure_native_host` with its exact requirement,
selected native candidate, admitted two-receipt contract and explicit limits.
Pass that opaque configuration to the Node entry; do not serialize it or import
fixed conformance setup into an application:

```js
import { authorizeLocalDatabase } from './session.mjs';
import { runNativeHostQuery } from './host.mjs';

const grant = await authorizeLocalDatabase(authorizedAbsolutePath);
const capture = await runNativeHostQuery(grant, ownedConfiguration, transportLimits, signal);
try {
  const completed = capture.output();
  // Pass completed to ordinary MoonBit producer binding / checked consumer.
  useCompletedInput(completed);
} finally {
  capture.close();
}
```

This source-checkout entry imports a fixed release build of `duckdb_host_node`.
It takes no factory, verifier, SQL, or runtime-module override. Configuration and
consumer application code must use the same pinned MoonBit build; this is not a
stable serialized ABI or a complete Program/Run Host. `document()` exposes the
completed observation document, not independent replay authority. Close revokes
new producer admission, including use of a previously obtained output handle;
consumer failure alone leaves the capture live. Each `output()` call performs
bounded materialization under the configured limits, without another source read.
Typed MoonBit failures are retained as the `cause` of `MoonBitHostFailure`.

For a selected broad candidate, application preparation instead uses
`@duckdb_host.configure_broad_host` with `BroadHostLimits`. Call
`runBroadHostQuery(grant, ownedBroadConfiguration, transportLimits, signal)` from
the same `host.mjs`. Its returned `bindInput(ownedConsumerPreparation, inputIndex)`
uses the existing captured-input binding directly. The expected producer is
derived from the owned requirement, not supplied separately by the caller.
Pass that bound input to the existing checked consumer; do not re-admit or copy
the captured rows in Node. Both entries expose `document()` and `close()`.
Closing either capture invalidates new execution even through an input already
bound before close, including a previously prepared ProducerRead or Compute
import. It does not revoke a consumer result completed before close. The broad
attempt's public `duckdb_broad_attempt_row_count` is diagnostic only: raw residual
CompletedOutput access before capture is not public.

The broad Host invokes `complete_duckdb_broad_capture` only after actual source
settlement. That operation validates exact issuer/attempt and transport ownership,
then runs Local residual, common guards, retention, record emission and capture.
An incomplete or failed attempt cannot be retried with larger limits. Duplicate
completion does not revoke an already successful capture. Unlike native, broad
selects the Local execution limits and pays for that residual; neither entry
waives the requirement-owned acquisition guards.

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
The MoonBit `decode_transport_columns` API decodes raw column JSON with bounded
bytes/nodes/columns/rows, preserves decomposed Unicode and CRLF, and returns typed
errors for malformed frames. It is a per-frame transport check, not a replacement
for cumulative receiving limits or value admission. The conformance wrappers now
use this same decoder; only their fixed test setup unwraps failures.
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
