# Planner and Native resident benchmark boundary

## Objective and scope

Connect existing benchmark acceptance to actual planner selections, resident
ownership and execution timing. Host is an explicit experiment condition, not
a row-count heuristic. This is the first of two delivery units: selection,
ownership and measurement connections first; one same-condition latency
improvement afterward. Instrumentation alone does not complete the task.

This branch changes benchmark runners and the Native diagnostic command. Its
only product-facing addition is a read-only getter for the already selected
Native acquisition choice. It does not change bounded output, resource-owner or
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
  before execution. Materializing the projection uses existing bounded policy
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
expected result CID/stage cardinalities. Its four conditions are resident
selection, fresh selection, cancellation after one completed task and rejection
with attempt cap one. Resident execution accounts for task deltas `[3, 1, 1]`;
fresh execution accounts for `[1, 1, 1]`. Cancellation retains the first result
and live resident reservation until explicit close. Insufficient attempts must
reject before Compute and still confirm close.

These are development-source diagnostics until a submitted revision and artifact
are bound in the PR record. The focused debug build and four-condition test
succeeded. Two portable parser/runner files passed 16 tests before the final
diagnostic refusal observation was added. The prior release build timed out at
its 180-second bound and is not counted as release acceptance. No full matrix,
packed acceptance or formal performance campaign was run locally.

The Native acceptance file is deliberately outside `*.test.mjs` discovery. The
existing Native direct-pair acceptance invokes it with its already built release
binary. Portable parser refusal tests are synthetic observation tests, not
mutations of the Native owner implementation.

## Remaining first-unit obligations

1. Connect Node Host acquisition and Compute observations, and check actual
   Native/Broad choices including residual processing under equivalent results
   and obligations. Reuse the existing public selection path.
2. Bind submitted revision, binary, toolchain and explicit condition to the
   focused execution record. Current debug diagnostics are not a clean submitted
   release performance result.
3. Confirm existing Native direct-pair acceptance and calibrated ordinary
   selection under the changed resident offer. No bounds or comparison obligations
   are waived.
4. Assess instrumentation overhead and preserve cold/warm preparation, transfer,
   identity, holding, cleanup and total intervals. A phase label alone is not
   timing evidence.

The second unit must reproduce a concrete current-revision delay, attribute it
with these observations and measure one improvement under the same conditions.
Physical memory bounds, GC reclamation and Actions evidence-reuse savings remain
outside this acceptance. Existing unfinished incremental-CI evidence work is
reported separately; this branch does not depend on its Draft PR.
