# Local DuckDB Relation execution boundary

## Responsibility and scope

The initial real-backend increment realizes the existing checkpoint-free
scan/filter/select acquisition and fixed-input filter/select Compute. It uses
the [query boundary](query-residual-execution.md) and
[completion boundary](execution-completion-storage.md), rather than deriving a
second canonical Program or Plan. Backend registration, estimates and placement
do not modify the checked acquisition or its identity.

The additional fixed-input group/count profile is described under
[exact-count realization](#fixed-input-exact-count-realization). Its execution
support is distinct from general DAG placement and resident-reuse support.

MoonBit owns requirement matching, SQL compilation, type compatibility,
preservation conditions, logical accounting, completion and evidence validation.
DuckDB-specific translation belongs in an adapter, not in the common planner.
The initial internal capability interface is not a stable public Connector SPI.
Acquisition and Compute remain distinct, even when one module provides both.

Smooth Cloud's connector implementation at `55b83448a` provides examples of
provider-local query translation, field envelopes, metadata prerequisites,
paging limits and typed Parameter materialization. Its separate DuckDB data-plane
route is not the registration model adopted here. Neither provider-specific date
helpers in a shared SPI nor implicit ordering repairs become ActQL rules.

Semantic Read/model interpretation is outside this boundary. ActOntology is a
separate implementation direction, not an implicit layer in capability matching
or SQL generation. Possible future View-like language integration requires its
own semantic design; it is not anticipated by adding ontology-specific requests,
resolution rules or fields to this initial execution interface.

The optional Node adapter pins `@duckdb/node-api` to `1.5.5-r.4`. It owns native
connections, prepared statements, exact physical value transport, cancellation
and cleanup. Neither Neo classes nor connections cross the common MoonBit port.
Node is an implementation choice for this adapter, not a mandatory runtime or
distribution decision for the final Local Host.

### Canonical requirement binding

`connectors/duckdb/acquisition.prepare_duckdb_query` retains the exact `QueryRequirement` and
derives provider scan/native preparations from its owned query sequence. SQL
generation and comparison rules remain in `connectors/duckdb/adapter`; this connection
does not rederive a canonical acquisition or grant access to a database path.
The separately selected broad residual consumes the requirement's output-row
and value-byte guards through the existing query execution boundary. Equivalent
requirement CIDs do not authorize exchanging input from a different owner.

Native compilation and the static root-byte witness are preliminary eligibility
checks, not a runnable strategy or a complete obligation discharge. Logical
work/live-root applicability, Host authorization, read-view and full-scan
validation, physical budgets, retention and capture evidence are separate
requirements. An unavailable native preparation does not invalidate a supported
broad residual, and execution failure never silently selects that residual.

The initial mixed acquisition comparison retains a provider binding alongside
each exact requirement. `choose_acquisition_candidate` compares only common
duration estimates, without inspecting that binding. Mock and DuckDB-broad
factories establish their own work inventories; DuckDB-broad includes session
and catalog setup, source scan, receipt transfer/conversion, Local residual,
capture, retention and cleanup. Bundles and their component estimates cannot
both charge the same slot; a missing scope produces an unknown estimate.
Unknown estimates defer without explicit Host preference, and complete ties
honor that preference. A proposal retains the exact provider preparation for
subsequent Host dispatch; it is neither execution evidence nor authority.
Native DuckDB is not included as an eligible mixed candidate merely because
its preliminary compiler/root checks passed. General applicability/obligation
coverage remains a separate integration requirement.

`CapabilityRegistry` owns immutable module descriptions and exact registration
handles. A module may declare Acquisition and fixed-input Compute independently;
the latter declaration cannot be used to construct an acquisition candidate.
Registration is bounded pure Host setup, not source permission or evidence.
Another registry with identical names and descriptions is a different owner.
Closing a registry disables future proposals and typed dispatch recovery; it
does not cancel running work or invalidate already completed observations.

The common candidate contains a registration, exact requirement and cost, not
a backend enumeration or type-erased provider payload. `PreparedAcquisition[T]`
keeps the provider's typed payload alongside that exact candidate. After common
selection, only its matching preparation recovers the payload for Host dispatch.
Mock and DuckDB factories validate their own bindings and work inventories; the
mock adapter preserves the common selection reason without a second comparison.
The common planner does not acquire a new branch when a provider is added.
Registration alone does not complete applicability, logical obligations or
execution evidence, and no generic executor is introduced by this boundary.
Typed work enums may remain provider-local. Start obligation coverage with the
existing source-validation/filter/select occurrences; completion coverage and
auxiliary physical work are not substitutes for these logical duties.

The Host-private `DuckDBComputeAttempt` binds an owned selected candidate to
its exact fixed input, common capacity, receiving buffers and completion port.
Input measurement precedes backend execution. Receipt sealing precedes trusted
transport settlement verification, demand/output checks and final completion.
The engine's trusted output port is prepared before execution and uses a fixed
internal verifier; callers cannot pass replacement output rows or proof JSON.
The low-level transport verifier installation remains trusted Host bootstrap,
not an ordinary Connector capability or a Program callback.

Only a live settled attempt with matching receipt, demand and capacity handles
may yield `CompletedOutput`. This completion publishes only the final target and
can be bound through the ordinary producer/consumer path. Duplicate completion
and abort after success do not revoke the successful result; explicit close
invalidates its live provenance and blocks new consumer execution. A downstream
result that already completed remains independent. The attempt stores a success
flag rather than its own completed output, avoiding a completion/attempt cycle.

The standard Node fixed-Compute assembly accepts only an opaque configured
candidate and transport/import allowances. Its trusted bridge loads the fixed
product MoonBit runtime and privately installs the exact settled attempt/port/
receiver/session verifier. It supplies no source grant or connection to the
isolated memory DB. SQL generation, physical parameter encoding, result admission,
capacity, demand and completion remain MoonBit responsibilities. No conformance
catalog, test export, alternate runtime or user verifier enters this assembly.
The returned output is the actual engine completion; public output access after
close is rejected, and retained handles fail subsequent producer admission.

Fixed-input Compute uses the same module registrations but a distinct owned
`FixedComputeRequest` and candidate type. The request retains one `ProducerRead`
for its exactly bound consumer, together with the exact pinned
`actql-consumer-capacity/0.1` CID and the Host-selected common row/value ceilings.
These limits apply to input and output independently; input rows cannot be
discounted because a filter will discard them. Value ceilings are per top-level
value, not per whole record. Binding the request is not proof of completed value
measurement or root enforcement.

An explicitly common fragment is retained by exact preparation identity. Local
must use that same preparation; equivalent reconstructed content is not enough.
The current DuckDB profile rejects such a selection before candidate comparison
because it cannot yet guarantee exact fragment work/live accounting. A fragment
chosen only inside a Local candidate does not become common retroactively.
The request has no source selector, connection, arbitrary
rows or content-CID reconstruction route, and does not create a canonical Plan.
Local preparation must have that exact consumer owner; the Local execution
operation delegates to the existing producer admission and sequence driver with
no supplied source inputs, preserving fragment limits and failure atomicity.
Each retry obtains a new execution budget without changing its completed input.
Local execution additionally enforces the request's common capacity using the
engine's fixed-producer guard operation. A separate physical measurement ledger
spans all input top-level values, root-ceiling preparation and final output
values. Root constraints are applied within the existing evaluator, not by
replaying expressions. The producer remains immutable and uses ordinary receiving
admission; measurement does not replace that admission or discount fragment work.

For execution outside the row evaluator, `FixedProducerMeasurement` performs the
same complete input value checks before execution and retains the remaining
physical budget until provisional output arrives. Finishing consumes the session
once, verifies the exact receiving owner, target and schema, and measures output
values using the remaining budget. Its measured-output handle matches the exact
input, output material and ceilings, not equivalent rows or CIDs. It proves only
input/output capacity: predicate demand, transport provenance and successful
execution remain separate conditions for trusted completion.

The restricted DuckDB fixed-input comparison shares operand and root accounting
with Acquisition's native comparison. It reads the exact retained input field,
measures the bound RHS only upon first demand, and derives true/false/NULL counts
from the received result count and operand nullness, without executing the
predicate in Local. Empty input has no RHS or root demand. The measurement owns
the exact compiled query, live receipt and byte ceiling. Result-count consistency
is not execution attestation; completion must separately verify that the trusted
transport actually ran that query against that fixed input. Measurement failure
revokes its own receipt, never a foreign query's receipt or successful upstream.

DuckDB preparation compiles an isolated temporary-table import and restricted
filter/select for the same retained input. The common comparison includes setup,
import/export, conversion, computation, retention and cleanup scopes. Selection
recovers only the matching typed preparation; native receiving, selected consumer
contract enforcement and opaque product completion are still separate duties.
Returning rows from DuckDB is not a substitute for those duties, and the
acquisition resource-scope clarification is not a blanket waiver for Compute.

The Host-private `DuckDBBroadAttempt` sequences metadata admission, receipt
admission/retention, transport settlement and guarded Local residual execution.
Sealing the receipt does not enable the residual: the trusted Node coordinator
must first observe completion of the same transaction's commands and successful
resource cleanup, then acknowledge settlement. Invalid transitions, cancellation,
admission failure and residual failure terminate the attempt and release its
pending references. An attempt is never retried with a different realization.
The resulting computation retains both full scan and output for subsequent
issuer verification; this lifecycle does not itself issue observation evidence
or authenticate a serializable claim that transport cleanup succeeded.

`DuckDBQueryIssuer` is registered by the trusted Host with the selected
requirement and a synchronous, read-only transport-ownership verifier. The Host
must bind that verifier to the exact authorized grant, attempt, port, read view
and settled source execution; neither user code nor wire data may supply it.
`prepare_issued_duckdb_broad_attempt` binds the issuer to the selected typed
candidate before access. It cannot attach authority after an unissued execution.
The issuer requires successful guarded residual execution, exact retained
scan/output handles and live transport verification before atomically issuing
the source-validation, filter and select records. Mock authority is not reused.

Broad capture uses the unchanged single-receipt observation schema and shared
canonical serializer. Scope/record and capture serialization share an artifact
budget. Binding a captured output verifies the exact issuer, attempt, issued set,
observation and transport association before ordinary producer admission checks
the receiver, target and Parameter owner. Failed consumers cannot cancel or
replace the successful acquisition. Cancelling pending execution is distinct
from explicit issuer/provenance revocation after capture.

The Node `runBroadQuery` coordinator supplies the transport verifier and only
invokes the synchronous semantic completion bridge after the actual source
transaction and cleanup have settled. The bridge performs MoonBit settlement,
residual, retention, issuance and capture, not JavaScript copies of these rules.
An accepted receipt belonging to another attempt is rejected. Explicit close
releases provenance; failed consumer binding does not. Transport sequencing and
semantic issuance are separate trust boundaries: a real-provider capture must
connect both to the same owned execution, not substitute an independent double
for either authority.

The low-level bridge factory and verifier registration are trusted Host assembly
operations, not Program inputs or ordinary Connector capability fields. A
standard product entry must assemble this bridge internally with the trusted
MoonBit implementation; it must not expose a per-call verifier override. Fixed
`connectors/duckdb/conformance` exports and its catalogs are test inputs, not
dependencies
of that product entry or its execution examples. A boolean returned by the exact
live-provenance verifier is distinct from accepting a caller's success boolean.

Broad and mock capture bindings retain exact issuer/attempt/observation liveness
through the engine's constrained-completion binding. They share completed data
without re-admission or full-row copying. Revocation is checked again when a
bound input or ProducerRead is used, not only when it is first created. Completed
downstream computations remain independent. Broad residual completion before
capture is package-private; the public diagnostic exposes only row count, not
a consumer-admissible CompletedOutput.

Issuer state machines share serial reservation, not their receipt state. Backend
issuer namespaces, per-issuer attempt counters, live authority and retained
receipt types stay distinct. Reservation checks exhaustion before incrementing
and never reuses a consumed number. Shared serialization and allocation do not
authorize cross-backend substitution of attempts, retained data or records.

After guarded broad computation, retention hashes the exact admitted scan and
completed output with the same bounded row-wire accounting used by mock. The
measurement byte/node budget spans both artifacts; an exactly exhausted scan
node allowance is output resource exhaustion, not invalid initial limits.
Receipt limits count the broad scan once, while retention counts both scan and
output without a sharing discount. A receipt limit already known to fail is
checked before output measurement. No values are readmitted or expressions
reevaluated for these hashes. The retained handle is valid only while the exact
owning attempt holds it; cancellation or failure invalidates that association.
Digest strings remain diagnostic data, not portable evidence or capture permits.

## Source and fixed-input isolation

`connectors/duckdb/host` owns reusable acquisition Host orchestration above
`connectors/duckdb/acquisition` and the DuckDB adapter. It accepts existing owned requirements, selected candidates,
admitted evidence contracts and explicit resource limits. It does not construct a
fixed Program/catalog, import conformance code, or derive another semantic Plan.
The conformance package supplies independent setup and expectations and invokes
this same Host orchestration for real Node execution.
Acquisition orchestration has no dependency on Local Compute, the generated
Compute bundle assembly, or the common adaptive Compute Host. Its configuration,
receipt state and declared receiver capacity belong to the DuckDB connector;
application-level Compute composition does not re-export these entrypoints.

`NativeHostRun` retains the exact issuer, attempt, compiled scan and active receipt
port. Receipt replacement, unfinished completion and unverified transport fail;
startup failure closes the newly allocated issuer. Consumer binding derives the
expected producer owner from the retained compiled query, not a caller-supplied
CID. Conversion/consumer rejection preserves an already successful observation.
Close is idempotent and revokes further use, whereas aborting unfinished work does
not retroactively erase an already completed capture.

The low-level Host startup takes a trusted transport verifier for runtime wiring.
The standard `adapters/connectors/duckdb/node/host.mjs` native entry installs that verifier
privately through the settled transport coordinator. Its configuration retains
already-owned preparation and limits, without verifier or SQL callbacks. It loads
the fixed `connectors/duckdb/host_node` product module, not a caller-selected runtime or
conformance fixture. Neither ordinary Connector registration nor Program inputs
can replace this wiring. The JS facade decodes raw transport frames using the
adapter's bounded physical decoders; type interpretation remains in MoonBit.
Typed failure results use the pinned compiler's JS ABI inside this private
facade only; this ABI is not a published cross-version Connector contract.
This restricts the standard entry, not arbitrary malicious code in the Host TCB.
The connector-owned Node bridge also drives fixed Compute and resident transport.
It does not depend on Local Compute or the standard multi-connector composition;
SQL, physical values and session-specific operations are not re-exported by the
composition bridge.

`BroadHostConfiguration` and `BroadHostRun` provide the corresponding broad
assembly using the existing one-receipt attempt state machine. The standard
`runBroadHostQuery` installs its private settled verifier and shares the bounded
physical transport decoding with native. It does not duplicate source validation
or evaluate the residual in Node. `complete_duckdb_broad_capture` verifies exact
live authority before state changes and sequences settlement, residual/guards,
retention, record issuance and capture. A failure aborts the unfinished attempt;
duplicate completion preserves an existing capture. Binding derives the expected
producer from the owned requirement and uses the existing captured-input API.
No additional full row copy or admission is introduced by Host assembly.

The Host supplies an explicitly authorized trusted local database binding.
Program Resource/SourceView descriptions alone grant no filesystem authority.
Only declared real tables are in scope; views, user SQL, extension loading and
external URLs are not source interfaces. Source connections are read-only;
read-only access is not a sandbox for malicious database files.

The native scan preparation retains the exact compiled query and its quoted
schema/table address. Its validation SELECT enumerates every known input column,
including columns absent from the final projection, without inserting a filter
or `SELECT *`. Validation and output receivers obtain their schemas from that
same owned checked pipeline (input port and final select respectively), rather
than independently supplied schema claims. Preparing these commands does not
prove that the physical address is a declared real table: Host permission,
catalog/schema checks and read-view ownership remain execution obligations.

The Node native-read orchestration runs a catalog-only metadata command, the full
validation scan and the native query within one source session. It waits for the
MoonBit-facing validation callbacks to finish before dispatching the native
command. Empty receipts still call schema preparation. Both row receipts receive
the same unique private read-view discriminator; this object has no connection
methods and is not a snapshot token. Reusing the same port to restart an attempt
is rejected. Any failure, including cleanup failure after the callback returns,
notifies the receiver's abort path. Transport deltas for each receipt exclude
catalog metadata while the cumulative session ledger includes it. These deltas
remain physical frame metrics, not canonical typed-wire receipt measurements.

Metadata verification, full known-scan validation and the result query use the
same connection and read transaction. A path or modification time is not a
snapshot identity. Capture retains immutable completed data; a downstream retry
uses that capture, not a fresh source read.

Compute uses a separate Host-owned database with only completed fixed inputs
imported into it. It cannot receive the source connection. Temporary resources
belong to an attempt and must not mutate the original database.

Fixed import preparation consumes the engine's opaque bound producer read view.
It generates quoted CREATE/INSERT statements from the receiving schema, preserving
nullability and exact scalar types; values remain separately bound parameters.
SQL construction has one cumulative byte ceiling for both statements. The view
retains its upstream completion and supplies one receiving cell at a time without
reconstructing a whole row or repeating value admission. Transport construction,
import work and receiving logical checks remain separately required. A zero-column
Relation is currently ineligible for this DuckDB table representation rather than
being silently converted into a different schema or row count.

`FixedCompute` prepares the import and filter/select query together from the same
owned producer view and table name. Callers cannot pair an independently compiled
query with a different receiver through its constructor. The trusted Node port
executes creation, row-wise parameter import and the query in one fresh Compute
transaction. Import row/cell ceilings are checked before allocation and commands;
parameter construction is bounded by the current row, not the full Relation.
Native chunks are provisional receiving data, not completed engine output.

`FixedComputeReceiving` binds result metadata and all chunks to the exact compiled
`FixedCompute`. The receiver validates the final checked schema, counts cumulative
physical values, and retains immutable admitted cells under a separate row/value
allowance. Filter/select cannot produce more occurrences than its fixed input;
that bound is checked before chunk admission. It is necessary but is not semantic
attestation. No source address or acquisition receipt is accepted here.

`FixedCompute` retains an ordered import inventory rather than one implicit
input. A join realization binds the exact input handles, deferred preflight and
the checked join's authored output guard. The selected output ceiling may only
be tightened by that guard. Unlike filter/select, join output can exceed either
input's row count; cumulative physical chunk admission enforces its output ceiling
before retaining results. Common consumer input limits apply independently to
every input, while value measurement has one ledger across all ports and output.
Even two ports sharing a backing store have separate logical occurrences.

The fresh Node transport validates all input dimensions before creating its
isolated database, then imports each port into its bound table. Import row limits
are per input; imported cells and transfer accounting accumulate across ports.
The returned import totals describe actual copies, not unique content CIDs.
The standard completion path handles both unary and preflight-bound binary
realizations without a second issuer or a separate join completion type.

Sealing returns an opaque `FixedComputeReceipt` and releases the receiver's
provisional builder reference. Its rows remain provisional material, not engine
completion. Failures and cancellation are terminal and clear open retention;
revocation invalidates receipt access without changing the successful upstream
input. Import preparation, parameter reads, receiving and sealing recheck that
the bound producer remains available. A producer view retained before external
issuer revocation cannot silently authorize a later Compute import.

The completed-input Compute resource contract is selected independently of source
acquisition. The acquisition-specific native exemption must not be reused to
discard an explicitly selected consumer fragment contract. Physical result
admission and retention do not resolve that contract selection or replace exact
consumer guard enforcement.

Raw column JSON enters through `decode_transport_columns`, not the authoring
parser's NFC/LF normalization. A nonrecursive preflight limits input UTF-8 bytes,
JSON nodes, columns, rows per column and nesting before JSON allocation. Only
arrays of null/boolean/string physical payloads are accepted; numbers cannot be
implicitly rounded by JSON decoding. Decoded UTF-8 text has a cumulative frame
ceiling. Malformed input produces typed transport issues, not a process abort.
These per-frame decoder limits are distinct from cumulative receipt/session
limits and typed value admission; a successful decode is not a validated receipt.

Fixed Compute transport records the exact attempt port, receiving callback and
actual closed Compute session only after command execution, transaction settlement
and cleanup succeed. A port is one-shot, including after admission failure or
cancellation. Reusing the immutable completed input requires a new attempt port
and fresh budgets, not reviving the previous attempt. Copied result objects,
another port, or a replacement receiver do not establish that relationship.
Explicit release revokes this transport relationship without invalidating another
successful attempt. This record is not semantic completion evidence: the trusted
MoonBit completion bridge must additionally bind the selected realization, exact
fixed input, guards, retained output and successful checks. No source grant or
source connection is part of the Compute record.

Successful fixed Compute seals its exact admitted output only after demand,
receipt, input/output guards, ownership and trusted completion-port verification
succeed. Before that transition, upstream availability is mandatory. Afterwards,
output verification uses the sealed rows and this Compute's own live transport
and retention, not the upstream input's current availability. Closing an upstream
capture cannot revoke independently completed Compute results; closing the
Compute itself still prevents new downstream admission. Already completed
downstream results keep their independent lifetime. Sealing shares the retained
rows without copying or re-admission and cannot be supplied by a caller boolean.

## Type transport and native expression support

Physical transport and expression support are separate decisions. The transport
carries exact physical values and type descriptors to MoonBit, where the existing
admission and canonical value contracts apply. It does not normalize text, round
decimal coefficients or interpret naive timestamps in Node.

| Input type family | Required initial mapping |
| --- | --- |
| BOOLEAN | Preserve boolean and NULL distinctly. |
| VARCHAR | Preserve exact text; apply pinned text admission in MoonBit. |
| Integer | Preserve the integer exactly across Node; admit as number only when losslessly representable under the selected ActQL type. |
| Floating point | Preserve physical value; ActQL number admission rejects nonfinite values. |
| DECIMAL | Preserve signed coefficient, precision and scale without JS Number conversion. |
| DATE | Convert losslessly to the admitted Gregorian date domain. |
| Timestamp | Require an unambiguous instant and lossless UTC millisecond conversion. Reject submillisecond loss, infinite values and implicit timezone interpretation. |

The mandatory native predicate subset is direct finite-number comparison or
boolean equality against a constant or an owned Parameter, including NULL.
Other expressions may use the existing Local residual when supported. Backend
ineligibility is not a language restriction. Once execution starts, failure is
not permission to switch candidates or hide a mandatory failure.

Native acquisition performs the predicate and projection in DuckDB. It still
needs full known-scan validation and applicable logical guards before capture.
Additional validation reads, transfer and retention are real work and must be
recorded and budgeted. Conformance compares against independent expectations and
Local execution; successful native execution does not require replaying the whole
Local filter/select on each production call. The alternative completion seam
must bind the exact checked owner, fixed input, output and completed checks; it
must not accept arbitrary rows plus a claimed CID as proof of execution.

The native compiler consumes one owned two-step lowered filter/select sequence.
It retains that exact owner, quotes table/column identifiers, and binds literals
and already resolved Parameters rather than embedding their values in SQL. A
numeric input comparison explicitly uses the DOUBLE domain after full-scan
admission; transport support for DECIMAL or timestamps does not grant native
comparison support. Unsupported expressions require a separately offered Local
residual, not a mid-execution fallback.

Physical result admission prepares a field-to-schema mapping before reading any
rows, so empty and all-NULL results do not bypass type eligibility. Each decoded
column chunk must have the prepared width and declared row count. Scalar checks
run in logical schema order within each row, independently of transport column
order, and use the existing physical conversion and shared value admission once.
Value-node and text usage accumulate across chunks; row/cell ceilings preflight
batch construction. A failed or cancelled receiver is terminal. Accepted batches
retain their exact receiver, but remain provisional: this handle validates values
only and cannot attest SQL semantics, source consistency or successful capture.
Its scalar/transport budgets do not replace row-container, logical guard, retained
storage or native work accounting. The Host must bind the receiver to the exact
statement/attempt and its fixed metadata rather than reuse it for another query.

Native receiving owns the two physical receivers and their admitted batches.
It requires exactly one `BASE TABLE` catalog result before validation, seals the
validation receiver before opening the native receiver, and subtracts validation
usage from the cumulative row/cell/value-node/text ceilings for native reception.
Receipt ports retain their exact parent; foreign ports and invalid transitions
cannot be used to continue reception. Abort cancels both receivers and drops
retained batches. Empty chunks do not accumulate retained batch roots. The
`has_both` readiness query describes this provisional state only: it is not an
evidence record, authority, native semantic proof or engine completion constructor.

Native receiving requires explicit value-byte and output-row ceilings. Each
admitted scalar is measured by the shared canonical wire emitter at receipt
finish, after full receipt admission and before enabling the next phase. This
matches the Local fixed-input admission-before-guard boundary; a later admission
failure is not hidden by an earlier value guard. Retained values are read without
copying, re-admission or predicate evaluation. The ledger spans both receipts:
one work unit per logical row and cell, plus bounded emitted bytes, nodes and
depth. Zero remaining nodes is measurement exhaustion, not invalid initial
configuration. Value ceilings include NULL and fields unused by filter/select;
native output-row ceilings do not restrict validation scan cardinality.
Failures identify receipt-relative global row and schema column (`-1` for a
row-level check), and abort both provisional receivers. These checks do not
evaluate a predicate again. They also do not discharge demanded expression-root
ceilings, evaluator logical work/live-root obligations, canonical whole-receipt
measurement, or completion/capture checks. Chunk admission and physical capacity
checks remain distinct from the per-value logical guard.

The single-receipt process-evidence profile represents a single logical received row
sequence. A full scan exported to MoonBit for validation and a separately exported
native query result are two actual receipts. They cannot be combined, hidden as
internal engine work, or represented only by the selected output. This path uses
the separate [two-receipt profile](../spec/execution.md#query-two-receipt), not an
extension of the single-receipt observation shape. A single broad receipt reused
for validation and residual continues to fit the original profile.

This two-receipt implementation does not reduce Host row transfer: it receives
the full validation scan plus the native result. Candidate estimates and actual
accounting must include both receipts, validation/conversion work, retained
material and cleanup; projected result size alone is not the cost. Whether total
elapsed time is better or worse also depends on computation and is not established
by this transfer fact. The baseline is a conformance path, not a speedup claim.

Provider-internal full validation is already permitted by the query-acquisition
and Host-adapter contracts when supported by verifiable execution evidence.
Avoiding the exported validation scan is therefore first an implementation/evidence
question, not automatically a new SourceView type-guarantee semantic feature.
Any internal implementation must close the following correspondence before use:

| Obligation | Potential DB evidence | Additional ActQL check/evidence |
| --- | --- | --- |
| Declared fields and nullability | Real-table catalog, stored types, applicable constraints | Exact SourceView mapping and every nullable/nonnullable contract; no coercion hiding invalid input |
| Exact scalar values | Storage type and relevant enforced constraints | Integer-to-binary64 exactness, DECIMAL precision/scale, finite numeric/temporal values, timestamp precision and timezone rules, text admission |
| Value-byte guards | Not established by schema or `NOT NULL` | Pinned canonical typed-value encoding and demanded-root byte rules, including escaping and nonselected scan columns |
| Full extent before predicate | Validation over the bound source extent | Validation plan cannot skip filter-excluded rows or unused known columns; failure demand remains preserved |
| Same read view and completion | Same owned read transaction | Live provenance for exact requirement/task/attempt/session, validation completion, result and retention; SQL success or a boolean alone is insufficient |

The single-receipt trusted-issuer route can represent internally validated native
output; the two-receipt route describes actual row receipts and must not be reused
for summary-only validation results. A concrete internal validator must first
demonstrate equivalence to the baseline using independent invalid-value, precision,
byte-boundary and ownership fixtures. Only an identified evidence-contract gap is
sent to main; the baseline implementation remains the immediate priority.

`coverage.complete: true` stays the closed completed-observation constant. It is
emitted only after the required source-validation/filter/select records and live
ownership checks succeed. Candidate obligation coverage is a different concept.
The logical duty is source validation; an extra scan/transfer is physical work
used to discharge it, not a reason to discard or relabel its receipt provenance.

The validation receipt contains all known scan fields and rows; MoonBit admission
must finish before the native query runs. The native receipt contains the complete
checked filter/select output. Both belong to the exact same authorized attempt
and owned consistent read view. A process-local read-view identifier distinguishes
execution evidence but neither replaces the live transaction handle nor creates
a source snapshot identity.

Each receipt hashes its own ordered typed-wire rows and records its field set,
row count and canonical byte count. Aggregate receipt budgets charge the two
transfers once each, using checked sums. Retention copies, transport frames and
engine work have separate accounting scopes. In particular, Node transport-frame
bytes are not a substitute for canonical typed-wire receipt bytes.

The adapter can identify the two retained, fully admitted receipts without row
materialization. It uses the engine's bounded immutable canonical column order
and shared typed-value wire emitter. Writer byte/node/order limits are cumulative
across the two hashes; received row/byte ceilings are independently enforced.
An empty receipt still hashes `[]` and consumes two bytes and one writer node.
The opaque pair retains its exact receiving owner. Aborting that owner invalidates
the matching check even though diagnostic digest strings remain readable.
Neither the pair nor its JSON projection is an execution record or capture
permit: task, attempt, read-view, native semantic and completion checks still
belong to the issuer/verifier integration.

Both receipts and the three execution records become issuable only after value
validation, native semantics and guards, budgets and immutable retention succeed.
The capture verifier must resolve the exact live handles, including task,
attempt, read view and retained output; hash-correct bodies alone do not grant
capture authority. Cancellation or failure is terminal. These are adapter
integration obligations: availability of the shared profile does not establish
real-backend execution conformance.

Canonical record material construction is shared independently of issuance.
It consumes already measured immutable row identities and the bound requirement,
preserving cumulative encoding budgets and the existing wire preimages. This
private serializer cannot establish a read view, authorize an attempt or issue a
record. Provider-specific issuers must verify those live relationships before
using it; reusing serialization does not reuse a mock issuer's authority.

## Lifetime, limits and publication

Native acquisition uses the same owned capability registrations and candidate
comparison as broad acquisition. Its typed payload retains the exact requirement,
compiled scan and root-bound witness; another preparation with equal contents
cannot recover a selected choice. The common planner does not branch on a
DuckDB enum. Provider-local work slots distinguish session/catalog, validation
scan/transfer/admission, SQL filter/select, native transfer/admission, demand
measurement, capture, retention and cleanup. Omitting either transfer or retention
leaves an unknown estimate rather than a free operation.

A selected `DuckDBNativeAttempt` supplies the requirement's common guards to its
receiver, instead of accepting caller replacements. Receipt ports belong to that
exact receiver. After both receipts and trusted Host settlement, exact demanded
values and both retained receipt identities are measured without Local predicate
replay. Physical measurement, canonical receipt and common acquisition limits
remain distinct. Failure aborts the attempt and invalidates its measurement;
measurements cannot be attached to a different attempt or retried after failure.
Settlement acknowledgement and these diagnostic measurements are not record
issuance, source authorization, live read-view attestation or product completion.
Those additional boundaries are required before capture can publish native output.
The Host-local two-receipt contract already provides the required authority
profile for this all-rows-received implementation. External-provider attestation
or a new validation-summary contract is not a prerequisite. Avoiding full-scan
transfer is a separate internal-validation improvement, not a completion gate
for the two-receipt path.

`DuckDBNativeIssuer` admits the complete two-receipt contract with its already
admitted acquisition and process-evidence dependencies under one contract budget.
It binds the exact selected native preparation before metadata access and reserves
an attempt-local read-view discriminator. The discriminator is not a snapshot CID
or self-authenticating token: the trusted bridge must verify its association with
the actual two-receipt execution and settled read transaction.

Issuance verifies that live association, exact owned measurements and the combined
retention ceiling, then atomically serializes two receipts and three records.
The two row transfers remain separately identified and counted even when their
contents happen to coincide. Capture uses the separate two-receipt observation
version and requires the exact issued-set handle. Artifact bytes/nodes include
both receipts, all three records, their hashes, the capture and request rehash;
no writer resets the shared allowance. Failure discards pending authority state.
After capture, cancellation of pending work cannot discard the observation;
explicit issuer or transport-provenance revocation remains effective.

The Host orchestration operation `complete_duckdb_native_capture` keeps settlement,
exact measurement, retention validation, record issuance and capture in MoonBit.
It accepts a live issuer/attempt and separate Host-selected physical/material
allowances, not a replacement transport verifier or common guard. Foreign issuer
requests are rejected before mutating the rightful attempt. An unverified or
failed completion becomes terminal; a duplicate call cannot invalidate an already
captured observation. Existing low-level stages remain available for independent
boundary tests. Host bridges should use the orchestration operation rather than
implement their own semantic stage sequence in Node or a fixed conformance setup.
This operation creates an acquisition observation, not an engine CompletedOutput.

The native observation retains immutable native receipt data without constructing
a row-engine completion from caller-supplied rows. The separate
`complete_duckdb_native_output` bridge installs an exact live-observation verifier
and connects retained data to the ordinary producer/consumer boundary. The
observation document or CID alone cannot supply it. Portable issuer tests do not
replace real Node bridge conformance.

`materialize_duckdb_native_output` obtains data only from the exact receiver
retained by a verified live observation. It does not accept replacement rows,
content identities or a caller-supplied success verifier. The returned handle
retains the issuer, attempt and observation; reading its material rechecks those
relationships and rejects revoked provenance.

For a row consumer, this explicit conversion creates bounded row containers while
sharing already-admitted immutable values. It neither decodes values nor evaluates
the predicate again. `AdmittedOutputRows` records the exact checked target and
uses the same value accounting as fixed-input retention, including capacity
checks before cell reads. It is deliberately neither `CapturedRows` nor
`CompletedOutput`: importing valid values does not establish execution success.
A failed conversion releases its provisional containers but preserves the
successful source observation. Retrying uses fresh conversion allowances and
never reopens the source. This conversion allowance does not discount receipt,
capture or subsequent consumer charges.

### Trusted external completion boundary

The row engine does not import acquisition or provider contracts.
`TrustedOutputPort` is low-level **trusted Host wiring**, not an ordinary
Connector registration surface. Its installer chooses a synchronous, pure
verifier that returns exact immutable retained material for live execution proof.
Installing an arbitrary verifier grants trusted-runtime authority; the low-level
API does not claim to make malicious Host code safe. Program inputs, JSON/CIDs
and ordinary Connector registrations must not supply that verifier.

The DuckDB bridge installs its verifier internally, without a caller override.
The engine independently checks exact bound owner, final target, schema and
retained-output selection. It publishes only the final retained target, not
unmaterialized intermediate steps. It keeps the verifier, proof and material
alive together and rechecks them on producer binding, producer-read preparation
and receiving execution admission. Revocation after binding therefore prevents
starting a new consumer. An already successful consumer retains its immutable
result independently; revoking upstream authority does not retroactively erase it.

Imported admitted values use a private completed-storage adapter, sharing the
already charged row containers without a second full conversion or admission.
Ordinary producer accounting and receiving execution remain mandatory. Projection
and row selection use the existing physical execution path and its budgets;
expression continuations are not part of the completion boundary. A standard
product Host assembly must restrict trusted wiring exports independently of the
fixture-based conformance setup.

The [acquisition resource-scope contract](../../spec/contracts/actql-query-resource-scopes.json)
separates common acquisition guards from selected fragment bounds. This native
scan/filter/select implementation does not select the Local residual fragment
contract and does not synthesize ordered-derive `row_kernel_limits`. It must
still enforce the exact acquisition output-row and per-record typed-wire guards,
full admission and checked demand. Per-cell measurement alone does not establish
the whole input-record ceiling. Local residual and downstream consumer fragments retain
their own unmodified limits. A Local-only fragment exhaustion need not prevent
native success; neither path can waive an explicitly selected common contract.

The Local acquisition guard checks every demanded expression result, including
intermediate operands, at the shared expression-result event. It reuses the
existing root lease's exact typed-wire measurement without re-evaluation or a
second charge. Undemanded branches and empty input create no such results.
The final-root-only consumer guard remains separate, and neither mode changes
the selected fragment's work, live-root, input-row or value limits.

For the restricted compiled comparison, a static root-byte witness can establish
the final predicate's byte bound without evaluating input rows: Boolean/NULL results need
at most five canonical bytes, or four when the exact bound RHS is NULL. A smaller
ceiling makes this native realization ineligible; it does not make the checked
query invalid, and Local residual remains a separate candidate. The witness
binds the exact compiled query and selected ceiling. It discharges neither scan
admission nor work/live-root limits, provenance, retention or completion, and it
is not an execution record. Generic receiving readiness alone does not imply
that this native eligibility check has been applied by a planner.
This final-result bound is not complete evidence for demanded operand values.
`measure_native_demand` measures the retained predicate field and the owned
literal/Parameter RHS under the same acquisition ceiling. It measures that
immutable RHS once at first demand; the recorded row count represents its
logical multiplicity. Empty input has no operand or predicate demand. A separate
explicit physical measurement budget accounts for this additional work without
borrowing or resetting receipt, fragment or consumer budgets.

For the admitted single eager number comparison or boolean equality, NULL result
occurrences follow operand nullness, true occurrences equal SQL output rows and
false occurrences are the remainder. The measurement records their exact byte
totals without evaluating the comparison again. Impossible counts are rejected.
The result retains the exact receiving owner and is invalidated by cancellation
or failure. This algebraic measurement is not provider execution attestation:
issuance must also establish that the owned SQL ran on the owned read view,
that retained receipts correspond to it, and that all other guards succeeded.

## Fixed-input exact-count realization

Fixed Compute SQL has its own owned `FixedQuery` representation. Its
filter/select alternative wraps the existing compiled comparison; its
group/count alternative retains the exact checked grouping/count descriptor.
Acquisition still uses `NativeQuery` and does not absorb grouping. The output
target and SQL parameter count come from the selected realization, not a
hard-coded second step or a fabricated comparison parameter.

The exact-count profile accepts row count and direct-field non-NULL count.
It retains repeated grouping occurrences and explicit `distinct: false`;
aggregate expressions, aggregate filters and `distinct: true` are outside this
realization. Direct-field counts have no expression root. Their fixed-input
demand record therefore differs from comparison-demand measurements; ordinary
input/output value guards, transport validation and retention remain mandatory.

Local execution shares stable index ordering and scalar comparison across
storage layouts, then constructs retained output through the ordinary sink.
Native execution performs `GROUP BY` and `COUNT` in DuckDB. Both preserve the
canonical group order rather than first encounter. For text keys the SQL
sorts lists of UTF16 code units, including surrogate pairs, instead of relying
on DuckDB's default binary VARCHAR order. These helper lists are physical
scratch, not new logical fields. Their cost and retention are not free.
All grouping, count-field and ordering references are qualified through the
input table alias, including the UTF16 helper. Output aliases cannot capture
grouping-key references through DuckDB's case-insensitive identifier lookup.

The current table representation retains logical field names. ASCII-case
collisions remain legal ActQL schemas, but cannot be imported into DuckDB tables
or materialized as resident outputs without a physical-name mapping. These
realizations are excluded before cost selection; the resident compiler also
rejects them at its low-level boundary. Fresh output transport may retain such
names without CTAS, and Local remains eligible. No execution-failure retry or
logical schema renaming substitutes for this static check.
DuckDB documents its [binary collation](https://duckdb.org/docs/current/sql/expressions/collations)
and [positional LIST comparison](https://duckdb.org/docs/current/sql/data_types/list);
the adapter is responsible for the ActQL-specific code-unit transformation.

The current fixed-import row count is Int-bounded, so each exact count is
representable in binary64. `CAST(COUNT(...) AS DOUBLE)` relies on that admitted
input bound; it is not a general count-overflow rule or a language-wide limit.
Keyed output cannot exceed the input row count. Global count must emit exactly
one row even for empty input, and its output still has an independent common
row/value ceiling. A missing global result cannot be sealed as a successful
receipt. Zero-column SQL output still needs a dedicated transport adaptation;
that shape is explicitly ineligible for this DuckDB realization, not invalid
ActQL.

Completion seals this Compute's own retained output only after common guards,
exact ownership and trusted transport succeed. Later upstream revocation does
not invalidate that independently completed result. Closing the result's own
attempt still prevents a new downstream computation. This extension does not
grant group/count a general DAG placement or resident-reuse guarantee merely
because its SQL can be compiled.

## Failure and resource lifetime

Cancellation request, the caller ceasing to wait, confirmed query termination
and resource cleanup are distinct states. Cancelled or failed attempts cannot
issue success evidence or capture. A connection whose stop is unconfirmed is not
reused. Managed row, transfer and retention limits are enforced independently of
logical guards and cost estimates. DuckDB's memory setting is not a hard bound
on total process RSS. Process isolation, forced-stop deadlines and durable
crash recovery are outside this initial increment.

The native standard Host treats `execution_bytes` as the DuckDB engine share,
not as the entire execution reservation. The common driver reserves that
share plus its separately derived import and transport scratch. The selected
engine share must be set as DuckDB's `memory_limit` before opening the
database; native and Node use the same canonical semantic settings and the
same physical capacity rule. `threads`, external access and access mode are
also explicit open limits. A successful ledger reservation does not imply a
process-wide RSS cap: the DuckDB allocator, transport scratch and other
process allocations remain distinct physical measurements.

The Node source-acquisition lifecycle retains an opaque completion relationship
between the exact Host file grant, one-shot port, read-view discriminator and
actual closed session. That relationship becomes available only after successful
command settlement and cleanup, and explicit release invalidates it. Copied
results or equal paths cannot reproduce it. This is transport provenance for
the trusted Host coordinator, not source snapshot identity or an ActQL record;
the MoonBit issuer must separately verify semantic guards, ownership and retained
scan/output. A consumer failure does not implicitly release this upstream proof.

Cross-task inputs are completed inputs only. Buffers and partial query chunks
are internal data, not publishable successful observations. Preparation,
conversion, import/export, auxiliary validation, computation, capture, retention
and cleanup belong in the candidate's accounting inventory; unknown estimates
remain unknown and inclusive estimates are not added to their breakdown twice.

General occurrence coverage, external attestation and durable replay require
their shared contracts. The current process-evidence schema is not replaced by
a backend's self-reported success flag. The accepted row layout and known
evaluation-performance regression remain unchanged; this increment does not
reopen the completed performance investigation.

## Fixed inner-join SQL boundary

The inner-join compiler binds the checked owner, ordered input ports, composite
equality pairs and projection. Its output is SQL preparation, not a native
completion or evidence that null/cardinality obligations have been discharged.
The preflight-bound realization uses the shared fixed-Compute candidate,
receiving, demand and completion path. The unary convenience compiler does not
infer a two-input realization from a single table name. Host-private preparation
must supply the exact ordered table inventory and an output ceiling. Automatic
two-input DAG dispatch and resident join reuse require their own input-location
and resource bindings; the SQL compiler alone does not establish those paths.

Each immutable input is projected into collision-free internal column names and
given `row_number() OVER ()` before joining. Explicit ordering by the left and
right ordinals preserves left-major/right-minor pair order, including duplicates;
it does not create a logical source-order proof. The adapter requires the
single-table, insertion-order-preserving input path described by
[DuckDB's order-preservation contract](https://duckdb.org/docs/current/sql/dialect/order_preservation).
The ordinal buffers and final ordering remain real physical work to account for.

Text keys use UTF-8 byte equality rather than session collation. Decimal keys
compare exact fixed-scale textual forms after removing only fractional trailing
zeroes. This avoids coercing two precision-38 operands into a common decimal type
that cannot represent both scales. Original projected values keep their types.
Numeric, boolean, date and timestamp keys use their admitted physical scalar
types. NULL keys do not match; a selected fail-null policy and cardinality
assertions still require independent pre-execution validation of both full inputs.
Output limits must fail before publication, never truncate SQL output with LIMIT.

Fixed join import preparation checks ownership and prepares imports, but does
not evaluate null/cardinality obligations. At attempt admission, common input
row/value measurement succeeds first; the same null/cardinality checks as Local
then run over immutable producer-column views. An oversized input value therefore
cannot be hidden by an earlier cardinality error from candidate preparation.
The preflight record belongs to
the exact receiving owner, prepared join profile and input handles; new work
requires their continued liveness. The checks do not construct joined rows or
repeat expressions. Physical preflight work and peak scratch have independent
limits, while import metadata limits span both ports. The attempt retains the
exact validation record and checks its correspondence before sealing success.
After sealing, the existing independent completion boundary no longer depends
on upstream liveness.
SQL preparation owns its table-name snapshot so caller mutations cannot redirect
an import away from the compiled query. These records are not output evidence:
common value/root guards, actual transport, output admission, output limits and
retention still belong to the completed Compute path.
