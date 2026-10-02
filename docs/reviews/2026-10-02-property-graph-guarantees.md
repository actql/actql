# Property Graph guarantee migration ledger

## Decision and evidence rules

The current decision removes the executable tuple Graph implementation, not
its generic resource and custody obligations. Historical sources are available
in Git. Inert text copies are not readers, fallbacks or compatibility adapters.
An unsupported-operation test does not establish that operation's former
capacity, completion or cancellation guarantee.

Three classifications are used below:

- **Retired representation**: an expectation required tuple construction or
  endpoint-pair identity. It cannot be a positive current Graph expectation.
- **Required guarantee**: capacity, input ownership, cancellation, cleanup,
  bounded preparation or publication atomicity must survive on current Graph.
- **Unsupported consumer**: no current implementation is connected. Refuse at
  the checked boundary without a tuple fallback; do not claim its old algorithm
  or resource proof migrated.

Focused successes are not aggregate Core/spec/CI acceptance. The published
#164 checkpoint is not the tested local source. Final acceptance requires the
public snapshot and required CI at the same submitted SHA.

## Current obligations

| Obligation / old failure group | Classification | Current executable evidence | Remaining work |
| --- | --- | --- | --- |
| Tuple constructor and endpoint-derived edge identity | Retired representation | `query_integration/property_graph_provider_profile_wbtest.mbt` rejects the old constructor; current keyed constructor retains independently keyed parallel edges | Audit remaining product symbols, readers and provider branches; negative tests alone do not remove them |
| Graph builder capacity/work/cancellation and no partial publication | Required guarantee | `managed_graph_storage/storage_wbtest.mbt`, `property_storage_wbtest.mbt`; current constructor tests in `query_integration/property_graph_construction_wbtest.mbt` | Repeat aggregate verification at submitted source |
| Completion, exact consumer/input owner, revocation, final reclamation | Required guarantee | All seven migrated `managed_graph_runtime/output_wbtest.mbt` lifecycle cases; keyed provider foreign-input and cleanup tests | Keep these positives, not substitutes that merely refuse old input |
| Snapshot byte limits, cancellation, trusted read schema, corrupt/interrupted reload | Required guarantee | `query_integration/property_graph_snapshot_wbtest.mbt`, `managed_graph_runtime/property_snapshot_wbtest.mbt` | Fresh public Local/HTTPS save → revoke original Source → reload → MATCH/TRAIL at submitted SHA |
| Repeated constructor input occurrences and mixed definition roles | Required guarantee | `pipeline_typing/construction_test.mbt`, `operation_obligations_test.mbt`; `capacity_program_step/property_graph_test.mbt` | Migrate remaining imported input/preflight fixtures |
| Distinct node/edge extents, producer owner and no fabricated row proof | Required guarantee | `pipeline_typing/produced_input_test.mbt`, `graph_counts_test.mbt`; current MATCH node/edge cases | Empty declared node universe exposed a real upper-bound regression; minimal `row_counts.mbt` fix preserves zero edges while still debiting every operand |
| MATCH predicate types, typed identity rows, downstream Relation consumers | Required guarantee | `pipeline_typing/graph_test.mbt`; `lowering_relation/graph_match_test.mbt` | Migrate Program and query integration inputs without Frontend-specific evaluation |
| TRAIL selector owner, bounded preparation, empty selector counts, row guard vs proof | Required guarantee | `pipeline_typing/graph_test.mbt`, `graph_report_counts_test.mbt`, `graph_empty_selector_audit_test.mbt`, `author_guards_test.mbt` | Retain current paths positives and exact/one-short tests |
| Graph input bound owner, foreign dependency rejection, imported closure, limit consumption | Required guarantee | `capacity_graph_preflight` now uses a definition-keyed Graph schema and scoped MATCH; original owner/unit/collection/exact-limit assertions remain | Four algorithm-dependent fixtures remain unresolved; no aggregate success claimed |
| Diff/apply, union/graft/subtract/mean, structural counts, report bounds, reach/shortest | Unsupported consumer | Current typing/lowering and diff refusal tests; legacy algorithm implementation is not a fallback | Remove remaining obsolete execution branches. Old algorithm-specific count/schema proofs are not claimed preserved. Keep generic projection/owner guarantees in supported fixtures |
| Consumer coverage and strict resource inventory | Required guarantee + unsupported consumers | Inventory distinguishes connected partial Graph routes from blocked routes | Aggregate spec remains red; do not remove checks or silently retain old completion claims |

## Latest narrow pipeline unit

The five migrated files (`graph`, `graph_unary_audit`, `graph_bounds`,
`graph_counts`, `graph_report_counts`) pass **11/11 on JS, Wasm and native**.
Logs: `/private/tmp/property-graph-pipeline-graph-contract-{js,wasm,native}-20261002.log`.
The empty-universe count regression failed before the `row_counts.mbt` fix:
`/private/tmp/property-graph-empty-extents-before-20261002.log`.
This is a static upper-bound regression, not evidence of corrupt runtime rows.

Five pure tuple-algorithm fixture files are withdrawn from executable tests:
`union_list`, `path_counts`, `mean_counts`, `mean_acceptance_audit`, and
`graph_structural_audit`. Their nine positive tests concern currently
unsupported consumers. They are not reported as nine migrated resource proofs.
Ten original files are byte-identical inert copies of source
`01c19faf0aa7d9a690ae09c66e98bac43d7e2e28`; Git remains the historical authority.
Non-Graph positives in mixed files remain executable.

Full pipeline, Core, spec, fresh packed acceptance and required CI have not
been rerun for this unit. The previous full pipeline at `d5e2b5b49` remains
343 total / 308 passed / 35 failed; it is not this unit's result.

## Preflight owner migration

The shared current input has independent N/E key definitions and an explicit
identity domain. Graph-to-Relation proofs now use the existing
`actql.bound.match-nodes` / `actql.bound.match-edges` laws; bound witnesses still
come from the original input owner. Imported input closures retain exact owner
registrations, reject foreign or missing dependencies, copy caller arrays and
enforce cumulative input/application work. No capacity owner or proof checker
is replaced or weakened.

The supported TRAIL fixture retains separate search-path/output-row scopes,
missing/foreign candidate and subject rejection, unused-branch coverage,
caller-array retention, missing/duplicate application rejection and
exact/one-short budgets. Its typed start belongs to the declared N/domain;
the retired traversed-node output is not claimed supported.

Focused native evidence is **14/14 plus 1/1 plus 1/1**:
`/private/tmp/property-graph-preflight-supported-native-20261002.log`,
`/private/tmp/property-graph-preflight-bound-owner-native-20261002.log`, and
`/private/tmp/property-graph-preflight-import-owner-native-20261002.log`.
The current complete Wasm package is **32 total / 28 passed / 4 failed**:
`/private/tmp/property-graph-preflight-current-trail-wasm-20261002.log`.
JS's preceding package run was **32 / 27 / 5**, followed by the migrated
TRAIL file **1/1**; that is not a new aggregate JS result. An attempted full
native package aborted at the still-obsolete `resolved_output` fixture with
SIGABRT; only the explicit focused native runs above are counted.

The remaining four cases are the old union composition, normalize/subgraph
bound forwarding, components ledger, and resolved components/traversed-node
output chain. The resolved-output guarantee still needs a supported positive
counterpart; it must not disappear under a blanket refusal. Initial migration
fixtures had a zero field ceiling despite a one-component key and omitted
the required node-MATCH predicate. Those fixture errors were corrected without
changing admission or capacity rules.

Latest fetched main is `0fd6332757176b88e8c4071e4a2cd0be3d6254e3` (#185/#188).
It has not yet been integrated into these local source checks. The published
#164 remains `125a186ae9396fbfc7865641922e8e8a4ffc87d9`, Draft and not GO.
