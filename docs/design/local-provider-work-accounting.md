# Local provider work accounting

## Productive admission and mandatory termination

The adopted Relation-chain contract makes `SequenceExecutionLimits.max_work`
the allowance for new Compute and attempted handoff. Once exhausted, the same
owner requests and confirms physical stop, then retains cleanup responsibility
until reclamation succeeds. Stop work cannot restore admission or turn a limit
failure into success. Its actual reported work is included in the diagnostic
total, which may exceed the allowance. There is no independent stop budget.
Cleanup's Bool/Result callbacks report no work and receive no invented charge.
Accounting is an observation, not authorization to bill.

This clarifies the previously unresolved delayed-stop branch, rather than
reinterpreting every field named `max_work`: input measurement, expression
evaluation, scheduling and managed finalization keep their own existing limits.
Chain `used` remains productive admission; it is not the stop-inclusive total.
No task identity, CID, wire or retained-data representation changes.

## One accumulator in the existing execution owner

`ManagedProviderExecution` holds a checked Int64 cumulative result. The common
`advance_managed_provider` boundary adds each validated delta once, including
Failed/Stopped polls. Existing bounded Session adapters already turn their
cumulative observations into deltas; the chain must not sum cumulative child
snapshots as new work. Handoff reports are still counted once.

Reads do not advance execution. Materializing cleanup takes a snapshot only
when releasing the provider handle; while pending, it references that owner.
Close-driven stop advances use the same boundary. Duplicate close, repeated
reads and cleanup retries cannot add work without a new physical poll.

Additive accessors return `Result[Int64, ManagedProviderWorkIssue]`:

- `managed_provider_cumulative_work(execution)`;
- `local_materializing_cumulative_work(attempt)`;
- `cumulative_provider_work()` on ordinary and managed Local driver operations.

The old `local_materializing_provider_work` / ordinary `provider_work()` still
returns a value only after successful completion and before close. It is not
redefined as a lifecycle diagnostic. The new accessors survive failure/close.
Driver work here is provider work, not input transfer or finalization work.

Invalid reports and Int64 overflow are sticky typed accounting errors. No
wrapped, saturated or incomplete normal total is returned. Accounting faults
request cancellation but retain the existing stop/cleanup route; they cannot
authorize another productive step or discharge recovery responsibility.

## Caller and evidence audit

The materializing and managed Local drivers validate individual poll quantum
and progress, not an aggregate total less than `max_work`. The Node strategy
bundle also validates individual work and yields between advances. The native
DuckDB Host reads the old getter on successful completion only. These consumers
do not establish a stop-inclusive total cap. Measurement and managed
finalization counters are distinct and are unchanged.

The Relation-chain Lean model does establish `reported <= budget`, conditional
on prompt cancellation with no added work. Its propositions and reviewed scopes
remain unchanged. Runtime regressions for delayed stop do not extend those
formal guarantees; source changes invalidate old source-bound evidence.
See [the pilot boundaries](../../proofs/relation-chain/README.md).
