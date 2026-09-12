# Decision: retain row storage

The fixed performance gate rejects automatic adoption of both experimental
layouts. Keep A (row arrays) as the product implementation. B (Value columns)
and C (typed numeric/boolean columns with validity buffers and Value fallback)
remain private white-box comparison code, not selectable product backends.

## Evidence and interpretation

- [Complete comparisons](comparison-results.md): every mandatory E2E/prepared
  case, paired intervals, five-phase ranges, recorded capacity and construction
  diagnostics. No favorable-case subset replaces the fixed matrix.
- [Method and reproduction](README.md), [pre-registered matrix](columnar-experiment.json)
  and [physical accounting boundaries](physical-accounting.md).
- 2,478 validated timing samples: 819 additional E2E, 420 legacy E2E, 819
  additional prepared-input and 420 legacy prepared-input. Each condition has
  seven alternating paired repetitions on the specified target matrix.
- 177 separate construction diagnostics. Shared cases have identical counters
  on JS/Wasm/native; these are not timing samples or allocator-wide profiles.

Neither numeric-wide nor nullable-wide achieves a reproducible native improvement
of at least 20% in every member, for either E2E time or whole-process peak RSS.
The mandatory E2E matrix also contains reproducible regressions: 25 B comparisons
and 18 C comparisons. These counts use the pre-registered directional criterion;
they do not mean that every regression exceeds 20% or 10%. No averaging across
cases or targets removes a veto.

The phase evidence indicates that fixture preparation and input admission account
for much of the wide numeric cases' enclosing time. Excluding those costs does
not rescue the adoption case: prepared-input measurements also fail to establish
the required major-group win. This is an inference about these fixed workloads,
not a proof that column layouts cannot help other workloads.

The construction diagnostics make the tradeoff visible. For numeric-project-10000,
A constructs 40,006 data arrays and transfers 720,000 row cell slots; B/C construct
67 data arrays and transfer 670,000 column cell slots. C additionally constructs
67 validity arrays with capacity 670,000 bytes in the nominal storage model.
These reductions in data-container constructions did not yield the required
end-to-end gain. Metadata, expression scratch, initialization, scalar wrappers,
source retention and runtime representation remain relevant; counts are not
converted into invented allocator bytes.

The existing row engine already shares rows in sort/take/distinct/dedupe. It is
not an engine that deep-copies every cell at every step. B/C retain full column
backings through small selections and must account for captured source storage
while importing. Neither side receives a free conversion or a fictitious early
release in the comparison.

## Requirement audit

| Requirement | Evidence and disposition |
| --- | --- |
| Correct take completion first | `1a60db0`; `src/lowering_relation/take_order.mbt` resolves the exact owning pipeline/step and excludes producer-carried history. Preparation, kernel bounds/terms and encoding consume the same decision. `take_inherited_wbtest.mbt` covers shadow, rename, projection/drop, repeated take, branches, producer transfer and empty inputs. `take_completion_wbtest.mbt` retains new-completion and full-key validation coverage. |
| Fix four warnings without hiding them | `6f26014` distinguishes retained ownership, obsolete helpers and bounded codec handling. Whole-target tests pass with `--deny-warn`; no blanket warning suppression is introduced. |
| Corrected A baseline and identical semantics | The fixed baseline is `6f2601473d3fa96d542019cbb6afa78ef1bdd528`. Later shared-kernel refactors apply to A as well as B/C; each report records the actual measurement source, not a relabeled baseline binary. All layouts use the same checked fragments, comparisons, row-major evaluator and sequence routing. |
| Release, phases, repetitions, targets | All four reports pass source/runner hash, exact schedule, target identity, timing-scope and seven-pair validation. Old pre-disposal legacy data is excluded. The complete comparison table retains phase min/median/max and paired intervals. |
| A/B/C rather than transpose-only comparison | Both Value columns and typed number/boolean plus NULL storage run every scheduled case, including text, decimal/time, nested data, projection, shadow, branches and producer inputs. |
| Fixed workloads and adoption conditions | The matrix predates measurements; the approved zero-column case starts with an empty schema, preserves 1,000 rows through `drop: []` and `sort: []`, and does not introduce an illegal take. All-column-drop rejection remains tested. `layout-adoption.test.mjs` checks full-group wins, cross-target regression vetoes and missing/duplicate evidence. |
| Logical budgets, failure order, ownership, identity | `layout_rows_wbtest.mbt`, `layout_sequence_wbtest.mbt`, `layout_input_snapshot_wbtest.mbt` and shared generated-fragment tests cover exact budgets, lazy branches, unused/late failure, producer/Parameter ownership and immutable outputs. Physical layouts consume one checked/generated representation; no storage tag enters wire contracts or semantic identity. |
| Physical ownership and copy/retention costs | Exact/one-below conversion limits, shared-column last-owner release, composed-view overlap, failure cleanup and fresh-budget reuse are tested. The accounting audit separates logical occurrences, unique owned capacity, nominal typed bytes and process RSS. Construction diagnostics explicitly separate cell, row-reference and index transfers. |
| Conditional migration | Performance conditions fail, so no column migration is performed. No new operations, Arrow, SIMD, Host, Cloud or public backend selector is introduced. |

## Validation and limitations

At diagnostic source `fb6db55`, JS/Wasm/native each pass **3,121 tests** with
warnings denied. Public interfaces agree across targets; format, documentation
and metadata checks pass. The measurement/statistics/adoption/report-provenance
Node tests pass **14/14**. The final evidence renderer additionally validates all
four real timing reports and all 177 construction diagnostics.

Linux CI was **not run**. Native results are macOS arm64 / Apple M4 with pinned
MoonBit `0.10.12+1634b282e`, not Linux or production-cloud measurements. Optional
100,000-row runs are not used as substitutes for the mandatory matrix.

RSS remains whole-process peak including warmup, not per-operation memory.
Construction diagnostics count successful source-level data-container paths,
not all allocator calls, scalar temporaries or failed-prefix traffic. The
separate conservative scratch/value limits remain enforced; no claim is made
that the owned-buffer ledger alone is a complete heap meter.

Raw samples, build logs and binaries remain under ignored `_build/`; only source,
tests, methodology and the compact comparison/decision evidence are committed.
There is no push, main merge, publication or new operation implied by this result.
