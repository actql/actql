# Completion boundary work and regression protocol

## Fixed starting point and edit scope

The implementation starts at `7c033f8`, replayed on main `7b655eb`.
All 150 original commits compare equal by range-diff; their old endpoint
`820a971` is retained by the backup branch. Main's uncommitted files are not
part of this work. No further main synchronization occurs during a paired
measurement phase.

The historical regression comparison uses exactly `f9ac87b` and `820a971`,
both with row candidate A. The subsequent completion-boundary comparison uses
the same rebased base on both sides. These are separate experiments.

Before product edits, allowed changes are comparison scripts and tests under
`scripts/`, shared test-only profiling fixtures under
`src/execution_relation/`, and reports under `benchmarks/local-relation/`.
Supplemental profiling fixtures must be identical on both measured revisions;
their overlay and source hashes are recorded separately from product commits.
Existing B/C measurements are neither repeated nor adopted.

The mandatory harness overlay is `layout_output_wbtest.mbt` from `820a971`
on the baseline worktree. It adds the generic test-only output append wrapper
used by the later trial; both sides then compile identical profiling/layout
helpers. The baseline's product files and HEAD remain exactly `f9ac87b`.
The runner rejects any other source modification and records the overlay hash.

After the regression gate permits progress, the authorized product scope is
`completion.mbt`, `producer_binding.mbt`, completion construction and producer
admission in `sequence_driver.mbt`, necessary `table_store.mbt` and private
reader/storage adapters in `execution_relation`. Concrete additional filenames
and their purpose will be listed here before editing them. The earlier
expression/frame extraction may receive local performance fixes preserving
semantics and API; each fix is separately committed and remeasured.

No typing/lowering, shared contracts or pins, logical budget laws, new
operators, global driver scheduling, public disposal API, or default column
execution is authorized. A necessary change outside scope is reported before
implementation. Logs and detached measurement worktrees stay in ignored
workspace storage, not in `/tmp` or commits.

## Preregistered measurement decision

Use the existing mandatory target/case inventory, release compiler pin,
independent assertions and warmup/observation/disposal rules. Report E2E and
prepared separately, without including build time. The two revisions alternate
old/new and new/old within each case/mode/target, initially seven pairs.
The mandatory matrix alone contains 1,652 measured processes. Additional
conditional/ordered/long-expression fixtures are fixed before their measurement.

Reuse the deterministic paired-bootstrap ratio statistics, retaining all raw
pairs, medians, absolute differences, intervals, direction counts and RSS.
For time the practical ratio threshold is 1.05; for process RSS it is 1.10.
A median paired ratio at or above that threshold and the existing reproducible
regression criterion means investigate/fix or stop. An upper interval below
the practical threshold permits progress, including documented tiny regression.
Other outcomes are uncertain: extend that case/mode/target to 21 total pairs;
if still uncertain, stop rather than declare no regression. Screening and
extension are descriptive decision rules, not a claim of family-wise 95%
coverage across all cases or sequential looks. Never average a failing cell
away, weaken thresholds after observing results, or retry until a pass appears.

Record runner/helper/manifest hashes, both source commits and trees, fixture
overlays, binary hashes, compiler/runtime/host versions, execution order and
raw process output. A missing sample, failed assertion or incomplete matrix
cannot pass the gate. RSS remains a whole-process high-water mark, separate
from logical roots and explicitly owned buffer capacity.

## Required product connection and stopping boundary

The target is a typed derive output through the real product completion,
binding and producer admission into checked select and stable sort, ending
in product completion without a full row matrix. Test-only backend selection
is permitted, but not a private alternative success constructor or bypass of
fragment/input admission. Existing row execution remains supported.

Unsupported consumers may use a declared bounded conversion, including copy
and simultaneous-retention costs. Strategy selection precedes execution;
errors cannot cause fallback/retry. Public opaque handles and reference
lifetimes remain unchanged; no immediate RSS release on dropping a reference
is promised. Ownership/parameter/target mismatch, partial failure, immutable
output, multiple consumers, producer reuse, zero-column nonzero-row output,
projection and exact/one-short limits require regression tests.

Performance comparison, any local performance fix, product boundary changes
and connection regression tests are separate commits. Final verification is
the whole three-target check/test suite with warning gate, API, format,
documents and metadata, not merely package tests. Linux CI is separately
reported. Submit the result and stop; this is not general vectorization,
Arrow/SDK, spill, parallelism or new stateful-operator implementation.

## Comparison harness verification

`measure-revisions.mjs` builds each revision separately, requires identical
profile/layout helpers, checks its declared overlay, pins binaries and invokes
the same existing profile test. The pure schedule preserves 118 mandatory
cells and 1,652 initial measurements. Unit tests cover alternation, matrix
coverage, separate time/RSS thresholds, ambiguous evidence, and keeping a
seven-pair regression visible after extension for another metric.

The cross-revision smoke passed 12 measured invocations: both revisions,
E2E/prepared, and native/JS/Wasm. This is runner validation, not a regression
verdict. The initial sandboxed attempt failed at macOS time/sysctl; the
authorized unsandboxed retry passed. Raw smoke evidence is kept in ignored
`_build/revision-measurements/1789253313020-91225/`. Full matrix and supplemental
expression measurements remain pending; product completion code is unchanged.
