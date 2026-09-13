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

## Historical comparison stopped

The first real comparison did not pass the gate. See
[the stopped comparison report](REVISION-REGRESSION.md) for observed native
regressions, the 21-pair uncertainty stop, incomplete coverage and the runner's
automatic-stop correction. Product completion/producer implementation remains
unstarted; the task is not complete.

## Accepted continuation baseline

The user accepted `f025ce4` for continued development, with the recorded
performance regressions retained. This is not a passed performance gate.
Historical baselines, diagnostic results and unmeasured coverage remain in
`REVISION-REGRESSION.md` and `FRAME-COST-RESULTS.md`. No further frame/event
tuning or rollback is part of this increment. The subsequent user-approved
exception is one bounded post-boundary diagnostic comparison, specified below;
it does not reopen the full matrix or optimization loop.

The concrete completion-boundary edits are `completion.mbt`, the existing
completion/input-admission sections of `sequence_driver.mbt`, and new private
`completed_storage.mbt` / `completed_rows.mbt` adapters. The default row path
stays intact. Completion may hold either its row store or a mixed physical
store; both are created only by the same successful driver wrapper. The
alternative data form retains typed numeric/validity buffers, explicit row
count and selection, not an executable IR. Checked projection and row-index
algorithms remain the existing implementations. Producer input accounting
reads through the private reader before projection regardless of representation.

Whitebox assertions/benchmark helpers and their existing values-vector
generator may be updated to explicitly request the row-only test view instead
of assuming every completed output is a row Table. New connection tests use
the real completion/binding/admission path. No typing/lowering, wire, registry,
pins, evaluation laws or new operation kernels are authorized.

## Independence from expression scheduling

Completion storage, success construction, producer binding and admission must
not depend on `ExpressionFrame` or its stop/resume/drain API. They consume
successful execution data and its existing checked ownership, not a suspended
evaluator. A limited test kernel may use the frame API internally, but neither
its frame nor a continuation may become part of a completed output or producer
input. Audit this dependency in the final diff. Removing resumability from a
future synchronous evaluator must not require changing these boundaries.

## One post-boundary diagnostic

After the boundary change, run the existing revision harness once against
`bafdc88`, using the same frozen diagnostic subset from `FRAME-COST.md`: four
1,000-row workloads, native/JS, E2E/prepared, seven alternating pairs per cell.
Keep the profiling overlay, toolchain and measurement conditions comparable;
record revision, runner, binary and raw-sample identities. Preserve the prior
`f025ce4` evidence rather than replacing its baseline or results.

Report absolute and proportional residuals against `bafdc88` alongside the
recorded one-pass residuals. Comparing separately measured reports is not a
paired estimate of the boundary change itself: record environmental differences
and uncertainty, and do not assert absence of regression when the evidence is
inconclusive. This diagnostic neither passes the historical performance gate
nor demands improvement. Do not extend uncertain cells, repeat the comparison,
or tune the evaluator. Report any apparent increase and stop for the user's
decision after completing the authorized correctness checks. Wasm performance
and the full performance matrix remain outside this diagnostic.
