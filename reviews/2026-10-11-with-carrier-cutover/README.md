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

The latest tested product source is `dcd402f4a196cbc8f0d0bd3d1964a89deb1ffa57`,
tree `1248b74577adb18d2a21d4ff3abbeefb9137b8ea`.
[p1-graph-row-alias-execution.json](p1-graph-row-alias-execution.json) preserves
JS17/17 and five read-only freshness checks in `run-Ufj9hv`, and the two corrected
independent current-vector assertions Node2/2 in `run-T6stAJ`, under the existing
60-second/grace5 nonHeavy guard. Node91/93 on earlier `aedb20368` retains its two
stale-current-literal failures; it is not Node93/93 on the latest source. Earlier
`f3dd115f6` Node5/5 and JS7/7 remain separate caller-migration evidence. All actual
Owner/group/own locks were observed released.

The direct connector caller is **not closed**: `run-T6stAJ` failed compilation
before any JS test due to missing `QueryLowering(RangeAliasRequiresRelation |
BindingPreparation(_))` cases in E/Root-owned `client_check.mbt:314`.
[p1-diagnostic-caller-handoff.json](p1-diagnostic-caller-handoff.json) retains
its exact source, command and required common diagnostic/disclosure boundary.
The independent JS selection does not bypass that required product caller or
make public preparation/Host execution complete. B has not edited that owner.
[prepared-checks.json](prepared-checks.json) contains the reproducible independent
commands and source/tree; the failed command remains in the separate handoff.

Previous `6d0f1a378` JS29/29, SGA Node11/11 and five freshness checks remain in
[p1-grammar-pin-execution.json](p1-grammar-pin-execution.json). Earlier `4d63461aa`
Node77 successful assertions belong to that SHA. Original receipts are unchanged.

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
- Graph FROM/Pipe row aliases parse consistently and receive the adopted
  `RangeAliasRequiresRelation` static reason before the existing Graph owner.
  Producer aliases and ordinary row aliases after an explicit Relation bridge or
  MATCH SELECT remain valid; no row schema is fabricated for Graph.
- Current Graph rows public fixture sources use WITH/GRAPH directly. Their 23
  normal/13 refusal declarations preserve complete independent metadata and JSON
  controls. Old authored text is retained in
  [pre-with-graph-row-source-input.json](pre-with-graph-row-source-input.json) only
  as history. Representative checker tests are not complete cohort execution.
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
The preceding WITH closure is additionally retained in
`scripts/fixtures/pre-with-graph-range-alias-values-identities.json`; grammar
`sha256:f9006fa913e4abfee8c8348a093db8405eb546bf39a625824d42079441a843c4`
and Run `sha256:8c387d8fbe388e526cafc19402cf5cc3091035092b97df1a99061e31436bd444`
come from independently checked full preimages, not observed runtime CIDs.

## Remaining cutover obligations

This Draft is not the completed revision. Remaining work is finite P1/P2:

1. Replace remaining current DATA fixture/caller/tutorial sources directly,
   preserving source semantics, independent rows/types/order and negative cases.
   Immutable receipts and private structural machine fixtures stay intact.
2. Complete the diagnostic caller handoff, the remaining four Carrier alias/type
   connections and all four Carrier bindings and adopted SGA/VecA/TEA argument-role connections. No second parser,
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
