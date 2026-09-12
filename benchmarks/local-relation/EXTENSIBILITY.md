# Execution extensibility experiment boundary

This experiment tests change locality, not column-storage adoption. The product
row implementation remains selected. Timing is supporting evidence, not the
previous twenty-percent adoption gate.

## Frozen edit boundary

Baseline: `f9ac87b`, main `8d24f6d` followed by the original 143 separate
authorization-design and lowering commits. Historical layout evidence remains
attached to its original commits; it is not regenerated under new identities.

Allowed implementation files are new `src/execution_relation/extensibility_*_wbtest.mbt`
files only. They may consume existing package-private kernels, typed lowered
expressions, layout readers/builders and ownership ledgers. Existing layout
experiments are reused, not rewritten. No product file is in the initial edit
allowlist. This report and a design rationale in `docs/design` may be added or
updated; design documents must not contain delivery progress.

Changing the common driver, expression evaluator, completion representation,
other kernels, lowering, typing, registry, wire schemas or pins requires a
report before proceeding. A prototype-local adapter is allowed; copying the
language evaluator or its accounting to evade a missing common seam is not.
Product boundary changes are a separate decision, not an incidental experiment
step. Private completion experiments are not product execution evidence.

## Historical footprint audit

The subsequent scope approval permits `rows.mbt`, `expression.mbt` and necessary
private implementation/test files in this package. Boundary extraction must be
verified and committed independently before the typed-batch trial. Driver,
public completion types, lowering, typing, shared contracts and budget rules
remain excluded. The initial no-product-edit rule above records the original
boundary, not the scope after this explicit approval.

Including `700e1a5`, the range `700e1a5^..7d84d96` changes 13 product files,
758 added and 335 removed lines, all in `execution_relation`. The range excluding
the first commit is 12 files and 1,043 changed lines. The 1,093-line footprint
does not mean that every later storage addition requires these changes.

| Change | Classification | Existing reuse evidence |
| --- | --- | --- |
| `IndexedRows`, `RelationRows`, `RowValues` | Initial reader generalization | Row and column readers call identical selection kernels |
| `evaluate_row_body_into` | Initial output-sink extraction | Column builder uses the existing row evaluator |
| `evaluate_*_selection` | Initial selection/materialization separation | sort/take/distinct/dedupe adapters reuse index results |
| `prepare_sequence_with_importers`, `run_sequence_with_backend` | Initial import/backend separation | Layout tests reuse sequence routing and admission |
| `TableStore[T]` release callbacks | Layout-independent lifecycle requirement | Both layouts run consumer retirement and failure cleanup |
| Layout adapters/builders/leases | Per-storage implementation | New representation supplies physical operations and lifetime rules |
| Traffic/profile runners | Experimental instrumentation | Not language or product execution semantics |

Remaining dependencies are concrete: `CompletedSequence.store` uses
`TableStore[Table]`, `CompletedOutput.table` uses `Table`, and producer admission
reads that table. The row-body sink still receives `Array[Value]`; expression
evaluation reads a `Map[String, Value]` and `Array[Value]` slots. These are
different issues from storage-only replacement. Whether they require product
changes is an experiment result, not assumed successful integration.

## Observation contract and independent expectations

Use checked expressions and operator ownership, not fixture-name dispatch or
source reparsing. Kernel selection is operation-wide and precedes execution;
unsupported vocabulary selects the existing evaluator before work starts.
Runtime errors and exhausted budgets never cause fallback.

Compare chunk widths 1, 7 and 1000, including failures on either side of a
boundary, nullable input, undemanded failing branches and discarded slots.
Fixed expected values/errors are independent of the product evaluator; row
comparison is additional evidence, not the sole oracle.

| Observation | Required comparison |
| --- | --- |
| Values | Types, values, NULLs, multiplicity, row order |
| Demand | No evaluation or charge for unselected children; no omitted slots |
| Failure | Normative row/slot/child priority and classification |
| Logical limits | Exact boundaries, precharges, retained roots, cleanup |
| Physical limits | Each layout enforces its own bounds; equal success under equal physical limits is not required |
| Completion | No partial output on failure or before input completion |
| Identity | Physical representation and chunk width do not alter semantic identity |

Normative owners include language requirements `common-expression-contract.demand-validation`,
`derive.ordered-resource-measures` and `derive.ordered-work-measure`. All input
validation precedes shadowing; logical charges precede traversal/construction.
Selecting the smallest value error after unbounded speculative evaluation is
not sufficient. Unspecified error/physical-limit priority is reported rather
than invented by the trial.

## Experiments and stopping point

1. Conditional numeric derive, masked lazy branches, multiple slots, and
   operation-level preselected row fallback. Do not introduce an independent
   general expression interpreter.
2. Stateful stable sort with append/end/output/dispose, preserving cross-chunk
   ties and retaining actual buffer ownership. Reuse the sort kernel.
3. Typed buffer input through a successful private output and a consumer,
   checking immutable lifetime and identifying any forced row conversion.

Record permitted files touched, unchanged consumers, conversions, retained
buffers and dependencies that recur per added operation. A design success is
not a product adoption decision. Report results before product boundary repair.
Join/group/window receive interface/scenario review only. Spill, parallel
execution, Arrow, external backends, SDKs and Program/Run publication are not
implemented or claimed validated.

## Evidence log

- Rebased baseline JS suite: 3,333 passing tests. This is baseline evidence,
  not completion evidence for the new experiment.
- `extensibility_sort_wbtest.mbt` introduces a private receiving/completed/disposed
  lifecycle around the unchanged `evaluate_sort_selection`. Chunk coordinates
  address retained typed buffers directly; there is no intermediate row matrix.
  Three tests pass on JS, Wasm and native. Fifteen-row fixed ties cross chunk
  width 7, with widths 1 and 1000 checked too. Shared-kernel work and workspace
  counters agree with whole-input selection. The original input handles can be
  released before sort while their 270 typed bytes remain retained by chunks.
  Late row-limit and kernel-control failures clear the pending handles and
  output, and disposal returns charged live capacity to zero.
- This first sort trial does not yet establish independent typed input admission,
  product completion/producer integration, conditional batch evaluation, or the
  full budget-boundary matrix. Those remain required investigations. The sort
  trial is blocking/in-memory: it is not streaming sort, spill or parallelism.

## Conditional derive: edit-boundary finding

The current common sink is after evaluation and accounting, not a pluggable
evaluation strategy. `evaluate_row_body_impl` in `rows.mbt` constructs a
`Map[String, Value]` snapshot for every non-projection row and calls
`evaluate_expression_retained` directly for both map and ordered bindings.
It then constructs `Array[Value]` output and invokes the physical sink.
`evaluate_expression_impl` in `expression.mbt` owns both continuation dispatch
and logical entry/operand/result charging. Its frame inputs are concrete
`Map[String, Value]` and `Array[Value]`, not typed-column or masked-batch views.

Consequently, the available reuse paths have different limitations:

| Path | What it preserves | What it does not establish |
| --- | --- | --- |
| Existing column sink | Shared demand, failure and accounting | No alternate evaluation strategy; still boxes every snapshot cell |
| Chunk loop around whole row evaluator | Existing evaluator semantics per call | Full-input admission and pending-output roots must not reset per chunk |
| New private numeric/mask interpreter calling budget primitives | Reusable scalar arithmetic and primitive counters | Duplicates demand, continuation and root scheduling instead of sharing them |
| Evaluate first, replay accounting later | Possible value comparison | Violates the required precharge boundary; cannot stand in for conformance |

This is a concrete request to expand the frozen edit scope, not proof that
columnar execution is impossible or a request to change language semantics.
The minimal proposed first expansion is `rows.mbt` and `expression.mbt`, plus
dedicated private implementation files in this package if needed, to expose a
common evaluation/frame boundary without changing the existing row wrapper.
The experiment must continue sharing demand, failure and root accounting;
merely adding an arbitrary alternate-evaluator callback is insufficient.
Any further need to change budget primitives, completion, driver, lowering or
contracts must be reported separately before editing them.

At that audit checkpoint, no such production edits had been made. The approval
and subsequent experiments are recorded below. The
Table-specific completion/producer boundary is a second, independent finding;
this proposed expansion does not authorize rewriting it or claiming a private
test completion is the existing product `CompletedOutput`.

## Approved frame extraction evidence

After scope approval, the first product extraction is confined to
`expression.mbt`. The existing synchronous evaluator now drains the same
resumable frame transitions. Entry/operand/result charges, continuation choices
and root operations stay in that single implementation. A terminal frame cannot
advance again, and cancellation closes temporary roots without refunding work
or freeing borrowed inputs. This extraction is not itself typed-batch support.

`expression_frame_wbtest.mbt` adds three tests: independent lazy/arithmetic work
vectors with quantum 1/7/1000 and exact/one-short caps; cancellation with a live
left operand and a separately owned root; and value-vs-budget failures plus
terminal result-root transfer. Together with existing regression tests, JS,
Wasm and native each pass 3,339 tests with `--deny-warn`. Document and metadata
checks pass. Linux CI and performance regression measurement are not included
in this extraction evidence. No driver, public completion type, lowering,
typing, contract or budget rule changed.

## Typed inlet and private consumer connection

`extensibility_typed_input_wbtest.mbt` supplies a restricted numeric physical
inlet: schema order, lengths, nullable validity, finite/canonical numeric cells
and row/control limits are checked before copying into sealed typed buffers.
It constructs no input row matrix. The source owner and destination have
separate nominal capacity leases: two two-row columns require 36+36 bytes
during copying, a 71-byte cap rejects and rolls back the partial destination,
and a 72-byte cap succeeds. Mutation of caller values after capture cannot
change the destination. This is not arbitrary artifact or producer admission.

`extensibility_consumer_wbtest.mbt` connects this inlet to the existing sort
trial and an actual checked select consumer through `evaluate_row_body_into`.
The private sorted view exists only after successful input completion and is
borrowed synchronously while consuming. It is not the public `CompletedOutput`.
Widths 1/7/1000 yield the independently fixed order
`0,3,6,9,12,1,4,7,10,13,2,5,8,11,14`. Consumer work is independently derived
as 75 admitted-input units + 15 row entries + 45 retained-output units = 135;
the live-root peak is 200 input bytes + the first 7-byte output = 207.
Both exact caps pass; 134 work or 206 live bytes fail with the corresponding
typed error and release pending output. A fresh consumer can use the retained
successful sort without rerunning it. Its typed output survives sort disposal.

The consumer still constructs one temporary `Array[Value]` per output row in
the common projection evaluator. It does not accumulate an intermediate row
matrix, but this is not evidence of entirely boxing-free execution. Supporting
the existing public producer API with this physical output still requires the
separate completion/admission change identified above. No such change is made.
The inlet/consumer connection also does not close the conditional batch-kernel
experiment, which remains a separate requirement.

## Bounded typed-slot/mask experiment

The approved continuation extracts shared expression events in
`expression_events.mbt` and output-root lifetime ordering in `row_events.mbt`.
The ordinary frame and row evaluator use these events. The test-only
`extensibility_batch_*_wbtest.mbt` specialization consumes already checked
expressions and does not call either `ExpressionFrame` or the ordinary row
evaluator for supported bindings. Its supported shape is numeric/boolean
leaves, a binary expression over leaves, and an IF whose condition and arms
each have that shape. Arbitrary nesting and other vocabulary select the
ordinary evaluator for the whole operation before execution. Resource failure
is never a fallback request.

Slot values are stored in typed column buffers, with a branch mask per binding
and chunk. Execution remains row-major: a selected branch runs only for its
lane; no unselected branch is evaluated or charged. There is no per-row input
map or output `Array[Value]` in this specialized path. Scalar operations and
canonical measurement still use transient `Value` scalars. This is not SIMD,
parallel evaluation, entirely boxing-free computation, or proof that arbitrary
expressions can be vectorized cheaply. Chunk sizes bound slot buffer retention,
not the pending whole-operation output or all-input admission.

Independent accounting for the fifteen-row two-slot fixture is 825 work and
314 peak logical bytes. Exact caps and one-short caps are compared with the
ordinary evaluator at widths 1/7/1000. Other fixtures cover NULL/empty input,
unselected division failure, row-before-slot failure, failures just before and
after a width-seven boundary, and preselected row/typed operations in one
private producer-consumer chain. The two-row fixture separately bounds typed
output plus temporary slot/mask bytes: 74 bytes at width 1 and 94 at widths
7/1000, excluding its separately borrowed input. Failed allocation disposes
temporary/output leases; logical roots return to zero. These are nominal
buffer units, not process RSS.

### Change-locality findings

| Change | Boundary and remaining cost |
| --- | --- |
| Another physical storage layout | Existing generic readers and builders cover the earlier A/B/C experiment without typing, lowering, identity or contract changes. A new layout still needs storage ownership and budget adapters. |
| Another bounded typed expression kernel | Specialization and target kernel are local after shared semantic-event extraction. Each new expression shape must explicitly preserve demand and lifetime; scalar arithmetic is not copied. No generic claim for arbitrary batch expressions follows. |
| Typed output or row-selection view | Private sort and checked consumer can share buffers and row coordinates. The product completion/admission path remains Table-specific and is **not** established as locally replaceable. Changing it needs separate approval. |
| Split input for blocking sort | Private append/end/read/dispose lifecycle works around the existing kernel. It retains the whole input and pending output. This is not streaming sort. |
| Join/group/window, spill or parallel scheduling | These require additional state and ownership design, not only swapping storage. They remain outside implemented support. |

The accumulated-cost signal is now concrete: a typed conditional kernel does
not add new row snapshots to other kernels or modify the driver. The ordinary
row fallback still creates temporary row arrays; adding further kernels only
through that interface would repeat this conversion. The shared events remove
duplication of selected accounting and root rules, not all work needed to
support a new expression language shape.

For future stateful operations, a join needs distinct left/right input-complete
signals and ownership of retained build keys/payload while probing; group needs
keyed accumulator state, pinned numeric laws and finalization; window needs
partition/order/frame state. Append/end/read/dispose expresses their lifecycle
outline but does not implement these states or prove their budget semantics.
Any incrementally generated output stays private until the required completion
boundary. A late failure must destroy pending output and owned state while
leaving separately borrowed input owners intact. Spill additionally needs I/O,
cancellation and external resource ownership, so it is not classified as a
storage-local optimization.

Product storage remains rows. No driver, public completion type, lowering,
typing, shared wire contract or budget rule is changed by this experiment.

### Verification and stopping boundary

JS, Wasm and native each pass 3,350 tests with `--deny-warn`. Public API
consistency, formatting, document validation, links (982) and metadata checks
pass. The existing release harness smoke passes A/B/C on all three targets
(nine invocations). Its first sandboxed attempt failed in macOS `time`/sysctl,
not in the output assertion; the authorized unsandboxed rerun completed.
This smoke verifies the harness and one narrow representative case, not a
statistical before/after performance-regression bound. No new speedup claim or
column-adoption decision is made. Linux CI remains unexecuted.

The experiment stops here. General batch expression scheduling, a complete
performance regression study, public completion migration, alternate backend
admission and the stateful algorithms discussed above are not completed or
silently authorized by these results. The private successful-output connection
is deliberately not reported as product producer compatibility.
