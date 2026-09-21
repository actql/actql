# Managed completion migration inventory

Date: 2026-09-20

Status: implementation inventory. This is not an acceptance report.

## Bases

- Integration owner: `feat/engine-remote-site-completion` at `98865fcf`.
- Shared base and `main`: `0886df5a`.
- Local family handoff rechecked at `6befbda7`.

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
| Remote completion port | Managed completion only | Site-owned output plus Coordinator-owned common holding | Exact dispatch, durable Coordinator observation, issuer, attempt, obligations, and current holding | Keep the typed evidence path and enter the same output-slot authority |
| Managed Site Transfer | Requires a live managed completion reference | Independent destination reservation and holding; source holding is not re-reserved | Exact source occurrence; no task completion authority | Read the unified output slot and preserve independent transfer lifecycle |
| Named Result publication | Consumes admitted task output through the standard Host | Publication holding remains separate from task completion | Named Result identity and publication commit remain separate | No new publication path; consume the same committed task output |

## Current common lifecycle facts

All prepared-execution families use the same Run ledger, task reservation, task
attempt, cancellation entry, settlement gate, disposal gate, retention
collection and final release. Product materializing preparations now receive
only `ExecutionLifecycleOperations`; they return the exact typed output through
the common completion boundary. They cannot obtain the compatibility `finish`
or scoped `publish` authority.

The DAG has one `outputs` array. Its private typed variants select materialized
or managed access without creating separate completion ledgers. The single
`commit_task_output` mutation attaches the holding, stores the typed reference,
marks the task done, clears completed inputs and advances the graph generation.
Synchronous Local, Local materializing, reference, DuckDB Node/native,
`compute_author`, managed execution and remote managed evidence converge on
that mutation.

Remote evidence additionally requires the Coordinator's durable observation
of the exact evidence, subject, and measurement identities. Site evidence by
itself cannot reach the common task commit. The configured native Remote Site
executor and its recovered material handle now enter this boundary through the
same durable Coordinator observation; they do not introduce another
completion authority.

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

## Implemented dependency order

1. Parallel Engine task-output arrays were replaced by one authoritative typed
   slot.
2. Lifecycle-only materializing preparation was added without another output
   representation or row conversion.
3. Local materializing and synchronous product callers were moved to the common
   commit.
4. Reference, DuckDB, and `compute_author` callers were moved without changing
   their physical representations. Resident DuckDB output remains resident.
5. The Local workstream must add its Carrier variant to this same slot when it
   consumes the shared commits. It must not retain
   `carrier_managed_completed` as another array.
6. Compatibility exports remain until the Local handoff and known external
   low-level consumers are migrated. No standard Engine product path depends on
   their finish/publication authority.

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

`ExecutionOperations.finish`, `ExecutionOperations.publish`,
`start_captured_execution`, `complete_task_execution` and `TaskPublication`
remain externally visible low-level compatibility APIs. They are a one-way
adapter into the common commit: they have no output array or success mutation of
their own. `PreparedExecution` itself is shared by the lifecycle-only and
compatibility binders and is not obsolete.

The compatibility removal condition is zero known consumers after the Local
Carrier branch rebases, adds its typed output variant to the shared slot, and
the deliberate low-level public API surface is reviewed. Ordinary
`captured_task_output` remains the typed materialized accessor and is not a
second authority.

The shared output slot is internal and does not require a public protocol
version. If later changes alter a public machine contract, its pins, generated
interfaces, and independent vectors must be updated together.
