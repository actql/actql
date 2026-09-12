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
