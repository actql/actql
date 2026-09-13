# Local DuckDB Relation execution boundary

## Responsibility and scope

The initial real-backend increment realizes the existing checkpoint-free
scan/filter/select acquisition and fixed-input filter/select Compute. It uses
the [query boundary](query-residual-execution.md) and
[completion boundary](execution-completion-storage.md), rather than deriving a
second canonical Program or Plan. Backend registration, estimates and placement
do not modify the checked acquisition or its identity.

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

`query_planning.prepare_duckdb_query` retains the exact `QueryRequirement` and
derives provider scan/native preparations from its owned query sequence. SQL
generation and comparison rules remain in `duckdb_adapter`; this connection
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
its preliminary compiler/root checks passed. General capability registration
and fixed-input Compute selection are separate integration requirements.

`AcquisitionBinding` is a transitional binding for the two connected
implementations, not the permanent extension mechanism. Common registration
must own binding identity, applicability, logical obligations, work inventory and
estimates while keeping provider payloads in the registered implementation.
Adding a provider must not require new semantic branches in the common planner.
Typed work enums may remain provider-local. Start obligation coverage with the
existing source-validation/filter/select occurrences; completion coverage and
auxiliary physical work are not substitutes for these logical duties.

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

## Lifetime, limits and publication

For the restricted compiled comparison, a static root-byte witness can establish
the demanded-root guard without evaluating input rows: Boolean/NULL results need
at most five canonical bytes, or four when the exact bound RHS is NULL. A smaller
ceiling makes this native realization ineligible; it does not make the checked
query invalid, and Local residual remains a separate candidate. The witness
binds the exact compiled query and selected ceiling. It discharges neither scan
admission nor work/live-root limits, provenance, retention or completion, and it
is not an execution record. Generic receiving readiness alone does not imply
that this native eligibility check has been applied by a planner.

Cancellation request, the caller ceasing to wait, confirmed query termination
and resource cleanup are distinct states. Cancelled or failed attempts cannot
issue success evidence or capture. A connection whose stop is unconfirmed is not
reused. Managed row, transfer and retention limits are enforced independently of
logical guards and cost estimates. DuckDB's memory setting is not a hard bound
on total process RSS. Process isolation, forced-stop deadlines and durable
crash recovery are outside this initial increment.

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
