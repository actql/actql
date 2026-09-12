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
The runner rejects modifications outside the listed test overlays and records
their hashes.

The supplemental overlay also changes only the test fixtures
`layout_numeric_cases_wbtest.mbt`, `layout_additional_profile_wbtest.mbt`, and
`sequence_profile_wbtest.mbt`, identically on both revisions. It adds three
1,000-row/two-number-column cases on every target in both modes: nested IF/CASE
with unselected division failures; eight ordered slots (input shadow followed by
seven distinct prior-slot bindings); and a left-associated chain of 64 additions.
Existing cases and clocks are retained. The supplementary preparation envelope
admits the deeper source/wire expression trees equally on both revisions;
execution budgets are unchanged. Closed-form expected outputs are id+1 for even
and id+2 for odd in the conditional case, k=id+1 and x1 through x7=id+2 through
id+8 in the ordered case, and x=id+64 in the long case. All retain descending
input order; conditional and long cases retain the input key column unchanged.
These add 18 cells/252 initial samples, for 136 cells/1,904 total initial
samples before any uncertainty extensions. This inventory is fixed before
measuring the supplemental cases.

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

The supplemental preflight initially rejected a fixture that repeated an
ordered output name. It was corrected to the valid input-shadow/prior-slot
chain above. Deep source and wire trees also required an explicit larger
preparation envelope. No product acceptance or execution rule changed.
The corrected smoke passed all 48 invocations (both revisions, all targets,
both modes, mandatory smoke plus all three supplementary profiles), recorded
under `_build/revision-measurements/1789255060319-17016/`.

`report-revision-comparison.mjs` independently reconstructs the complete
136-cell matrix from raw output assertions and RSS, recomputes the seven/21
pair decisions, and rejects missing cells, failed assertions, altered stored
measurements, reordered revisions and unsafe raw paths. Synthetic full-matrix
and rejection tests validate the auditor; neither they nor smoke are evidence
of regression absence. The full comparison remains to be measured.

The supplemental increment passed 18 comparison/statistics/auditor Node tests,
279 execution-package tests on each of JS/Wasm/native with `--deny-warn`,
format, documentation and metadata checks. These are incremental checks, not
the final whole-repository verification required after product-boundary work.
Linux CI has not been run.
