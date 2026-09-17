# Managed completion to common graph publication

Date: 2026-09-17.

The selected DuckDB strategy task can now consume an exact managed Store body,
execute its checked query through DuckDB, retain the native result and publish a
verified managed completion to `CapturedDAG` without constructing a legacy
`CompletedOutput`, logical row CID or ResultArtifact. This is the first actual
multi-task product path for the new profile; its installed representation is
deliberately finite rather than a claim of general managed dispatch.

## Boundary

`ManagedCompletedOutput<T>` remains the typed Host-owned completion. The common
graph stores only an opaque `ManagedCompletionReference`: the exact completion
occurrence plus a live availability check. It contains no representation
payload, portable handle or content identity. A separately completed output
with equal values or the same profile does not match that reference.

`complete_managed_task_execution` accepts only:

- the graph's exact active, physically settled task execution;
- the exact checked owner and final output port;
- either the task's exact legacy acquisition inputs or its exact managed input
  use-sites;
- a live managed completion and its exact retained storage byte count; and
- for a nonempty body, the matching live allocation converted from that same
  task's reservation.

The resident-table path is intentionally rejected until it has an equivalent
managed ownership bridge. The legacy finisher and connector publication hook
are not called, and the old completed-output array remains empty. After the
boundary commits, the graph owns the body holding, marks the task done, settles
unused reservation capacity and can select the next checked task. The Host
continues to own Store availability and the separate measurement-index holding.

The Node wrapper makes this transition atomic to its caller. If common graph
publication fails after connector verification, it revokes the managed output
and stops the graph; it never returns a detached managed success. On success it
removes the body allocation from the output's independently releasable tokens,
preventing a later output cancellation from double-releasing graph capacity.

## Exact downstream input preparation

`captured_managed_task_input` now prepares a typed `ManagedProducerRead` only
for the exact data edge of the currently ready consumer. The caller must
supply the Host-owned completed output whose opaque occurrence is stored for
that edge's producer and target. Equal rows, schema, profile, physical digest
or another completion from the same producer cannot satisfy the lookup.

This preparation establishes the receiver, input ordinal, producer occurrence
and checked projection. It deliberately does not grant a Store pin, current
read authority or resource capacity. Those remain dispatch-time obligations.
The resulting use-site follows the output's live condition, so revocation makes
both another graph lookup and an already prepared read unavailable.

The real Node/DuckDB regression uses a dedicated serial dependency for this
case. The general fixture also contains parallel branches whose next scheduled
task reads Acquisition directly; task order is not treated as a data edge.
This distinction prevents a convenient preceding completion from being
substituted for the checked producer.

The bound inputs enter connector selection through
`ManagedFixedComputeRequest<T>`. This request retains the existing fixed-compute
capacity contract, exact receiver and ordered input ports while remaining
separate from the legacy CID-bearing `FixedComputeRequest`. It rejects a logical
row ceiling below the retained input count and rejects unavailable material.
`ManagedFixedComputeCandidate<T>` applies the same installed capability,
quantity and serial-cost checks to this request. Candidate comparison remains
pure preparation, not a pin or execution authority. The DuckDB implementation
compiles either its existing checked FilterSelect query or the finite checked
take/projection/copy view as the candidate payload. It does not manufacture a
legacy request or decode the input while compiling. The real regression selects
that candidate through the registered DuckDB capability before inspecting its
SQL.

`PreparedManagedExecution` then carries the selected private payload and common
physical envelope into `start_captured_managed_execution`. DuckDB driver code,
rather than a fixture-authored lifecycle closure, owns the exact selected query,
typed managed completion port, cancellation and settlement state. Its lifecycle
has cancel, settle, dispose, release and ready checks, but deliberately has no
legacy `CompletedOutput` finisher or publication callback. The captured DAG
uses the same reservation and cleanup state machine for both execution
families, while their success boundaries remain disjoint. A conformance start
with no native I/O separately proves reservation/settlement and that the legacy
finisher rejects a managed execution. The product Host path below supplies the
Store pin and native execution evidence that this lifecycle-only fixture does
not.

## Installed Store/native product path

`runManagedColumnStrategyHostCompute` accepts only the opaque selected Host
configuration, the exact graph-owned material, the installed representation
contract identifier, Host limits and Host storage policy. It accepts no SQL,
verifier, completion callback or caller-authored evidence. The MoonBit driver
owns the selected request, compiled query, typed completion port and task
lifecycle.

The initial installed representation is an ordered set of Number/Text columns
encoded as bounded newline-delimited physical column frames. Revision `0.2`
stores columns in the checked logical schema order and stores an explicit
logical row ordinal for every value occurrence. Neither DuckDB field order nor
its internal `rowid` defines the ActQL occurrence. This is a finite
implementation identifier, not a registered logical CID and not a portable
ResultArtifact contract. The Host:

1. resolves the exact `ManagedProducerRead` for the selected downstream task;
2. acquires a Store read pin and checks path, generation, physical digest,
   current authority and material binding;
3. grants that exact file to the DuckDB session and imports it with checked,
   adapter-generated `read_json` SQL and no parameter-row INSERT path;
4. runs the selected query and, for an installed checked filter/select or take
   view, reads the selected logical occurrence ordinals from a private hidden
   column;
5. transfers the corresponding per-cell measurements from the exact producer
   index, checks the selected row count and demand, and writes the unchanged
   values in logical schema order to a new Store body;
6. for an unsupported output shape, uses the ordinary typed output verifier
   instead of treating evidence transfer as successful;
7. settles actual physical use, retains the sealed output allocation and
   publishes it through `complete_managed_task_execution`; and
8. registers the new material for a later exact managed reader without giving
   the caller a pathname or completion authority.

Logical content identity is not inferred from the Store digest. Store integrity,
producer/attempt binding, typed value admission and graph completion remain
distinct checks. The standard regression repeats this path for tasks 2 and 3,
so task 3 reads task 2's exact independently held body instead of falling back
to legacy rows. Closing an ancestor after its consumers complete does not
revoke their outputs. Physical cleanup is asynchronous: logical use is revoked
first, and the common allocation is returned only after Store cleanup confirms
release and the Host refreshes the graph retention ledger.

The product entry reports finite work counters rather than inferring savings
from elapsed time. Each downstream task observes one physical-integrity pass,
one native file-import command, zero parameter INSERT rows, zero
logical-content CID computations and zero Core output-value admission cells.
The first task transfers three measurement cells for three selected occurrences
while projecting and renaming `id` to `kept`. The second executes checked
`sort(kept asc)`, then `take(count=1, offset=0)`, copies `kept` to `id`,
transfers one measurement cell for source occurrence 1 and selects the copied
field. Sort SQL uses the checked Number order and the original occurrence as
the stable tie-break. Both write one output frame and report exact input/output
physical byte counts. An extra or out-of-range occurrence is rejected.
These counters do not claim that DuckDB performs only one internal filesystem
read or that no typed-value work occurs. DuckDB still evaluates required
operations, the Host still validates occurrence framing and storage order, and
the common boundary still checks demand, ownership, holding and native
settlement.

The same product regression also runs a global count over the original managed
producer. That operation creates a new value, so the Host admits exactly one
output cell and retains its one-cell measurement index. Two independent
filter/select consumers then read that same group result. Each reports one
reused measurement cell, zero Core output-value admission cells and zero
logical-content CID computations. Revoking the group's original input does not
revoke the independently admitted group result or either later consumer.

## Real strategy regression

The standard Node/DuckDB Host regression runs the selected task through actual
DuckDB execution and checks the following sequence:

| boundary | reserved retention | held bytes | graph state |
| --- | ---: | ---: | --- |
| admitted open | stream base + 100,000 body + 896 index | 0 | task 1 running |
| index and actual 43-byte body retained | stream base + 99,957 | 939 | task 1 running |
| native settlement | unchanged | 939 | no success yet |
| task-1 managed publication | 0 | 939 | task 1 done, task 2 ready |
| task-2 selected-evidence publication | 0 | 1,670 | tasks 1 and 2 done, task 3 ready |
| task-3 selected-evidence publication | 0 | 2,265 | sorted chain done; group task ready |
| global-count publication | 0 | 2,860 | one new value admitted with a one-cell index |
| task-1 output revoke | 0 | 1,964 | task-1 index released; descendants remain valid |
| task-3 close and physical cleanup | 0 | 1,369 | task-1, task-2 and group bodies remain |
| task-2 close and physical cleanup | 0 | 638 | task-1 and group bodies remain |
| first group consumer publication | 0 | 1,233 | one group measurement reused |
| second group consumer publication | 0 | 1,828 | the same group measurement reused again |
| both group consumers closed | 0 | 638 | shared group result remains live |
| group result closed | 0 | 43 | task-1 body remains graph-owned |
| task-1 close / cleanup confirmation | 0 | 0 | all bodies reclaimed |

The same regression rejects a 100,001-byte body despite the adjacent stream
base reservation, and rejects a legacy completion call after managed
publication. This demonstrates distinct ceilings, one attempt and one success
mode per task, and ownership transfer through cancellation.

## Remaining production work

The product path is intentionally limited to the installed Number/Text column
representation and finite checked FilterSelect and take/projection/copy query
families. It now implements a Q6 evidence-transfer path for unchanged values,
including projection/rename, exact-copy derive, logical-schema column
reordering, explicit row-occurrence mapping, checked slice composition and
repeated downstream reuse. A newly computed global-count result is admitted
once and its measurement evidence is reused by two later consumers. It does
implement one checked Number/Text stable sort before slicing or shape changes;
Text uses the existing UTF-16 logical order and ties retain source occurrence
order. It does not yet implement computed derive values, general sort
composition, join or keyed-group result reuse, general schemas/codecs, mixed
acquisition/managed input families, resident-table publication, Local
execution or named Result bridging. The finite
representation identifier must either become an adopted machine contract or be
replaced by the shared registered representation boundary before portable use
is claimed.

The original 27-case/1 GiB acceptance measurements also remain open and must be
reported separately from the new-profile measurement. This increment proves an
actual pinned Store → DuckDB → Store → common graph path and independent
downstream lifetime; it does not claim general managed execution or a
performance acceptance ratio.
