# Equivalent-obligation comparator boundary

Q8 requires independent execution assembly, not an independent reimplementation
of ActQL semantics. This inventory specifies that boundary; it does **not**
claim that the equivalent-obligation comparator is implemented or accepted.

## Shared components and independent assembly

| Concern | May share | Must assemble independently |
| --- | --- | --- |
| Value semantics | Checked schemas, common value admission and DuckDB physical value conversion | Bounded source/result chunk traversal and exact fixture input/output mapping |
| Logical identity | `execution_relation` canonical encoder and hashing primitives | Required per-boundary identity requests, traversal order, completion of each hash and association with its exact result |
| Guards and budgets | The existing query/Relation guard and measurement primitives | Placement at each required occurrence, cumulative charging and failure precedence; not merely a final-row-count check |
| Physical integrity and storage | Low-level Store file writing, integrity, retention and cleanup primitives | Choice of valid representation, creation/publication sequencing, independent intermediate retention and release |
| DuckDB transport | Pinned SDK and bounded connection/transport helpers | Connection creation, transaction boundaries, input access, SQL execution and settlement |
| Fixture and oracle | Registered fixture generator and independent expected values/CIDs | Actual execution must not substitute fixture expectations for observed validation or identity generation |
| Execution control | None of the product Host/planner/DAG orchestration | Fixed-fixture scheduling, required input/attempt associations, reservations, cancellation and cleanup responsibility |

The direct implementation must not call `createManagedExampleHost`,
`runCapturedStrategy`, the physical-strategy example assembly, or copies of
those implementations. The existing `runRetainedComparator` is the **product
leg**, not the equivalent direct leg. `runRawRetainedComparator` is the **raw
engine leg** and omits obligations; renaming it does not establish equivalence.

Shared low-level helpers must be inspected for transitive orchestration before
reuse. Sharing canonical encoding avoids inventing different semantics; it does
not establish correctness by itself. Independent result/order/CID fixtures and
negative validation, guard, retention, cancellation and cleanup fixtures remain
required.

## No artificial work for comparability

Preserve every registered intermediate completion/identity/independent-holding
boundary. Do not require identical file formats, repeated imports, or separate
validation/hash/write traversals merely because the product currently uses them.
Conversely, do not remove an intermediate result or guard by fusing tasks. This
experiment does not add task-boundary fusion.

Initial data placement and timing boundaries must match across each pair.
Preparation, first import, required validation, identity, retention publication,
stopping and cleanup cannot be moved outside timing on only one side. A preloaded
resident comparison is a separate condition from a cold first-use comparison.
Record nested/overlapping intervals rather than summing them as exclusive time.

## Three distinct conclusions

1. Product versus equivalent direct execution measures generic runtime overhead.
2. Equivalent direct execution versus raw DuckDB measures guarantee **and shared
   implementation** costs. The entire difference is not necessarily unavoidable.
3. Absolute total time, memory, transfer and major phases describe practicality.

The unchanged registered thresholds apply. Passing 1.25 alone is not a claim of
acceptable absolute latency. Missing comparator obligations, failed cases or
unmatched timing boundaries leave acceptance undetermined, never passed.
