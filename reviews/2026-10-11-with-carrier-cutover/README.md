# WITH Carrier cutover: current implementation and evidence

## Current finite source

Draft [#1506](https://github.com/actql/actql/pull/1506) targets main. B normally
adopted published main `ece026dda6a48a5a86259f048ca55e553dd87f4f` after its
previous gate terminated. Common check-only #1502 is integrated; INFER/Debug
completion is not a start prerequisite. The reviewed revision remains fixed at
`b5d03b1d38912c52a9ad333a4734155edbec0c70` on Root's design branch. Its 119
supplied IDs and all 130 IDs remain in [acceptance-id-inventory.json](acceptance-id-inventory.json).
No SQL compatibility sidequest, alternate checker/evaluator, compatibility
parser or new acquisition/storage owner is added.

The latest tested product source is `6d0f1a3782d687dc98715ea144e0b8cd177e49c6`,
tree `6201eeb09af32789b0f548e42f03fa7047bba4a0`.
[p1-grammar-pin-execution.json](p1-grammar-pin-execution.json) records actual
JS29/29, corrected SGA Node11/11 and five read-only freshness commands in
`run-Jdvclk`, under the existing 60-second/grace5 nonHeavy guard. Earlier
`4d63461aa` Node87/88 includes 61/61 independent Values vector tests, 6/6
manifest tests and 10/10 profile tests, with one remaining SGA historical-body
assertion failure. Those 77 successful checks belong to that SHA; they are not
an executed Node88 result for `6d0f1a378`. Original failures remain preserved.
Actual Owner6688, its process group and own lock were observed absent.
[prepared-checks.json](prepared-checks.json) contains reproducible limited
commands and exact product source/tree for an independent worktree.

## Implemented P1 boundaries

- One bounded Pure/Compute/Statement parser and lexical WITH resolver. Each
  body resolves before its binder is introduced, with original source spans.
  Whole CTAS wrappers remain Compute; authored/grouped bodies remain Pure.
- Shared SQL/AQL-text WITH lowering through ordinary Program construction.
  JSON/YAML machine inputs and SQL's existing top-level head selection remain.
  The retired DATA parser/count/API route and old pure-constructor spelling
  have no fallback.
- GRAPH primaries, Graph-preserving bodies and existing Graph-to-Relation
  consumers reuse the common constructor/Bridge. Marker-free MATCH resolves
  the same Graph producer as FROM GRAPH, without reconstructing its definition.
- Every binding is statically checked using common typed check-only topology,
  actual Catalog/local inputs and retained order/value/profile obligations.
  Demand follows original producer/import/projection edges. Normal prepare and
  publication remain strict; unused bindings do not evade input-required order.
- Resolved SGA Producer occurrences are included in the conservative Source
  use census. ID/data strings are not mistaken for producer references. Sharing
  does not replace the common checked topology or imply additional authority.
- Retired LABELS property annotations are refused at the authored token; their
  AST field and lexer flag are removed by actual pinned interface generation.
  Graph label membership and ordinary property/literal values remain distinct.

[p1-graph-cutover-execution.json](p1-graph-cutover-execution.json) preserves clean
`f01d05b7` JS27/27, the independent full Program comparisons, bare/marked MATCH,
public selector routing refusals and exact LABELS source location. Public routing
unit tests are not Host execution evidence. The earlier failed12/9/3 and27/25/2
attempts are retained with their real counts and receipts.

## Grammar, profile and identity coherence

The installed P1 grammar now uses WITH producer bodies and GRAPH, without DATA,
PROPERTY GRAPH constructor or LABELS productions. The adopted four-Carrier/P2
semantics and not-yet-installed vector/temporal surfaces stay explicit. Current
query specification and Graph design examples use WITH/GRAPH. Imported design
indices and original historical evidence are not rewritten or marked executed.

Existing generators update compilation manifests, canonical fixtures and
normative complete-document imports. Independent old/new Values preimages are
retained in `scripts/fixtures/pre-with-carrier-cutover-values-identities.json`
and `submitted-with-carrier-cutover-values-identities.json`. Values Program,
Unit and ResultPlan identity are unchanged; grammar-dependent invocation,
executable/compiled Plan and Run identities change. New expectations come from
complete independently assembled preimages, never a runtime's returned CID.
Old stored Runs and source bytes are not reinterpreted under the new grammar.

## Remaining cutover obligations

This Draft is not the completed revision. Remaining work is finite P1/P2:

1. Replace remaining current DATA fixture/caller/tutorial sources directly,
   preserving source semantics, independent rows/types/order and negative cases.
   Immutable receipts and private structural machine fixtures stay intact.
2. Close consistent authored non-Relation alias/type refusals, all four Carrier
   bindings and adopted SGA/VecA/TEA argument-role connections. No second parser,
   scalar-name guessing or generic OP/raw JSON evaluator is permitted.
3. Execute the agreed SQL/AQL-text/README and four-Carrier packed Local/HTTPS
   cohorts with independent Program/value/schema/refusal expectations, same
   request reuse and actual resource release, only in an allocated Heavy slot.

No Heavy, new package producer, public Host/provider execution, Native/Wasm
execution or Hosted CI was started for the current unit. Static/caller results
are not publication acceptance. A common-owner failure gets a minimal source,
Program and exact refusal handoff; it does not block independent frontend work.

## Retained preparation and earlier results

The following records keep their original source and evidence classifications:

- [source-baseline.json](source-baseline.json), [p1-seams.json](p1-seams.json),
  [static-admission-seams.json](static-admission-seams.json),
  [retired-entry-callers.json](retired-entry-callers.json).
- [parallel-edge-controls.json](parallel-edge-controls.json),
  [scope-demand-controls.json](scope-demand-controls.json),
  [four-carrier-controls.json](four-carrier-controls.json),
  [compute-context-controls.json](compute-context-controls.json),
  [graph-definition-preimages.json](graph-definition-preimages.json).
- [p1-binding-preparation-execution.json](p1-binding-preparation-execution.json),
  [p1-demand-check-only-execution.json](p1-demand-check-only-execution.json),
  [p1-demand-common-order-handoff.json](p1-demand-common-order-handoff.json).
- [p1-source-replacement-execution.json](p1-source-replacement-execution.json):
  clean `4710de15` JS31/31 and formatting, separate from later submitted sources.
  Private `7c1e7ddb` JS15/15 remains evidence for that SHA, not all-main PASS.
- [p1-execution-index.json](p1-execution-index.json),
  [p1-graph-binding-execution.json](p1-graph-binding-execution.json),
  [p1-shared-route-execution.json](p1-shared-route-execution.json).

Unmodified failure receipts remain alongside these records. B preserves its
incremental build and borrowed pinned yaml dependency; no foreign worktree,
shared Heavy lock, custody or original package evidence was changed.
