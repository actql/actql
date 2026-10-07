# Incremental managed admission reclamation

## Scope and implementation

This unit depends on retained-input cleanup in #846 at
`6557620a76c213478e859f550644b884dfb87b9d`. It is not completion of the entire
retained Local goal.

Cancellation immediately revokes admission without scanning all private rows.
`advance_managed_output_values_reclamation` retires bounded entry slices using
the existing admitted-buffer reclamation primitive. Disposal performs one
64-entry slice; repeated cleanup retains the same owner and resumes its cursor.
An active reader or callback prevents destructive reclamation. The witness only
observes released roots and does not drive cleanup.

Private reference slots are optional solely to scrub popped authority handles.
Receipts still contain concrete, independently copied reference handles and the
transferred measurement index. No wire value, identity, admission budget or
logical Compute work rule changes. Reference retirement does not establish a
collector latency or physical-byte lifetime bound. Receipt creation and
availability validation still have synchronous walks outside this unit.

Local finalization retains its admission owner until the witness confirms
release. DuckDB's existing cleanup entrypoint also advances private admission
before common reservation retirement; native settlement and Store release remain
separate requirements. Cleanup does not restart Compute.

The reviewed driver-retirement source premise adds this release guard before
detaching the finalization owner. Its negative mutation removes that guard.
Provider construction, stop checks, common reservation retirement, and the
existing bounded input/root slices are unchanged. This premise update does not
claim a new whole-physical-lifetime capacity theorem.

## Preparation evidence

The following evidence observes dirty source at the dependency SHA above, not
execution of the eventual clean commit. Evidence remains under the worktree's
`_build/local-checks/attempts` and `_build/focused-evidence` directories.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- \
  --target js src/execution_relation/managed_output_reclamation_wbtest.mbt \
  src/execution_relation/managed_output_values_wbtest.mbt \
  src/execution_relation/managed_output_retention_wbtest.mbt \
  src/execution_relation/managed_producer_bridge_wbtest.mbt
node scripts/local-checks.mjs test node --timeout-seconds 60 -- \
  --test-name-pattern 'source rejects|current driver/common owner source' \
  proofs/relation-pipeline/capacity/parent-control/driver-retirement.test.mjs
moon info --target js src/execution_relation src/connectors/duckdb/driver
moon check --target js src/query_integration src/connectors/duckdb/host_node
```

- Admission/receipt/reference JS tests: 18/18, `run-lyWkWn` and
  `focused-test-cBKNxl`. The final removal of a synchronous closed-row clear
  follows this receipt and is not covered by that execution.
- Source-premise admission and negative mutations: 32/32, `run-NI0GvB` and
  `focused-test-LdkOsO`. These are source/overlay checks, not Native execution.
- Canonical interface generation completed (27 tasks). The affected callers and
  new Local regression compiled on JS (65 tasks); compilation is not execution.

The new cursor cases independently derive retirement-entry counts for 100
two-column rows and 80 reference rows, compare quanta 1/7/64, retain the finished
receipt/index, and reject late append/finish. The Local driver regression builds
100 rows through the existing provider and finalization route before cancellation
and checks pending capacity, non-publication, final release and unchanged work.
That driver regression has not yet executed successfully.

## Failed attempts and remaining checks

The first new test attempt caught method/constructor function syntax errors
(`run-jtYxFA`). A subsequent incorrect name filter discovered zero tests and was
rejected by the nonzero guard (`run-Qu9LVu`). Neither is a passing receipt.

The focused Local caller selection reached the 120-second limit twice:
`run-a5GVmR` and `run-ciCnEe`. The second used the completed incremental compiler
cache. Both terminated with released wrapper locks; neither emitted a test
result. The query test core artifact was updated while the JavaScript test
artifact remained older. No stale artifact was executed as new-source evidence,
and the timeouts were not converted into assertion failures or successes.

The final two-file admission recheck also timed out (`run-gwe0BQ`). Its wrapper
could not complete process-group inspection and retained the worktree lock after
SIGKILL escalation. An explicit signal-zero probe subsequently confirmed that
the recorded owned group no longer existed (`ESRCH`). Only the matching
token/inode-checked lock was removed; the incomplete receipt remains unchanged.
No subsequent build or test was started.

Remaining: execute the Local caller/callback regression selection, recheck the
final closed-row change, validate DuckDB cleanup through its consuming runtime,
and prepare the affected runtime before public real-Store acceptance. Wasm/Native
execution, physical-byte correspondence, full Core/proof/packed/HTTPS/performance
and clean submitted-HEAD CI are not established. No new PR readiness or shipping
claim follows from this preparation record.
