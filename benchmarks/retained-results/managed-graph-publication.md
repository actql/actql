# Managed completion to common graph publication

Date: 2026-09-17.

The selected DuckDB strategy task can now publish a verified managed completion
to `CapturedDAG` without constructing a legacy `CompletedOutput`, logical row
CID or ResultArtifact. This is the first common scheduler connection for the
new profile; it is not yet the complete production multi-task dispatch path.

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

## Real strategy regression

The standard Node/DuckDB Host regression runs the selected task through actual
DuckDB execution and checks the following sequence:

| boundary | reserved retention | held bytes | graph state |
| --- | ---: | ---: | --- |
| admitted open | stream base + 100,000 body + 768 index | 0 | task 1 running |
| index and 321-byte body retained | stream base + 99,679 | 1,089 | task 1 running |
| native settlement | unchanged | 1,089 | no success yet |
| managed graph publication | 0 | 1,089 | task 1 done, task 2 ready |
| exact task-2 input preparation | 0 | 1,089 | checked task-1 occurrence bound |
| managed output revoke | 0 | 321 | index released, graph body retained |
| task close / cleanup confirmation | 0 | 0 | body reclaimed |

The same regression rejects a 100,001-byte body despite the adjacent stream
base reservation, and rejects a legacy completion call after managed
publication. This demonstrates distinct ceilings, one task attempt, one success
mode and ownership transfer through cancellation.

## Remaining production work

The graph and typed relation layers can now prepare the next managed input, but
the standard strategy dispatcher still constructs requests through legacy
`ProducerRead`. Production dispatch must select this exact managed boundary,
acquire its Store pin/authority/capacity, execute it and publish the second task
through the same graph path. Mixed acquisition/managed input families,
resident-table publication, Local execution, named Result bridging and the full
27-case/1 GiB measurements remain open.

This increment therefore proves common graph publication and retention
ownership for one acquisition-fed selected task. It does not claim completion
of the production managed graph or any performance acceptance ratio.
