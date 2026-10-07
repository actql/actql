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

## Integrated focused validation

The parent normally adopted main
`ae1f273bc1174e50598d86ab932daa0bc28c5f4d` as
`317d7e146e57cf638ed42b4a5b59294629708bdf`. This child then normally merged the
parent as `ffe0b243c8c1f730bea4d6909b3f69063d4a6740`, without conflicts.

The earlier timeout truncated generated JavaScript. Syntax inspection rejected
that incomplete artifact; it was not used as execution evidence. The following
focused selections used one compiler job and a 300-second invocation budget,
not a full Core or packed campaign:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 300 -- \
  --target js --jobs 1 \
  src/execution_relation/managed_output_reclamation_wbtest.mbt \
  src/execution_relation/managed_output_values_wbtest.mbt
node scripts/local-checks.mjs test moon --timeout-seconds 300 -- \
  --target js --jobs 1 \
  src/query_integration/local_publication_reclamation_wbtest.mbt \
  src/query_integration/managed_scratch_release_wbtest.mbt \
  src/query_integration/managed_import_reclamation_wbtest.mbt
```

- Clean `ffe0b243c8c1f730bea4d6909b3f69063d4a6740`: admission JS 8/8,
  `run-D9aR2X` / `focused-test-FOQgDS`, including the final closed-row change.
- The first caller attempt ran 10 cases, with 9 passed and 1 failed:
  `run-4C7Q7j` / `focused-test-I1KAG9`. The new Local cancellation case passed.
  The older import fixture incorrectly required a 100-row producer's admission
  to retire in a single cleanup pass. Its expectation now requires pending
  capacity to remain charged and independently bounds subsequent passes from
  100 three-container rows plus seven metadata entries, at 64 entries per pass.
  No successful-result expectation, work limit or failure code was weakened.
- Dirty source at the same integration SHA, with the caller fixture correction
  and canonical formatting: caller JS 10/10, `run-KTXAR2` /
  `focused-test-GWO30D`. This executes Local finalization cancellation, incomplete
  import reclamation and DuckDB completion/callback/receipt cleanup cases.
- Source-premise and negative mutations: Node 32/32, `run-bQlynw` /
  `focused-test-W4NL70`, on that same dirty source. These are not a full Native
  proof campaign or physical-lifetime theorem.

Project-wide `moon fmt --check` found existing main formatting differences in
`src/platform_native/executor_slot/executor_slot_native.mbt` and
`src/query_syntax/query_test.mbt`. Neither file is changed by this unit; the
command failed and is not reported as a pass. Changed-file formatting is checked
separately with the pinned formatter. A materializing fixture's canonical-only
formatting is returned to the parent PR rather than mixed into this child.

Remaining: validate the new DuckDB driver cleanup hook through its consuming
runtime and prepare the affected runtime before public real-Store acceptance.
The executed DuckDB cases exercise its completion owner, not the installed
Host driver hook. Wasm/Native execution, physical-byte correspondence, full
Core/proof/packed/HTTPS/performance and submitted-HEAD CI are not established.
This unit can be published as Draft; these checks do not establish shipping
readiness or completion of the whole retained Local goal.

## Standard Host and real-Store validation

Local Node and DuckDB Host JS release runtimes were rebuilt from clean
`f104f8ede03f6353481d971ca7ce1a2e77b9f959` (`run-ggp024`, 75 tasks).
The DuckDB conformance runtime also built (`run-5U1GOE`, 3 tasks). These root
runtime artifacts are not packed packages. The focused boundary imports the
checkout SDK and standard Host, and uses real retained/publication Stores.

The initial 13-case selection failed 8 cases (`run-4GKC8r` /
`focused-test-bk4Dyr`). Successful-output close reached common cleanup refresh
before disposing its ticket. Two scalar boundary cases additionally used the
old work model. Neither check was removed: parent commit
`e5bce7dda72bbc8a3ffeb336d2449d8a456e81bc` fixes close ordering and adopts the
existing independent 162/161 work model with unchanged 9/8 workspace limits.
The new close-order regression failed before the fix and its three-file Node
selection subsequently passed 31/31; see the parent record for receipt scope.

The child adopted that fix by normal merge as clean
`c87106aa97d5587691acd93a12b1ead806110f8d`. The following selection passed
13/13 (`run-w3M31g` / `focused-test-MVnICX`):

```sh
node scripts/local-checks.mjs test node --timeout-seconds 180 -- \
  --test-name-pattern \
  'retained Values honors|retained source-free Values chain retains responsibility|retained Values publishes ordered source-free chain|installed retained .*factory executes|installed retained Vectors retains custody after publication|installed retained Events retries cleanup after publication' \
  adapters/connectors/duckdb/node/test/retained-values-chain.test.mjs
```

This executes normal installed Local Graph/Events/Vectors mixed Stages and the
source-free Values/filter/select route, reads the three actual Named Results
against independent ordered rows, and checks two consumers and final resource
release. It also executes typed work/workspace one-short failures, cancellation
after filter starts, arithmetic failure, retained append/finalize failure, and
Carrier publication failures with cleanup retry and unchanged dispatch counts.

Compiled MoonBit inputs are unchanged between the runtime-build SHA and this
execution SHA: the merge changed only the Node adapter, tests and evidence.
Runtime reuse therefore does not hide a stale compiled input. The installed
DuckDB driver hook itself is still not exercised by this Local boundary.
Wasm/Native execution, clean packed/HTTPS acceptance, physical-byte lifetime
correspondence and submitted-HEAD CI remain unverified. No full campaign or CI
retry was added. Subsequent documentation commits do not relabel this receipt.
Before publication, the unpublished merge message was changed to Conventional
Commits with 72-column lines as `4be58f30a5cbfecb26bdd80792df5960f50a7e18`.
Its tree and parents are unchanged; the execution receipt stays tied to the
original merge SHA above, not the message-only successor.
