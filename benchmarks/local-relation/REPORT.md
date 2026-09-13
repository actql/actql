# Local Relation execution: integrated findings

Row storage remains the default. Typed layouts, limited kernels and the product
completion/producer connection have been tested for extensibility, and the
necessary internal boundaries have been established. Performance regressions
remain: they were accepted for continued implementation, **not as a passed
performance gate**. The subsequent one-pass recovery is a measured candidate,
not an implicit decision to adopt columns or start another optimization cycle.

This is the current entry point. [Reproduction](README.md),
[physical accounting](physical-accounting.md) and
[machine-readable evidence](evidence/README.md) support it. Documents in
`archive/` are historical snapshots; their stops and pending approvals do not
describe current blockers. Git history and experiment code are preserved.

## Questions answered

| Question | Finding and boundary |
| --- | --- |
| Should the product switch wholesale to columns? | No demonstrated benefit under the fixed A/B/C adoption matrix. Keep rows as default; this does not reject columns for other workloads. |
| Must a storage change rewrite typing/lowering/identity? | The tested alternatives stayed within execution adapters and kernels. Shared contracts and meaning were unchanged. |
| Can a limited typed kernel share semantic machinery? | Yes: frame transitions and demand/charge/root events are shared. The numeric conditional experiment avoids full row snapshots, but still schedules rows/slots; general vectorization is not proven. |
| Can typed output cross the real product producer boundary? | Yes: limited typed derive → CompletedSequence/CompletedOutput → binding/admission → select → stable sort → product completion, without a full row-matrix conversion. |
| Can all consumers remain typed? | No. Supported projection/index adapters retain numeric buffers; other expression bodies use a bounded row-output builder selected before execution, never as error fallback. |
| Are stateful/distributed execution mechanisms ready? | No. Private split-input sort exercises append/end/read/dispose while retaining all input. Join/group/window, spill and parallel scheduling need further state/resource design. |

The product default still uses row storage; experimental A/B/C backends are not
public options. The private numeric completion adapter is product code, while
the limited typed derive kernel remains test-only. Neither Arrow support nor
whole-Program/Run/Host/Effect/Result publication follows from these experiments.

## Adopted structure and invariants

Permanent design is documented separately:

- [Physical storage](../../docs/design/local-relation-storage.md): layout does
  not enter semantic identity; shared selection and copy/retention costs matter.
- [Expression frames](../../docs/design/execution-expression-frames.md): shared
  demand, representative failure, charge and root-lifetime transitions.
- [Completion storage](../../docs/design/execution-completion-storage.md):
  successful execution evidence, physical representation and backing ownership
  are distinct but cannot be freely recombined by callers.

Completion and producer admission do not depend on ExpressionFrame's
stop/resume interface. Removing resumability from a future synchronous path
must not require changing this boundary. Public completion remains opaque;
there is no public mutable buffer accessor or disposal operation.

Checks preserve checked-owner/target/Parameter relationships, NULL, duplicates,
column and row order, stable ties, mandatory evaluation, lazy demand, failure
atomicity and fresh-budget reuse. Physical sharing does not discount logical
occurrences. Full backing capacity remains charged through small selections.
Container units, logical value bytes and process RSS are different measures;
no complete allocator-level memory cap or immediate GC release is claimed.

## Performance evidence and decisions

The layout experiment used 2,478 release timing samples and 177 separate
construction diagnostics. Neither B (Value columns) nor C (typed columns)
met the preselected native major-group 20% improvement condition. Mandatory
E2E comparisons contained 25 B and 18 C reproducible directional regressions;
those counts include small changes, not only large regressions.

For numeric-project-10000, A constructed 40,006 data arrays versus 67 for B/C,
with 720,000 row-cell transfers versus 670,000 column-cell transfers. C also
constructed 67 validity arrays with nominal capacity 670,000 bytes. Lower
construction counts did not imply the required timing gain. Current row
selection already shares payload; this was not a comparison against deep-copying
every cell after every operation. Full matrix statistics remain in the selected
layout evidence and the [historical appendix](archive/comparison-results.md).

The historical evaluator comparison stopped without passing the gate: 812
samples, 37 completed decisions, and 14 trailing samples without decisions.
The stored raw status says `running` because termination bypassed finalization;
it must be interpreted as stopped, not complete. Native prepared regressions
motivated frame/event attribution and the first bounded improvement pass.
Synchronous draining and removal of binary-event temporary arrays improved
native prepared cases about 5–8% versus the extracted evaluator, but did not
restore the old baseline. `f025ce4` was explicitly accepted for continuation.

All later diagnostics fix four 1,000-row cases, native/JS, E2E/prepared,
seven alternating pairs per cell: 224 processes per comparison. They are not
the full matrix. Descriptive paired-bootstrap intervals are not family-wise
guarantees; an uncertain cell remains uncertain without extra samples.

| Comparison | Purpose | Time cells: within / regression / uncertain |
| --- | --- | --- |
| bafdc88 → 2e913f2 | Post-completion residual, separate run | 4 / 9 / 3 |
| f025ce4 → 536fef9 | Direct completion-boundary attribution | 10 / 0 / 6 |
| 536fef9 → 8b3a625 | One local recovery patch | 6 / 0 / 10 |
| bafdc88 → 8b3a625 | Residual after that patch | 2 / 8 / 6 |

All RSS cells in these four diagnostics were within the fixed 10% threshold.
`within` is a cell result, not a gate pass. The direct attribution does not
support assigning the larger earlier separate-run residual to completion alone.

The recovery removes only a confirmed empty storage-reservation callback on the
ordinary row path; typed storage still invokes its actual capacity hook. Its
product commit is `c6c0608` on main `974ae98`; the identical historical-base
cherry-pick `8b3a625` was measured to avoid mixing main changes into attribution.
JS conditional prepared time improved by a paired median 12.0% (marginal median
difference -1.770 ms), but other cells were small or uncertain. Conditional E2E
point estimates worsened (native +8.4%, JS +6.3%), also uncertain. This is not
evidence of an engine-wide recovery or a causal decomposition of all costs.

| Prepared case | Latest paired residual vs bafdc88 | Median time difference |
| --- | ---: | ---: |
| native numeric projection | +5.5% | +0.250 ms |
| native conditional | +12.8% | +0.367 ms |
| native ordered | +10.5% | +0.890 ms |
| native long expression | +12.2% | +3.532 ms |
| JS numeric projection | +10.2%, uncertain | +0.905 ms |
| JS conditional | +12.9% | +0.925 ms |
| JS ordered | +1.7%, uncertain | +0.140 ms |
| JS long expression | +2.8%, uncertain | +1.242 ms |

Paired-ratio medians and differences of marginal medians are different
estimators. Do not add percentages across runs or infer API latency from these
fixtures. Historical revision IDs intentionally identify measured binaries;
they are not rewritten to newer rebase equivalents.

## Verification and remaining work

The latest implementation verification at `c6c0608` passed whole-repository
JS/Wasm/native checks and 3,401 tests each with warnings denied, API consistency,
format, documentation, metadata and 14 comparison-infrastructure tests. Linux
CI was not run. This documentation consolidation does not relabel earlier
performance measurements as measurements of the current main-based binary.

Relevant maintained regression families include `take_inherited_wbtest.mbt`
(owned take completion), `layout_*` (storage/selection/ownership),
`extensibility_*` (limited kernels and lifecycle), `expression_frame_wbtest.mbt`
(frame scheduling), `completed_*` (real completion/producer connection,
immutability, NULL/empty inputs and cumulative exact budgets), and
`storage_hook_wbtest.mbt` (absent and explicit physical hooks).

Remaining decisions are acceptance of the latest recovery candidate and scope
of the next feature. Remaining technical limits are general batch scheduling,
broader typed kernels/storage, stateful algorithms, spill/parallel execution,
Arrow/SDK integration, unmeasured Wasm/typed-path performance and full-matrix
performance acceptance. Another layout still needs private storage/ownership/
capacity adapters; another specialized kernel must preserve demand and lifetime.
Locality was demonstrated for the tested changes, not arbitrary future engines.

## Evidence retention

Selected machine-readable statistics for 13 report sets and all 177 construction
observations are now tracked under `evidence/`, with original source hashes and
comparison identities. They are summaries, not substitutes for raw admission,
sample-order or output-assertion audit. Full raw reports, stdout/stderr, build
logs and binaries remain in ignored `_build/` and have **not** been deleted or
uploaded to an external artifact store. They are not protected by Git. A complete
raw backup is still required before any cleanup of those local directories.
