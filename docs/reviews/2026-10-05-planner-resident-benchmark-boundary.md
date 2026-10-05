# Planner and Native resident benchmark boundary

## Objective and scope

Connect existing benchmark acceptance to actual planner selections, resident
ownership and execution timing. Host is an explicit experiment condition, not
a row-count heuristic. This is the first of two delivery units: selection,
ownership and measurement connections first; one same-condition latency
improvement afterward. Instrumentation alone does not complete the task.

This branch changes benchmark runners and the Native diagnostic command. Its
product-facing observations are a read-only getter for the already selected
Native acquisition choice and an optional installed Node task-start observer.
The bounded example also retains its original checked physical query preparation
to offer Native and Broad candidates over exactly the same requirement and
physical mapping. It does not reinterpret the logical Source identity as SQL
schema/table names or change the public Client's acquisition policy.
It does not change bounded output, resource-owner or
ledger implementations, incremental-evidence reuse, or PR CI job selection.
The manual performance matrix profile is renamed to `native-direct` to remove
implicit Host routing. This is a changed experimental condition, not a directly
comparable replacement for historical formal results.

## Connected observations

- Acquisition records the actual existing choice, quantities, declared receiver
  bounds and reason. The Native application offers one Native candidate; a
  `HostPreferred` result is not a comparison against a nonexistent Broad offer.
- Compute records existing candidate projections and the selected registration,
  assessment position, strategy revision, resident flag and selection source
  before execution. The actual owner explanation also retains rejected
  assessments and is bound to the same revision, selected task, capability,
  resident profile, quantities and reason. A post-completion explanation cannot
  stand in for this pre-execution observation. Materializing the projection uses existing bounded policy
  consultation and charges its planning work. Diagnostic estimates remain
  explicit inputs, never evidence of calibrated ordinary performance.
- Per-task snapshots read the real Run ledger and resident owner counters.
  Each successful task accounts for Compute plus new environment/import
  attempts. This is finite counter correspondence, not proof of opaque physical
  attempt identities or allocator lifetime.
- Sealed canonical Rows bytes, charged retained bytes and selected retention
  bounds are distinct. The DuckDB owner also retains verification/file state;
  equality with canonical payload size is not assumed.
- Close must confirm release, retain cumulative consumed counters, clear live
  reservations, remain unchanged on duplicate close, and reject further Compute.
- Monotonic phase timestamps enclose actual startup, acquisition, planning,
  execution, identity and cleanup boundaries. Nested task/observer intervals are
  not additive. Planning projection time/work and owner observation time are
  reported; they are not a complete causal measurement of instrumentation cost.

## Focused development verification

The 100-row Native diagnostic uses the existing registered source and independent
expected result CID/stage cardinalities. Its six conditions are resident
selection, fresh selection, cheaper Local selection, refusal of cheaper
resident strategies with attempt cap four, stop/close after one completed
task and rejection with attempt cap one. Resident execution accounts for task deltas `[3, 1, 1]`;
fresh execution accounts for `[1, 1, 1]`. The between-task stop retains the first result
and live resident reservation until explicit close. Insufficient attempts must
reject before Compute and still confirm close.

`stop-after-task` ends the probe loop without starting the next task, then
closes the existing Run and acquisition owner. Its output is
`stopped-between-tasks`. This proves retained responsibility and return at that
boundary; it does not prove acceptance/propagation of a formal cancellation
request or a terminal cancellation observation. Formal cancellation acceptance
is checked separately below.

The four-attempt case admits three fresh Compute attempts but cannot admit the
five attempts needed by resident preparation/import plus Compute. At every
selection, an actual rejected assessment has `attempt_limit` and a lower
estimated duration than the selected feasible assessment. The test checks these
structured values, rather than searching for an error word or inventing a
selection reason. Lowering the execution cap alone is not this experiment:
the existing application sizes its offered Native envelope from that cap, so a
fresh offer can remain feasible. No capability or upper bound was rewritten.

These are development-source diagnostics until a submitted revision and artifact
are bound in the PR record. The initial focused debug build and four-condition
test succeeded; its former cancellation label was corrected to a between-task
stop. Two portable parser/runner files passed 16 tests before the final
diagnostic refusal observation was added. The updated six-condition Native test
and 15 targeted parser tests passed 16/16 on development sources after the
pre-execution explanation was added. Evidence:
`_build/local-checks/attempts/run-UCZNYl` and
`_build/focused-evidence/focused-test-ENC05X`; the incremental Native debug build
is `_build/local-checks/attempts/run-KfJzVy`. These are debug acceptance and
synthetic observation refusal evidence, not release performance measurements.
The prior release build timed out at
its 180-second bound and is not counted as release acceptance. No full matrix,
packed acceptance or formal performance campaign was run locally.

The Native acceptance file is deliberately outside `*.test.mjs` discovery. The
Native diagnostic is selected explicitly, separately from the existing release
gate. `nativeRegisteredResidentOffer` remains false and the existing
`test-native-direct-pair.mjs` keeps its original uncalibrated Local expectation;
unverified resident defaults and extra gate work are not enabled. Portable parser refusal tests are synthetic observation tests, not
mutations of the Native owner implementation.

### Review corrections and Node correspondence

The review of `ad8c7ee6a17f09c1fef364eed3d3b62abaa82cf7` identified the
incorrect cancellation label and unverified changes to the registered release
gate. The stop label/CLI were corrected without an old-name fallback. The
resident default was restored to false, and `scripts/test-native-direct-pair.mjs`
was restored byte-for-byte to the base-main version. The six-condition debug
diagnostic plus focused runner checks passed 6/6 at
`_build/local-checks/attempts/run-5CN1SI`; its build is `run-RmDSI5`.
This closes the misleading evidence label, not formal cancellation acceptance.

The installed Node driver can now copy the actual selected planner explanation
and ledger quantities after authorization and before Compute starts. The
callback cannot replace the selected task. The managed worker preserves its
existing completion custody callback, then records after-task quantities.
The diagnostics contain no task/output handles or additional holding references.
Without an installed task-start observer, the driver performs no extra explain
call. Observer exceptions and AbortSignal use the existing stop/finalizer path.
The comparator now requires explicit `observePlanner: true` to install these
observations. Without it, the worker uses the original completion custody
observer, so normal benchmark runs do not acquire extra per-task explain work.

The explicitly selected `node-owner-acceptance.mjs` uses the existing 100-row
comparator and independent result/stage expectations. Actual resident task
attempt deltas are `[3, 1, 1]`: first Compute, environment and import, then two
Compute attempts. Acquisition precedes these snapshots; the parent additionally
accounts for one execution process. Driver quantities, explanation and child
ledger are compared at the same boundary; actual connector preparation accounts
for the deltas. Selected retention bounds, live resident reservation and final
confirmed resource return remain checked. This is finite correspondence, not
opaque attempt identity or physical heap proof.

The real Node check passed 1/1 at `_build/local-checks/attempts/run-05NKpb`.
Copies of its observations with a completed selected task, extra unaccounted
attempt, or early resident reservation release are rejected. These are
observation-tampering checks, not mutations of the product. The three focused
driver/installed-observer tests passed 3/3 at `run-3YvinC`, including callback
failure/abort before Compute. Their stub-based abort check does not establish
the requested real resident cancellation acceptance. JS preparation was limited
to four consuming runtime packages (`run-WYkraN`).

These development checks do not establish calibrated performance, a causal
instrumentation overhead comparison, or public Native/Broad equivalence. Their
preparation/worker intervals overlap and must not be summed into total time.

## Remaining first-unit obligations

### Public Node acquisition capacity counterexample

The explicit `node-acquisition-counterexample.mjs` preserves the requested
successful Native/Broad equivalence expectation on the same registered 100-row
source. It is not included in ordinary portable test discovery or accepted as
a passing regression. The Node public source boundary requires schema snapshots
and capability evidence; the diagnostic supplies those from the fixture's
declared contracts, without deriving expected results from the evaluator.

On development sources at `93a28858a47ea3ac61f23a2aa50795a6dbe2cd17` plus
the new diagnostic file, Native is selected with the existing `HostPreferred`
priority policy but stops with
`NativeHostIssue.Attempt(Receiving(Values(PhysicalResultIssue.RowLimit)))`.
Broad is selected on the same requirement, completes its residual, matches the
independent CID and two output rows, and returns live reservations exactly once.
The overall equivalence acceptance remains failed, not partly successful.

`src/client_local_host/client_duckdb_acquisition.mbt` fixes Native physical
`max_rows` at 100. `begin_native_receipt` subtracts validation usage before
admitting the Native result: 100 validation rows plus two result rows need 102.
The benchmark's data-configured application already has its own explicit
combined receiver envelope; this public client preparation path does not.
This is a concrete setup/admission limitation, not a demonstrated violation of
the existing 100-row cumulative contract. Do not increase a limit silently or
omit validation to make the benchmark pass. The requested comparison needs an
explicitly bounded preparation connection before it can be claimed complete.

The last diagnostic command was the scoped Node wrapper with a 30-second bound;
the test ran for about 1.1 seconds and failed as above. Evidence is retained at
`_build/local-checks/attempts/run-MmjI8q` and
`_build/focused-evidence/focused-test-tVFheC`. The source file was then renamed
from `node-acquisition-acceptance.mjs` to identify its incomplete status; its
body is unchanged. Supporting JS builds were limited to `connectors_builtin_node`,
`physical_strategy_example` and the direct `connectors/duckdb/host_node` import.
No product limit/owner changes or broader matrix were added.

### Bounded Node Native/Broad comparison

`node-acquisition-acceptance.mjs` uses the existing data-configured benchmark
preparation, rather than the separate public Client policy above. The example
retains the original `DuckDBQueryPreparation`; both candidates use that exact
checked requirement and physical schema/table binding. Actual
`choose_acquisition_candidate` runs before provider I/O. With unknown estimates
and no Host priority it defers; duplicate priority entries are rejected. The
comparison supplies explicit Host priorities and records the actual
`HostPreferred` selection, not an invented estimate-based reason.

Both realizations keep the existing benchmark receiver ceiling of 102 rows
(100 validation rows plus two result rows), output ceiling of 100 rows, and
the same ledger/transport envelope. Native performs its validation and result
reads; Broad receives 100 rows and executes the existing bounded Local residual.
Both must match the independent expected output CID, two rows, output contract
and requirement CID. The real ledger records one acquisition attempt and live
holding before close. Close clears live reservations/holding without resetting
consumed attempts or transfer, duplicate close leaves usage unchanged, and
access after close is rejected.

This development-source case passed 1/1 after a focused JS release build.
Evidence: `_build/local-checks/attempts/run-j53YWl` (build),
`_build/local-checks/attempts/run-c4eOKX` and
`_build/focused-evidence/focused-test-UA2fSC` (execution). These results include
uncommitted example/diagnostic changes on top of
`51ec79b66ca88548be0fc046130ef28476b14692`; they are not clean submitted-SHA
acceptance or a latency improvement. Preparation, selection, acquisition and
close use monotonic interval measurements. A single Native-then-Broad run is
not a calibrated or cold/warm performance comparison. The public Client's
fixed-100 admission counterexample remains unresolved and is not relabeled as
successful by this alternate, explicitly bounded experiment.

### Fixed-SHA release acceptance already obtained

At clean `51ec79b66ca88548be0fc046130ef28476b14692`, the focused Native release
build completed (`run-OgccwF`). Its binary SHA-256 was
`d07168befd3f50744d7e1e2c0f0bcfb38f1e75fa5bd1a9ee1790c1c9dc8d516b`.
The unchanged `scripts/test-native-direct-pair.mjs` passed with its original
uncalibrated Local expectation. The existing 1,000-row training/100-row held-out
calibration and profile-backed direct-pair check also passed (`run-4Gbwsj`).
The explicit Native six-condition and real Node owner diagnostics passed 2/2
(`run-ig3YHd`). These are evidence for that revision only; subsequent example
changes are not covered by that binary, and no full performance matrix was run.

### Formal cancellation at an acknowledged resident boundary

`node-cancellation-acceptance.mjs` starts the same installed plan through the
existing managed process Host, retained Store and completion custody. Its fixed
diagnostic worker uses the standard task-start observer to report task 2 only
after task-1 completion acknowledgement. The copied real explanation must show
authorized resident selection and an incomplete task 2; the child ledger has
four attempts (acquisition, resident environment, import and first Compute),
with a live resident reservation. The parent then aborts the actual execute
request. Delegated capacity must remain charged immediately after cancellation,
until the process exit is observed.

The corrected case passed 1/1 (`run-Zc0g6g`, `focused-test-LaQ7ep`), with actual
`ExecutionCancelled`, exit code 0/no termination signal, stopped/exited true,
cleanup pending false, five parent attempts including its process, zero uncertain
transfer and live delegation reservations, and no task-2/task-3 completion.
The independently owned source/task-1 bodies remain available in the parent
Store after child stop. Explicit custody close and Store retry return them;
duplicate close/retry must leave both Host and Store accounting unchanged.
Additional reservation-before-exit and duplicate-Store checks passed in the
development run `run-GMkBcP`.

This is formal request cancellation before second Compute, not cancellation
inside an active Compute. The prior acknowledgement-in-flight diagnostic remains
saved separately: its failure and conservative settlement without terminal usage
are not relabeled as successful cooperative cancellation. No owner, ledger,
physical limit or production cleanup contract was changed for this acceptance.

### Observer cost diagnostic

`node-observation-cost.mjs` fixes four samples in off/on/on/off order. Both
conditions use the same source, checked Program, estimates, limits and installed
worker; completion custody and independent expectations remain required.
Actual resident realizations and seven total attempts must match. Disabled
observations must produce no per-task explain report/interval. Enabled
observations retain their finite selection/owner correspondence checks.

Every sample reports complete Host execution and subsequent cleanup, overlapping
preparation phases, new resident preparation/import in task 1, reused resident
tasks 2/3, transfer, identity and holding diagnostics. Nested intervals are not
summed. New processes are distinguished from uncontrolled OS/compile caches.
The initial two-file development run passed 2/2 (`run-GMkBcP`) but ran the
cancellation case concurrently: its cost values are not an isolated comparison.
The submitted-revision cost command must run alone. Four finite samples can
expose observer work/cost; they cannot prove a statistical overhead ceiling or
the second delivery unit's same-condition performance improvement.

### Acceptance still required

1. Bind the development cancellation and bounded Native/Broad comparison
   above to the submitted revision and affected runtime artifacts.
   The separate public Client limitation remains explicit.
2. Bind submitted revision, binary, toolchain and explicit condition to the
   focused execution record. The release results above bind their stated
   revision only; unpublished changes need their own correspondence.
3. Preserve the verified Native direct-pair and calibrated ordinary-selection
   conditions when subsequent changes affect their compiled inputs.
   Resident offers remain explicit diagnostics until this evidence
   supports any default change. No bounds or comparison obligations are waived.
4. Assess instrumentation overhead and preserve cold/warm preparation, transfer,
   identity, holding, cleanup and total intervals. A phase label alone is not
   timing evidence.

The second unit must reproduce a concrete current-revision delay, attribute it
with these observations and measure one improvement under the same conditions.
Physical memory bounds, GC reclamation and Actions evidence-reuse savings remain
outside this acceptance. Existing unfinished incremental-CI evidence work is
reported separately; this branch does not depend on its Draft PR.
