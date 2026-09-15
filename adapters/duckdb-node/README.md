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

For owned query integration, `connectors/duckdb/acquisition.prepare_duckdb_query` takes an
existing canonical requirement and Host-selected schema/table names. Its broad
scan feeds the receiver above; `execute_duckdb_broad_residual` applies the guards
from that exact requirement rather than accepting replacement logical limits.
The native preparation accessor reports compiler/root-ceiling compatibility
only; by itself it is neither a validated runnable offer nor source-access
authorization. Candidate validation, Host authorization before access and
settled execution evidence before publication remain separate requirements.

`connector_sdk.prepare_capability_registry` creates bounded, owned Host registrations. Pass
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

Fixed-input request, capacity and choice APIs belong to `connector_sdk`.
Local candidate/execution functions belong to `connectors/local`; DuckDB Compute
candidate/attempt functions belong to `connectors/duckdb/compute`. These replace
their former `query_planning` locations without forwarding compatibility APIs.
DuckDB candidate failures retain concrete `Compilation` diagnostics or a wrapped
common `Request` failure, rather than adding SQL errors to the common request type.

For completed inputs, `prepare_fixed_compute_request([ProducerRead, ...], capacity)`
binds the exact receiving owner and every checked input port, in port order,
with an explicit `FixedComputeCapacity`: the
pinned consumer-capacity CID, common `max_rows`/`max_value_bytes`, and an optional
exact common fragment preparation. No implicit unlimited default is supplied.
Each input's row ceiling is checked independently, even if the planned operation
would discard every row. The request snapshots the handle array, not the rows.
Local, fresh-import DuckDB and resident DuckDB support the checked binary
inner-join profile. Both input ports retain independent guards and exact
producer ownership, including when they share the same backing table.
Schemas whose names collide under ASCII case folding (such as `K` and `k`)
remain legal in ActQL. DuckDB table imports and resident outputs exclude these
schemas before selection, because the current physical representation preserves
logical names. Fresh output transport can return them without materialization;
group keys are explicitly qualified input references, not output-alias lookups.
Local can consume these outputs. There is no automatic retry after failure.
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

For a preflight-bound inner-join configuration, the same entry imports both
ordered input ports into one isolated Compute database. `importLimits.maxRows`
applies to each input independently; `maxCells`, `importedRows` and
`importedCells` are cumulative across imports. Equal contents on two ports do
not imply a shared import. The standard Host conformance includes captured
self-join input, empty input, duplicate ordering, and downstream consumption
after closing the upstream capture. Common DAG dispatch also binds both ports
for fresh-import join; its portable tests cover reservation, settlement and a
separate downstream group/count. The resident variant binds both checked input
ports to retained tables and is also exercised through the standard Host.
Common input guards run before join null/cardinality checks, and all succeed
before the native attempt may execute SQL.

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

This independence also applies to successful DuckDB fixed Compute: after
`runFixedHostCompute` completes, closing its upstream capture does not invalidate
the still-open Compute result. Closing that result itself blocks new consumers.
Upstream closure before Compute completion still prevents successful publication.

For the internal checked-DAG increment, a native capture also exposes `source()`.
This returns an opaque `CapturedInputSource` with the exact acquisition and live
observation ownership; it is not a portable CID-based replay handle. Bind it to
the same checked graph using `physical_strategy.open_captured_dag`, supplying one
Host physical ledger that remains owned by that run across task choices.
Prepare a selected task's `ComputeHostConfiguration`, wrap it with
`duckdb_host.configure_strategy_compute_host`, and execute through
`runStrategyHostCompute` in `host.mjs`. The standard Host retains verifier wiring;
task completion is recorded by the DAG's exact attempt, not a caller-supplied
output. This fresh-DB entry uses a separate temporary database for every task and
imports each fixed input. Resident sharing is a separate selected realization,
not an implicit optimization of this entry.
The common DAG start (not only the Node wrapper) reserves `maxTransportBytes` and an execution envelope
against that ledger before DB creation. `computePhysicalCapacity(limits)` from
`physical-capacity.mjs` supplies the same envelope to planning and dispatch:
configured `memoryBytes`, plus eight bytes per permitted UTF-8 transport byte,
256 bytes per permitted cell/column/parameter entry, and four bytes per permitted
SQL byte. These are explicit Host allowances for serialization and container
capacity, not measured V8 heap/RSS or an OS sandbox. All contributing quantities
are checked transport ceilings, not unchecked estimates. A returned Compute's
`physicalCapacity` separates DB and scratch reservations from transferred usage.
Receiver-retained MoonBit results use a separate pre-reserved envelope derived by
the product MoonBit configuration from its actual retained-node/text, output-row
and completion-metadata limits. `physicalCapacity.retentionBytes` reports that
capacity; it is not included again in Node scratch or reported as actual heap use.
Sent/received frame bytes are charged
before acceptance and never refunded by result close or failure. Actual session
cleanup releases unused transfer and configured DB-memory reservations.
An error with `cleanupPending` retains `cleanupHandle.status()` and asynchronous
`cleanupHandle.retry()` for the same owned resources. `primaryFailure` and
`cleanupErrors` remain separate. Retry is resource cleanup, not a query retry.
The optional Host transport limit `cancelWaitMs` bounds the caller's wait after
cancellation (an integer from zero through 2147483647 milliseconds). Without it,
the call waits for settlement as before. Expiry returns `Cancelled` with a live
`cleanupHandle`; it does not acknowledge native stop, release ledger reservations,
or allow success publication. `status()` reports current pending responsibility,
while `retry()` awaits the same original operation and retries only failed cleanup.
The error's `cleanupPending` is the return-time snapshot; use the handle for updates.
This is an in-process handle, not durable recovery or a hard native-kill timeout.

### Run-owned resident execution

Before the first search, `duckdb_host.configure_resident_dispatch` can attach a
run-owned `physical_strategy.ResidentProfile` and resident task rates to the
standard dispatch setup. The profile specifies DB capacity, preparation/cleanup
estimates and per-producer import transfer, scratch and table allowances. Task
rates cover calculation, output receipt, Host retention and task cleanup; do not
include the shared preparation/import lines again. Unknown estimates remain
unknown. Only the exact run-owned profile and its selected input dependency may
authorize provision or import.

The fixture-independent `examples/physical-strategy.mjs` accepts `--resident`
(or `runExample({ ..., resident: true })`) to include this realization. Its
illustrative model uses one millisecond each for environment preparation,
cleanup, each input import and each resident task; these are supplied estimates,
not timings. The example ledger permits 500,000 transferred frame bytes, covering
acquisition as well as an initial import and three result envelopes. Actual
transport remains charged and bounded independently of the model.

`runCapturedStrategy` then selects Local, fresh DuckDB or resident DuckDB through
the same finite comparison. It provisions one source-isolated in-memory DB only
after reservation, imports a shared input once, and reuses retained result tables
within that DAG. Each task uses its own transaction. Host receiving, guards,
demand and independent completed results remain required; this does not eliminate
result transfer or acquisition's full-scan transfer.

The shared DB allowance stays reserved until confirmed destruction. Host output
copies and task scratch remain separate. Last-use table removal happens in a
task transaction after its reads and is credited only after commit and native
settlement. Output capacity is reserved before that removal. Table allowances
are Host admission policy, not measurements of DuckDB allocator bytes or a claim
that its configured memory limit bounds total process RSS.

Application users normally call `runCapturedStrategy` or the documented example.
Its serial loop lives in the connector-independent `adapters/host-node` module.
Local execution and DuckDB fresh/resident execution are installed contributions,
selected by exact registration handles rather than a Node backend switch.
The DuckDB contribution owns resident preparation, imports and session cleanup;
the common MoonBit start/completion checks still enforce reservations and output
ownership. A fulfilled implementation Promise alone cannot publish a task result.

The Node contribution set is assembled at rebuild time from connector-owned
`src/connectors/*/node-bundle.json` manifests. After changing a manifest, run
`node scripts/connector-node-bundles.mjs --write` from the repository root; the
generated assembly is checked by the adapter test command. This is trusted
composition, not dynamic plugin loading or an option for applications to replace
verification. The independent common-loop protocol tests are in
`adapters/host-node/strategy.test.mjs`; real-provider conformance remains here.
The following operations are a trusted Host-implementer protocol, not a sequence
of commands accepted from Program inputs. The low-level resident operations in `host.mjs` are
`openResidentStrategyEnvironment`, `importResidentStrategyInput` and
`runResidentStrategyHostCompute`. They retain trusted verifier wiring and cannot
attach arbitrary DB connections. Environment `status()` reports live/pending
state; `close()` invalidates DB reuse without revoking independent Host results.
After copy loss, only unstarted work can be selected again from live fixed Host
inputs, under the existing search and cumulative resource limits. Failed or
started tasks are not automatically retried.

`runResidentStrategyHostCompute(setup, environment, tables, limits, mappingLimits,
signal)` takes an array of resident table handles in checked input-port order.
A two-input join requires both handles; passing the same table twice is valid
only when both checked ports refer to that producer. The standard strategy driver
obtains this mapping from the selected strategy, imports each missing producer
once, and supports resident join followed by group/count without reimporting
the intermediate result. Results still return to the Host for validation and
independent holding. Preparing a later input unsuccessfully releases earlier
unstarted borrows; after admission, native settlement owns their release.

Transport settings are validated and frozen before environment reservation.
Invalid settings do not spend an attempt. Import preflight or reservation
rejection cancels only the most recent unstarted table preparation, reclaiming
its slot, quota and unused name while preserving spent planning work. Corrected
limits can then be submitted on the same environment. After import admission,
failure stops the graph and does not enable this preparation rollback.
Host implementers must distinguish work never sent from provision or cleanup
whose completion is unknown. No returned DB handle is not a cleanup proof.

The strategy result's `cleanupPending()` and asynchronous `cleanup()` retain
unconfirmed resource recovery after failure. `close()` releases output handles;
it does not assert native cleanup or retry computation. Cleanup failure never
changes a failed strategy result into success. These are process-local resource
handles, not a general provisioning SPI, cross-DAG cache or durable recovery.

Explanation retains the last selected placement after environment cleanup.
`selection.dispatch_authorized` distinguishes that diagnostic history from a
currently authorized dispatch. Resident task entries include their shared
profile's preparation/cleanup estimates and import envelopes; repeated profile
descriptions are not additional charges. The whole-strategy assessment contains
the composed cost, while the ledger reports actual accumulated usage.
Outstanding environment cleanup is included even when all remaining choices are
Local. A live environment does not repeat setup; settled cleanup is no longer
charged, and unknown cleanup remains unknown in every affected candidate.

For native acquisition charged to the same graph ledger, use
`runStrategyNativeHostQuery(grant, ownedConfiguration, ledger, transportLimits, signal)`.
It reserves before source opening, charges metadata and both receipts, and returns
`usage`, declared `physicalCapacity`, `document()`, `openDAG(checkedGraph)` and
`close()`. `openDAG` transfers the retained capture into a matching graph once;
it does not accept serialized graph authority. The accounted entry deliberately
does not expose standalone `output()` or `source()` exports. Keep the capture open
until every intended root consumer has started/completed as required by the serial
runner. Closing it rejects new root reads; completed descendants retain their
independent results and necessary physical holdings. Unused reservation release
never refunds spent transfer or the attempt record. Evidence/scan retention
ceilings can make this envelope substantially larger than a Compute-only budget.
This native path is distinct from standalone borrowed capture and does not claim
automatic accounting for the broad Host entry.

For a runnable application using user-supplied files, see the
[checked serial strategy example](examples/README.md). It includes preparation,
the standard Host driver and explanation output without conformance dependencies.

To drive a selected finite DAG without fixture-specific per-task calls, construct
an owned `duckdb_host.StrategyHostDispatch` with `configure_strategy_dispatch` and
call `runCapturedStrategy(setup, transportLimits, importLimits, signal)` from
`strategy-host.mjs`. The generated sequences must belong to the exact checked
tasks. The driver reads the current strategy; it does not choose a fallback or
invent an input before its producer completes. Its returned `status` is
`host-tasks-completed` or `host-tasks-failed`, not Program/Run success. `completed`
records which tasks this invocation executed, `failure` preserves the original
error/cleanup handle, `usage()` reads the same cumulative ledger, and `output(task)`
is an internal Host handle for a still-retained completed result. Call `close()`
to close task output ports; close the owned capture separately. A failure never
authorizes continuing an unstarted branch or publishing partial Program success.
For automatic bounded re-estimation, call MoonBit
`configure_dispatch_estimates(setup, profiles, searchLimits)` before any search.
Supply one `DispatchEstimateProfile` per Compute in checked task order. Its
Local/native rate lines cover the work inventory below, with optional fixed,
per-input-row, per-canonical-wire-byte and per-potential-pair millisecond coefficients. For example,
a Local bundle `{ work_slots: [0,1,2,3,4], fixed_ms: Some(1L),
per_row_ms: Some(2L), per_wire_byte_ms: Some(0L), per_pair_ms: Some(0L) }` estimates `1 + 2 * rows`;
it is a supplied model, not a measured performance claim. Native capacities are
explicit enforceable envelopes; Local capacities derive from execution limits.
Neither is inferred from estimated selectivity.

The installed policy copies all rate arrays. `output_rows_per_mille: Some(1000)`
forecasts no filtering until an actual completed row count replaces it; `None`
keeps that forecast unknown. Root row/wire counts reuse capture measurements.
For join, input-row and input-wire rates sum both ports, while `per_pair_ms`
uses the product of left/right row estimates (zero for non-join operations).
The join output fraction is relative to that potential-pair count, not either
input alone. These quantities do not authorize output growth or relax its guard.
Non-root wire size is unknown, and a nonzero wire coefficient therefore makes
that estimate unknown. A missing coefficient is also unknown, not zero. This
automatic policy defers rather than inventing an unknown-candidate priority.
Manual selection with explicit Host ordering remains available without installing
this policy. Dispatch refreshes only changed, unstarted state, with bounded
planning work and revision count. On refresh failure it does not use a stale
selection or repeat the same failed search on subsequent calls.

`explain(maxBytes = 65536, maxNodes = 10000)` returns a
bounded diagnostic object containing selection reason, selected task work bundles,
alternative capacity rejections, current ledger and ledger-at-selection. Duration
and byte quantities use decimal strings; unknown durations are null. The
`remaining_at_selection` estimate is not an elapsed-time measurement or a freshly
recomputed estimate after execution. `assessment_complete: false` identifies an
unfinished search, not a successful full comparison. These diagnostics are not
canonical Plan data, evidence or Program success permission.

Work-slot numbers refer to the corresponding adapter's disjoint serial inventory:

| Slot | Local filter/select | DuckDB fixed filter/select |
| --- | --- | --- |
| 0 | Preparation | Session/table setup |
| 1 | Receiving admission | Input transfer |
| 2 | Computation | Input conversion |
| 3 | Retained output | Native computation |
| 4 | Cleanup | Result transfer |
| 5 | — | Result conversion |
| 6 | — | Retention |
| 7 | — | Cleanup |

A bundle can cover several slots once. It is not counted again as separate
breakdown lines. Already consumed acquisition traffic is shown in the ledger;
remaining-task estimates do not manufacture an estimate for acquisition time.
`available_root_statistics` reports the live capture's already measured final
row count and canonical row-wire bytes, or null after root revocation. This is
not the validation-scan size or the Node transport-frame size and is not a guard
exemption. Reading it performs no additional source access or expression replay.

For bounded conditional comparison, configure `physical_strategy.configure_strategy_search`
before starting tasks, prepare owned estimates with `prepare_task_offer`, and call
`revise_strategy`. Read its selected registrations, remaining cost and candidate
rejection reports before preparing actual input-bound Compute candidates. Future
task estimates do not bypass runtime applicability or input admission. A completion
or physical resource-state change permits bounded reconsideration of unstarted
tasks; changing prices alone does not permit repeated search. Completed placements
and consumed transfer remain recorded. The selected Node task's transfer and
DB-memory ceilings cannot exceed the selected envelope.
`max_revisions` counts accepted searches, including failure and deferral.
Charged preflight rejects malformed offers, missing tasks, excessive combinations
and invalid priority permutations without consuming a revision; corrected requests
need no fake resource progress. An accepted search revokes previous dispatch
permission before enumeration. Its failure cannot resume the old selection or
repeat unchanged-state exploration. Host priority addresses original enumeration
positions, including rejected strategies, and is remapped after resource filtering.
Standard dispatch also checks static native expression/import eligibility before
cost comparison. `excluded_realizations` explains exclusions; unsupported native
expressions may still use a separately eligible Local realization regardless of
the supplied native price. Runtime owner/liveness/capacity checks still apply.

Native cleanup settles execution capacity while retaining the result reservation.
Successful completion atomically attaches its exact holding before publishing
task success. The reservation is private to that run/task/attempt; low-level callers
cannot supply a borrowed or undersized reservation. Failure alone does not settle
native resources: stop acknowledgement and explicit buffer disposal are separate.
Closing a Compute result revokes its port, but its holding is not released while
a DAG descendant still anchors it. `physical_strategy.close_captured_task_output`
releases a Local result port as well, allowing ancestor holdings to be collected.
The checked task stays completed even after its output port is released. The Host
must keep a port open for uses exported outside this run; arbitrary foreign handle
lifetimes are not tracked automatically.

Local task execution now derives its working/retention envelope through
`execution_relation.generated_sequence_capacity` from the selected immutable
execution and measurement limits. It reserves before calculation and retains
successful output through the same DAG lifetime handling. Future-task estimates
must cover these capacities; underestimated offers cannot enlarge their envelope
at dispatch. No logical budget is reduced to make a reservation fit.

The product configuration also derives `physicalCapacity.receiverScratchBytes`
for MoonBit transport decoding, admitted batches and final demand/output checks.
`executionBytes` is the total DB, Node scratch and receiver scratch reservation.
Native cleanup releases only the DB/Node portion; receiver scratch remains until
success or failed-buffer disposal. A partial settlement cannot enlarge capacity.

This is not yet a complete Host physical-budget runner: acquisition integration
still needs accounting. Internal task outputs do not authorize partial
publication of a failed Program.

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
The MoonBit `connectors/duckdb/adapter` also emits exact prepared parameters from admitted
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
