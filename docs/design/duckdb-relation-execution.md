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

## Source and fixed-input isolation

The Host supplies an explicitly authorized trusted local database binding.
Program Resource/SourceView descriptions alone grant no filesystem authority.
Only declared real tables are in scope; views, user SQL, extension loading and
external URLs are not source interfaces. Source connections are read-only;
read-only access is not a sandbox for malicious database files.

Metadata verification, full known-scan validation and the result query use the
same connection and read transaction. A path or modification time is not a
snapshot identity. Capture retains immutable completed data; a downstream retry
uses that capture, not a fresh source read.

Compute uses a separate Host-owned database with only completed fixed inputs
imported into it. It cannot receive the source connection. Temporary resources
belong to an attempt and must not mutate the original database.

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

The current process-evidence profile represents a single logical received row
sequence. A full scan exported to MoonBit for validation and a separately exported
native query result are two actual receipts. They cannot be combined, hidden as
internal engine work, or represented only by the selected output. Such a path
requires an additional admitted multiple-access contract before issuing a
completed observation. A single broad receipt reused for validation and residual
continues to fit the existing profile. See the
[Host adapter and access rules](../spec/execution.md#query-acquisition).

## Lifetime, limits and publication

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
