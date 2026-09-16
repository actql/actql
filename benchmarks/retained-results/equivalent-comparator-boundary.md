# Equivalent-obligation comparator boundary

Q8 requires independent execution assembly, not an independent reimplementation
of ActQL semantics. This inventory specifies that boundary; it does **not**
claim that the equivalent-obligation comparator is accepted. An independent
execution prototype now exists in `adapters/duckdb-node/bench/equivalent-obligations.mjs`.
It always reports `acceptanceEligible: false` and names its missing obligations;
it is not the registered equivalent comparator and cannot supply passing pairs.

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

## Executable prototype and remaining closure

The prototype opens its own read-only source connection and transaction, performs
full source validation before filtering, runs each fixture Stage as a separate
temporary table, hashes and independently holds every named intermediate, and
reuses those private tables without parameter imports. It preflights join pair
cardinality before creating the join result. The independent fixture supplies
the final ordered-content oracle, not execution receipts.

`src/benchmark_obligations` shares the DuckDB physical value decoder, schema/value
contracts, canonical writer and canonical column-order helper. It contains no
product Host/planner/DAG assembly. Its measurement traversal is benchmark-owned;
completed per-value size measurements can discharge the next consumer's
measurement by charging the full cached work/bytes/nodes again. A smaller ceiling
or exhausted budget falls back to measurement; it is not silently waived. The
orchestration must bind that summary to its private immutable table and live
retained result. These are benchmark tokens, not production completion evidence.

The prototype now attaches the adapter's common comparison-demand measurement
to the existing source/output traversal for the registered acquisition and
filter consumers. Numeric RHS admission uses the physical decoder. Each demand
token is bound to its exact completed input scan, consumed once, and finished
using the actual SQL output cardinality. No extra input scan is added. Pending
future-consumer demand failures are retained until that consumer completes;
they do not fail its already completed producer. Each stage's report includes
operand/predicate quantities and physical measurement usage. This connects
comparison measurement, not the remaining logical-work charging, acquisition
evidence metadata or full failure-precedence equivalence.

The current tests cover nine small workload/layout combinations, order,
duplicates, NULL, Unicode, column-order permutation, nonfinite physical values,
guard exhaustion, poisoned streams, cumulative measurement budgets, an invalid
source value excluded by the filter, cancellation before start and during a
real second output writer, and Store cleanup. Independent settlement attempts
rollback, connection close, instance close, Store revocation and Store cleanup
even if an earlier action fails. Injected settlement failures preserve both the
execution cause and every failed cleanup phase and cannot yield a successful
sample. This does not yet certify real native-close or filesystem-failure
recovery. The independent column-order test caught a schema/transport index
confusion during development, before acceptance use.

Still required before equivalence approval:

- Matched execution-process/cold and warm timing boundaries.
- Complete expression-demand/guard failure parity and its negative fixtures.
- Independent file-plus-metadata retention and shared DB-plus-scratch execution
  admission, not only the Store limit or the engine's configured memory limit.
- Acquisition evidence metadata construction/validation parity.
- Transfer and logical-work accounting equivalence.
- Broader ownership, cancellation at other execution phases and actual resource
  cleanup-failure fixtures (beyond injected settlement actions).
- All 27 cases, followed by the registered alternating-pair experiment.

### Full prototype matrix (not equivalence acceptance)

Clean `f0a5dd95e0a985633ec6d61d421253751f0a4c55` completed all 27 registered
cases in fresh per-case processes. Source generation ran separately before
each child; the runner checked unchanged source before and after every case.
`equivalent-prototype-fixed-f0a5dd95.json` preserves reports, required final CID
checks, intermediate holdings, cleanup, phase times and explicit missing duties.
No sample is acceptance-eligible. These runs establish prototype coverage only,
not complete resource/semantic parity or the registered paired performance gate.

Illustrative diagnostic execution times: narrow million-row join/count 10.40 s;
narrow million-row reuse 13.56 s; numeric-64/100000 reuse 50.75 s; text-1024/100000
reuse 27.91 s. Child process-cycle and cleanup times are separately recorded.
The wide reuse case spent 9.44 s validating the source and roughly 10.2–10.5 s
in each of its four stages, despite reusing input measurements. Stage intervals
include native computation, output validation, identity and independent storage;
they do not isolate hashing. Do not divide product timings by these incomplete
comparator timings to claim an overhead ratio.

Do not turn a successful prototype run or its lower elapsed time into a 1.25
comparison result until this list is closed with inspected evidence.

## Resource-domain correction

The earlier phrase "combined DB-copy and file retention" was inaccurate if read
as adding both to the 1 GiB independent-retention ceiling. Product
`physical_resources/shared_capacity.mbt:reserve_shared_capacity` reserves an
execution resource; its table allocations are suballocations, not additional
Host retained allocations. `physical_strategy/resident_execution.mbt` separately
checks the independent output holding. This is existing product behavior, not
a relaxation of the experiment.

The comparator must therefore account independently for:

- The unchanged 1 GiB retained-output limit: files and retained completion
  metadata, with reservation before writing and settlement after completion.
- The unchanged 4 GiB execution limit: the shared DB resource, live table copies
  within it, and simultaneous semantic/transport scratch outside that resource.
  Table suballocations are not counted twice as independent holdings.

The current prototype reports Store reservations and the configured DuckDB
memory ceiling explicitly but marks resource conformance incomplete. An engine
setting alone neither reserves the external JS/MoonBit scratch nor proves a
whole-process RSS bound. Likewise, file-only Store accounting does not account
for completion metadata. These gaps must close before equivalent-obligation
acceptance; the reporting correction alone does not close them.
