# Managed completion unification: shared boundary result

Date: 2026-09-20

Implementation base: `7a9bc32f` on
`feat/engine-remote-site-completion`.

Verified implementation head: `84abc691`.

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
- existing typed managed execution and remote managed evidence.

DuckDB standard Hosts opt into lifecycle-only completion. The low-level DuckDB
preparation default remains a deliberate public compatibility mode, but it
feeds the same common commit and has no separate output store.

Resident output is validated and bound to its resident table before the common
commit. It is not converted, serialized or re-imported. Deferred physical
verification runs only after the common holding is admitted, preserving the
existing retention ordering.

## Compatibility boundary

The exported `ExecutionOperations.finish`, `ExecutionOperations.publish`,
`start_captured_execution`, `complete_task_execution` and `TaskPublication`
surface remains as a one-way adapter. It is isolated from product
materializing preparation and cannot complete those executions. It owns no
parallel task-output state.

Removal requires both of the following:

1. the Local Carrier workstream rebases and moves Graph, Events and Vectors to
   the shared typed slot; and
2. known external low-level API consumers are reviewed or migrated.

Keeping this adapter does not keep the former independent product success path.
Deleting it before the parallel Local workstream can consume the shared change
would make the cross-branch migration unsafe.

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

The verified implementation head passed:

- complete MoonBit suites: JS 5,095/5,095, Wasm 5,094/5,094 and
  native 5,145/5,145;
- connector SDK tests: JS, Wasm and native, 16/16 each;
- physical strategy tests: JS, Wasm and native, 16/16 each;
- query integration tests: JS, Wasm and native, 357/357 each; and
- retained-boundary Node tests, 239/239;
- real DuckDB standard Host, managed Host and typed resident join tests, 3/3;
- documentation and dependency-boundary gates; and
- MoonBit format and public API consistency.

The Local and reference integration fixtures also verify that the compatibility
`complete_task_execution` entry rejects lifecycle-only product executions. The
real DuckDB resident counters remain on the resident path rather than a batched
import fallback.

## Remaining cross-branch work

The Local Carrier branch currently still has ordinary, managed and
Carrier-managed output arrays. Its integration task is to add a Carrier variant
to the shared `CommittedTaskOutput` slot and migrate every Carrier producer,
consumer, transfer and release path. It must not recreate a fourth authority or
keep `carrier_managed_completed` as a parallel ledger.

After that handoff, the integration owner must rerun the affected Local family
suites, generated API and bundle gates, no-copy counters, full repository gates
and Linux CI on one fixed SHA. Only that combined candidate can close the whole
work order and remove compatibility exports whose consumer count reaches zero.
