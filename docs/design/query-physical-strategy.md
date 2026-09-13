# Initial query physical strategy

`query_planning` consumes the owned local query preparation described by
[query residual execution](query-residual-execution.md). It neither derives a
canonical acquisition nor introduces a semantic Run, Invocation, approval or
commit scope. Its `QueryStrategy` is a Host-private proposal for the same query.
It is not a public Connector SPI or runnable Plan.

Two mock realizations implement the checked finite scan/filter/select shape:

- Native query evaluates complete source admission, filter and select inside the
  mock source, then receives the selected output.
- Broad acquisition receives the broad input, then performs complete admission
  and the checked local residual before the capture boundary.

Both invoke the existing evaluator, rather than duplicating predicate semantics.
Native query is not a weak prefilter: it cannot discharge filter by checking only
returned rows. Physical receipt limits can abort a broad attempt before a value
failure; the same receipt limits apply after source computation in the native
route. The source computation budget and receipt budget are separate.

## Tasks and accounting scopes

The physical proposal has `RealizeQuery` followed by `CaptureObservation`.
The edge requires complete query output; it does not permit task-to-task
streaming. Broad receipt and local residual are internal work in the first task,
not new semantic acquisition units. A fixed-input consumer belongs after capture,
not between these internal operations.

The serial cost inventory contains source work, completed receipt transfer,
receipt conversion, residual where applicable, observation capture, output retention
and cleanup. An inclusive
source cost may cover multiple disjoint inventory slots once; including both it
and a duplicate breakdown is rejected. Unknown or missing work estimates remain
unknown. They do not become zero or silently remove a residual/capture stage.
Transfer bytes, retained bytes and money stay separate from duration and from
each other. No estimate is a hard resource bound or preservation proof.

The common cost helper ranks complete estimates by latency. If any estimate is
unknown, an explicit complete Host-priority ordering is required to propose a
candidate; otherwise selection defers. Offers from a different prepared query are
rejected before comparison. Candidate order, price and route never modify the
shared semantic derivation. All shared runtime requirements remain visible and
pending even after a candidate has been selected.

## Mock execution and capture separation

The synchronous mock attempt copies only a bounded container of immutable source
cursors. No offer, estimate or selection performs I/O. This explicit supplied
finite source is an execution fixture, not proof that an external SaaS/DB source
was observed. Both routes use the ordinary local execution and immutable completed
output implementation. Input failures and expression failures remain typed.

`MockQueryComputation` retains the admitted full scan and completed local output
privately, with actual source
and received row/column counts. There is deliberately no public consumer-output
accessor. This intermediate is not a `completed_observation`, issuer record,
authority decision or capture success. Receipt cells are physical quantities,
not canonical wire bytes or the acquisition's logical row/value guards.

Full-scan admission and query execution share an opaque `QueryReceipt`, owned by
the exact query preparation. Keeping this immutable material allows a verifier
to inspect even native rows and columns not received by the Host without a
second admission or reevaluation. Reusing it still runs the driver's input
checks and accounting with a fresh execution budget. It does not establish
external source authority, a snapshot or successful observation capture. Its
retained capacity must be included in capture's physical retention checks;
reduced native receipt is not reduced full-scan retention in this mock.

The canonical rows identity is computed directly from retained input or completed
storage, not by rerunning a predicate or building a JSON row matrix. A bounded
column permutation emits object keys in canonical UTF-16 order while preserving
row order, duplicates, projection layout and zero-column row counts. Nested typed
values use the shared nonrecursive wire emitter; decimals remain fixed-scale
strings. Hash output is bounded by wire bytes, value nodes and container depth;
column metadata and comparison work have separate preparation bounds.

`RowWireIdentity` keeps its exact immutable receipt or completion owner. Matching
its CID does not imply matching that owner, an observation attempt or authorized
issuer. Its byte count includes the complete ordered JSON array and is suitable
for this profile's receipt-wire accounting, not allocator capacity or RSS. It
does not replace per-record/per-root logical limits or physical retention
admission. Failed hashing returns no usable identity and leaves retained data
available for a separately budgeted retry.

An attempt is one-shot. Failure never changes the selected route or rereads a
source. Cancellation is supported before computation and at the computation/capture
boundary, not during the synchronous evaluator. Cancelling an attempt discards its
references; it does not invalidate other owners' preparations or completed data.
An independently retained intermediate cannot itself authorize capture after the
owning attempt has been cancelled.

The [process-evidence contract](query-acquisition.md) owns the final issuance and
capture checks: authorize the issuer, allocate attempt identity, enforce all
logical/physical guards, retain output and resolve live role records. Local
computation success and row/column counters do not replace those checks. Serialized
JSON and matching hashes are not a source of authority. Until that boundary is
connected, the mock execution API exposes only an unpublished computation.

Real provider attestation, external transfer, durable capture, shared scans,
aggregate absorption, carried-input joins and general streaming need their own
increments. Relation-specific query support does not define all Connector ports;
carrier conversion remains semantic work, not a physical Transfer operation.

## Canonical boundary checks for later increments

These shapes check the boundary design; only the exclusive filter/select shape
has a shared derivation entry. Rows in the table do not independently establish
new canonical units or permit absorption through an existing barrier.

| Shape | Ports, observation and required boundary |
| --- | --- |
| scan → filter → select | Shared derivation owns one declared source input and the select output capture port. Query-internal residual stays before capture. A downstream fixed-input Compute consumes that exact retained observation. |
| scan → group → aggregate | Proposed source-to-aggregate acquisition needs main's absorption and numeric-observation/guard rules. Otherwise capture the source and run checked group/aggregate as later Compute. Neither choice is derived from price. Local group/aggregate kernels and their shared execution contracts are separate prerequisites. |
| One scan shared by two aggregates | One observation must own both consumers' input ports. A shared source capture followed by two Computes is a proposal; two independent fresh reads cannot replace it. A combined multi-output acquisition needs explicit common-observation and joint-completion rules from main. The current exclusive derivation rejects this shape. |
| Captured SaaS input joined with a warehouse source | A retained SaaS input port is fixed data; the warehouse input is a fresh declared source. Whether main derives a carried-input acquisition with output capture, or a separate warehouse capture and a two-input Compute, must be settled semantically. Physical staging/Transfer cannot turn the retained SaaS input into another read. Owned snapshot/port mappings and join execution are prerequisites. |

The same separation applies to Graph, Vectors and Events: a completed port retains
its carrier contract, owner and logical content. Physical relocation or encoding
does not become graph normalization, vector scoring, or an Events window/watermark
operation. Those require their own checked semantic work and demand/limit contracts.
An Events stream is not evidence that this completed-input task edge supports
streaming, and a Relation receipt limit cannot substitute for another carrier's
logical limits. General port support is not claimed by these Relation-only mocks.
