# Managed completion migration inventory

Date: 2026-09-20

Status: implementation inventory. This is not an acceptance report.

## Bases

- Integration owner: `feat/engine-remote-site-completion` at `98865fcf`.
- Shared base and `main`: `0886df5a`.
- Local family workstream inspected at `62751055`.

The Engine branch had two task-indexed completion arrays before this work:
ordinary `CompletedOutput` and `ManagedCompletionReference`. The Local family
workstream adds a third Carrier-managed array. The branches share the same
legacy/managed task hook split. Carrier changes are not copied into the Engine
branch; the shared output-slot commit is intended to be consumed by the Local
workstream.

## Product caller inventory

| Entry or caller | Output and authority before migration | Physical material and holding | Consumer and identity behavior | Migration target |
|---|---|---|---|---|
| Local synchronous dispatch | `execute_captured_synchronous_task` commits an ordinary output directly | Common Run reservation and holding; in-memory `CompletedOutput` | Ordinary `ProducerRead`; no universal CID | Typed managed in-memory output through the common completion boundary |
| Local materializing dispatch | `PreparedExecution`, Legacy hooks, `finish`, scoped `publish`, then ordinary task completion | Independently materialized in-memory output; common reservation and holding | Ordinary inputs and output transfer remain bounded | First end-to-end materializing migration; retain the existing evaluator and representation |
| Local managed dispatch | `PreparedManagedExecution` and `complete_managed_task_execution` | `ManagedRetainedOutput` plus common retained allocation | Typed managed producer bridge; requirement-driven identity | Keep as the reference lifecycle; do not add row copies or hashes |
| Local Carrier providers | Carrier-managed completion on the Local workstream | Carrier-specific typed payload and retention | Carrier-specific scoped reads | Add a typed variant to the one output slot when the Local branch consumes the shared commit |
| DuckDB ordinary execution | Legacy prepared execution and ordinary completion | Node/native DuckDB result or resident relation; common holding | Ordinary reads; resident reuse is representation-specific | Migrate without materializing or re-importing resident relations |
| DuckDB managed execution | Managed completion and typed physical material | File or managed generation with exact holding | Typed managed reads and identity obligations | Keep on the common managed boundary |
| Reference asynchronous execution | Legacy prepared execution and ordinary completion | In-memory reference output under common holding | Ordinary reads | Migrate after Local using the same materialized managed adapter |
| Reference managed execution | Managed completion | Typed retained reference material | Typed managed reads and optional logical identity | Keep on the common managed boundary |
| `compute_author` | Starts and completes `PreparedExecution` | Uses the selected implementation's reservation and holding | Common Host checks completion immediately before commit | Change its channel to the unified prepared execution contract |
| Remote completion port | Managed completion only | Site-owned output plus Coordinator-owned common holding | Exact dispatch, issuer, attempt, obligations, and current holding | Keep the typed evidence path and enter the same output-slot authority |
| Managed Site Transfer | Requires a live managed completion reference | Independent destination reservation and holding; source holding is not re-reserved | Exact source occurrence; no task completion authority | Read the unified output slot and preserve independent transfer lifecycle |
| Named Result publication | Consumes admitted task output through the standard Host | Publication holding remains separate from task completion | Named Result identity and publication commit remain separate | No new publication path; consume the same committed task output |

## Current common lifecycle facts

Both prepared-execution families already use the same Run ledger, task
reservation, task attempt, cancellation entry, settlement gate, disposal gate,
retention collection, and final release. The remaining hook difference is that
Legacy owns `finish` and a scoped `publish` callback, while Managed supplies a
typed completion port outside the hook.

The common completion boundary already verifies:

- exact checked owner, target, input binding, task and attempt;
- selected registration and current execution;
- operation settlement and implementation readiness;
- required evidence and material availability;
- exact retained bytes or an admitted upper-bound allocation;
- transfer of holding ownership to the graph before task success.

No migration step may weaken those checks. A compatibility adapter may only
feed an already verified materialized result into the common owner. It must not
become a second success ledger or accept an output unconditionally.

## Shared dependency order

1. Replace parallel task-output arrays with one authoritative typed slot.
2. Add a managed in-memory representation and completion adapter that reuses
   existing Local output admission evidence.
3. Move Local materializing and synchronous product callers to that adapter.
4. Move reference, DuckDB, and `compute_author` callers without changing their
   physical representations.
5. Apply the shared slot to Carrier output on the Local workstream.
6. Remove Legacy hooks, ordinary completion branches, and obsolete exports only
   after all product callers are migrated.

## Performance and accounting baseline

The migration must not add a full materialization, serialization, import,
digest, logical CID, or eager statistics pass. Existing materialized paths may
keep their current allocation. Existing managed and resident paths must keep
their representation. A physical allocation is charged once, while each
consumer retains its own admission and logical work charges.

Structural regression checks must distinguish:

- physical allocation and copy count;
- import and serialization count;
- physical digest and logical CID passes;
- exact retained bytes and admitted retained upper bounds;
- consumer-specific reads and charges.

## Compatibility and removal conditions

`PreparedExecution`, `ExecutionOperations.finish`,
`ExecutionOperations.publish`, `start_captured_execution`,
`complete_task_execution`, ordinary `captured_task_output`, and
`TaskPublication` are externally visible low-level APIs. They remain only while
a known product caller or deliberate compatibility fixture still uses them.
Their removal condition is zero product callers after Local, reference, DuckDB,
native/Node composition, `compute_author`, and generated bridges are migrated.

The shared output slot is internal and does not require a public protocol
version. If later changes alter a public machine contract, its pins, generated
interfaces, and independent vectors must be updated together.
