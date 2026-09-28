# Managed completion unification: shared boundary result

## Follow-up status (2026-09-28)

At main `805a29c5f`, `src/physical_strategy/captured_dag.mbt` uses one
`CommittedTaskOutput` boundary for materialized, managed and Carrier-managed
outputs. The cross-branch integration prerequisite described below is no
longer an open architecture task. This does not establish all Carrier retained
execution obligations. The remainder is evidence for the historical Engine
branch, not a current integration checklist. See [current status](current-product-status.md).


Date: 2026-09-20

Implementation base: `7a9bc32f` on
`feat/engine-remote-site-completion`.

Verified Engine implementation head: `4b4087f9`.

The branch subsequently hardened the shared remote boundary so a durable
Coordinator observation is required in addition to Site evidence. The Engine
branch then removed the obsolete Connector-owned finish and publication
authority after every product and conformance caller had moved to the common
materializing or managed boundary.

The earlier report used the pre-rebase object names `98865fcf` and
`8a9102f4`. The history rewrite changed commit identities without changing
the implementation tree. This report records the corresponding commits in
the current branch history.

This report records the Engine-side shared boundary delivered for
`2026-09-20-managed-completion-unification-work-order.md`. It is not the final
combined Local Carrier acceptance report. The Local workstream must consume the
shared commits and add its typed Carrier output to the same slot before the
cross-branch architecture is complete. Linux CI on the eventual integration
candidate is also pending.

## Implemented authority

`CapturedDAG` now has one authoritative `outputs` array. Its private variants
hold either a materialized output or a managed completion reference. A single
`commit_task_output` mutation:

- attaches the graph-owned holding;
- stores the typed output reference;
- marks the task done;
- clears completed input ownership; and
- advances the graph generation.

The variants are access types, not separate ledgers. A task cannot expose two
completion kinds, and scheduling, release and transfer read the same slot.

All prepared materializing execution uses the common lifecycle-only hook set:
cancellation, disposal, settlement, readiness, retention release and final
release. Output verification and task success remain Host-owned. A product
Connector no longer receives its own `finish` or `TaskPublication` authority.

## Migrated paths

The following Engine product paths use the common output commit:

- synchronous Local execution;
- Local materializing execution;
- asynchronous and synchronous reference execution;
- DuckDB Node and native execution;
- DuckDB resident relation reuse;
- generic materializing `compute_author` execution;
- existing typed managed execution and the shared remote evidence boundary.

The remote boundary now requires a durable Coordinator observation of the
exact evidence, subject, and measurement identities before it can invoke the
common task commit. Raw Site evidence cannot complete a task. The configured
native Remote Site product runner still has to supply the recovered material
handle and this Coordinator fact; the integration fixture is not presented as
that product runner.

DuckDB standard Hosts use lifecycle-only completion. The low-level DuckDB
preparation path no longer selects a compatibility completion mode and cannot
manufacture Connector-owned finish or publication callbacks.

Resident output is validated and bound to its resident table before the common
commit. It is not converted, serialized or re-imported. Deferred physical
verification runs only after the common holding is admitted, preserving the
existing retention ordering.

## Removed compatibility authority

The exported `ExecutionOperations.finish`, `ExecutionOperations.publish`,
`TaskPublication`, `start_captured_execution`, `complete_task_execution`, and
the corresponding preparation helpers have been removed. `PreparedExecution`
now carries only the physical payload and lifecycle observations. The Host
accepts the exact materialized output at the common completion boundary.

Dependency-boundary tests reject reintroduction of these APIs. Local,
reference, DuckDB, remote-completion fixtures, and `compute_author` all use the
same common authority. No compatibility output store or Connector publication
scope remains.

## Identity, data movement and accounting

The unification adds no full-row materialization, serialization, import,
physical digest, logical CID or statistics pass. Materialized outputs retain
their existing storage. Managed file output retains its exact material and
evidence. Resident DuckDB output remains resident.

CID-free execution remains CID-free. Named Result publication remains a
separate commit with its existing identity obligations. This refactor does not
turn task completion into Program publication.

The common Run ledger still reserves execution and retention before use.
Operation settlement, output validation, holding admission, completion commit,
consumer admission and final reclamation remain distinct facts. A failure after
private output creation leaves the holding on the failed execution until its
existing disposal path confirms release.

## Local verification

The final Engine removal passed:

- query integration tests: JS, Wasm and native, 358/358 each;
- dependency-boundary tests, 46/46;
- the complete real DuckDB Node suite, 132/132, including standard Host,
  managed Host, resident reuse, and the 27-case smoke matrix;
- `moon check --target all --deny-warn`;
- documentation gates; and
- MoonBit format and public API consistency.

The real DuckDB resident counters remain on the resident path rather than a
batched import fallback.

## Remaining cross-branch work

The Local Carrier branch currently still has ordinary, managed and
Carrier-managed output arrays. Its integration task is to add a Carrier variant
to the shared `CommittedTaskOutput` slot and migrate every Carrier producer,
consumer, transfer and release path. It must not recreate a fourth authority or
keep `carrier_managed_completed` as a parallel ledger.

After that handoff, the integration owner must rerun the affected Local family
suites, generated API and bundle gates, no-copy counters, full repository gates
and Linux CI on one fixed SHA. Only that combined candidate can close the whole
cross-branch work order. The Engine compatibility exports no longer defer that
handoff.
