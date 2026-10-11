# Checked topology before WITH demand

This finite common-owner dependency separates complete pipeline/declaration
checking from Result publication-order closure. The motivating independent
Program captures a Catalog-backed nullable object but exports only a separate
constant row. Ordinary preparation rejects its unused capture at
`stages[0].results.source` with `UnresolvedOrder` before the frontend can select
demand. The old frontend counterexamples and expected Programs remain unchanged
in B's WITH cutover branch.

## API and invariants

- `stage_results.check_local_program` returns opaque `CheckedTopology` and usage.
- `pipeline_check_context.check_sourceview_program` returns opaque
  `SourceViewCheckedTopology`, retaining the exact Catalog registrations and
  their attachments as well as local environment ownership.
- `relation_results.prepare_checked_inputs` projects the checked inventory via
  the existing Select checker and `pipeline_typing.project_produced_input`.
  Original pipeline, target, projection, source Cursor, conditional key/value
  evidence and logical order are retained. It issues no `ResultPort`, publication
  strategy, Plan, Run or execution permission.

The same internal Stage loop checks every pipeline, parameter collection, local
input, Result inventory and private Table declaration in both modes. Import
resolution and exact producer attachment are shared. Check-only also runs the
existing contextual order closure across producer ancestry: unresolved order
needed by an operation such as Take is still refused, including in unused bodies.
Only Result publication-order resolution is deferred. Authored Result definitions
and their `TotalDeterministicOrder` obligations remain accessible through the
checked inventory. Calendar/ModelTask handles are retained. Remaining runtime
value, capacity, binding and operation-profile obligations are not discharged.

The ordinary `prepare_local_program`, SourceView preparation and publication
binder remain strict and accept only their existing publication types. No order
error is caught and ignored. A checked topology cannot be supplied as prepared
publication wiring. After demand changes the authored Program, callers must
recheck that new source with the normal strict path; old checked handles cannot
be transferred to its stages.

## Independent controls and actual evidence

The independent local and Catalog Programs cover dead capture, imported capture,
repeated import occurrences, exact producer/projected input identity, original
Cursor and pending Result order, an unused invalid filter, Catalog/partition
absence or mismatch, required input-order refusal and bounded accounting.
[Catalog preimages](catalog-independent-preimages.json) are the unchanged
independently authored shared fixture; expectations are not regenerated from
product output.

Clean source `904b58f6c4ba4585d11e416c23ec7b767c55e1d1`, tree
`2ab7f5dce2090092dca16ba64cdda7ed9551739d`, passed JS **20/20** in
`run-HYeuFs` using the existing nonzero wrapper, timeout **60 seconds**, grace
**5 seconds**, nonHeavy. Selection: `stage_results/{checked_topology_test,
local_program_test,imports_test}.mbt`, `pipeline_check_context/{checked_topology_test,
calendar_topology_test}.mbt`, and `relation_results/ports_test.mbt`.
Pinned `moon info --target js` generated the three interfaces; pinned formatting
and caller compilation completed separately. [Execution record](execution.json)
retains original compiler/fixture failures and successful follow-ups; they are
not relabeled as successes. No automatic approval rejection occurred for these
new bounded commands. Every recorded Owner/group and own lock was absent after
termination. The submitted documentation commit follows the tested product source.

Frontend captured/nested lowering after adoption, public Local/HTTPS, Wasm/Native
execution, full profile closure and CI remain unverified by this common API unit.
B will connect the existing demand traversal to this owner-issued topology next.
The full WITH replacement, old DATA removal and P1/P2 completion remain separate
unfinished work. No Model/Native resource boundary or other owner's worktree was
edited, and no Heavy producer or campaign was started.
