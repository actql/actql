# Common Engine and Site Architecture Implementation Result

Date: 2026-09-18. Implementation commit: `120cd1dc`.
Baseline: `5a305f3ce5cdac421985fb9a71878bc22af51237`.

This report closes E0 through E3 of
`2026-09-18-engine-site-implementation.md` for local implementation
verification. Linux CI has not yet verified this commit, so this result is not
merge readiness.

## Implemented boundary

The common Host now models an Execution Site independently from a Connector
registration. A Site has its own identity, generation, admission state,
execution capacity, retained capacity, holdings, operations, and teardown
lifecycle. The same implementation can be advertised at more than one Site,
and one Site can advertise more than one implementation.

Candidate enumeration remains side-effect free. Candidate comparison includes
known startup, transfer, and execution costs and uses the existing stable
registration ordering for equal costs. Dispatch rechecks the selected Site
generation, registration revision, task, attempt, input authority, and
capacity before starting work. A stale or revoked binding is rejected rather
than retried automatically at another Site.

The common Host remains the only authority that commits task completion. A
Site executes adopted validation and representation work, but its response is
not completion by itself. Existing task execution, settlement, holding, and
cleanup state remains authoritative; the Site layer does not add a second Run
ledger.

## Explicit Transfer

Transfer is a managed operation rather than a language task. The initial
provider moves bounded row-wire batches from an immutable retained source view
to a destination-owned memory generation. It does not construct one array
containing the complete wire payload. Its typed success record binds the
Transfer attempt, both Site generations, both material generations, logical
views, codec, preservation rule, row and byte measurements, integrity mode,
and destination retention state.

The required standard path is covered on Node:

```text
checked fixed input -> Site A Compute -> managed completion
  -> explicit Transfer -> Site B Local consumer -> common completion
  -> reclamation
```

The source holding and the Transfer's source-use pin remain distinct. A failed
or cancelled Transfer retains the pin only while source access is unconfirmed.
Destination cleanup that no longer refers to the source cannot prolong that
pin. Destination reclamation remains independently accountable until it is
confirmed or successfully retried.

## Capacity and same-Site copies

Site execution and retained-byte ceilings are enforced as sub-scopes of the
existing Run accounting. Admission requires both scopes to fit and rolls back
the Site reservation when the Run reservation cannot be established. Existing
source retention is not reserved again. Destination allocation and temporary
workspace are charged where they exist, and a physically independent copy is
a separate allocation.

A meaning-preserving copy into another material is a Transfer even when both
materials belong to the same Site. Filtering, derivation, and aggregation
remain Compute. Sharing an immutable allocation with another holding does not
create a copy Transfer. Tests cover atomic Site reservation, holding lifetime,
and same-Site copy accounting.

## Integrity boundary

The adopted in-process memory codec does not compute a physical digest or a
logical CID. Its trust boundary is the Host-registered implementation moving
typed values and ordered duplicate occurrences from a verified immutable
source view into a new owned generation. The success record states that both
content digest and logical identity remain unestablished.

Independent fixtures reject value substitution, row reordering, and duplicate
occurrence loss. This contract does not generalize to mutable, untrusted, or
durable boundaries: those require a snapshot or immutability boundary,
authenticated expected integrity evidence, or storage-specific write/read and
retention checks respectively. A physical digest is not a logical CID.

## Lifecycle and failure coverage

The implementation covers foreign and stale bindings, task and attempt
mismatches, capacity exhaustion, cancellation during Transfer, delayed stop,
source mutation, Site and material generation mismatch, destination creation
failure, cleanup failure and retry, multiple consumers, one-sided reclamation,
and admission during teardown.

Site teardown first stops new admission, then permits existing settlement,
holding release, and cleanup retry. It does not complete while a holding,
operation, or reclamation responsibility remains. Site revocation does not
return unconfirmed retained or execution bytes.

Local, reference, DuckDB, Node, and Workers paths use the common Site surface.
The Local-only Node path does not require the DuckDB SDK, and Workers execute
their existing standard conformance path through the Site bridge.

## Local verification

The implementation tree passed:

- MoonBit tests: JS 4,522/4,522; Wasm 4,521/4,521; native 4,521/4,521.
- Retained boundary: 168/168.
- DuckDB Node: 127/127.
- Workers conformance: 7/7.
- Process capacity and accounting: 15/15.
- Documentation, contracts, generated metadata, and link gates.
- MoonBit format and public API consistency.
- Node and Compute contribution generation freshness.
- Independent third-Connector addition on JS, Wasm, and native.

The public API and Connector-addition checks were rerun from the clean tracked
implementation commit. The separate untracked Local Compute plan was not part
of this implementation or its verification tree.

## Deferred work

This result does not claim formal Result publication, remote execution,
credentials, durable restart, Cloud placement, resident relation reuse,
expanded Local kernels, or formal performance acceptance. It also does not
claim that a process-local Transfer contract is sufficient for a remote or
durable trust boundary.

No new wall-clock target was introduced. Existing-path structural counters
remain the regression gate; copies and accounting required by an explicit
Transfer are expected work. Resident reuse, measurement-index reduction,
native direct output, and the formal 27-case performance comparison remain
separate work.

Passing the required Linux CI on the same final SHA is still required before
this branch is merge-ready.
