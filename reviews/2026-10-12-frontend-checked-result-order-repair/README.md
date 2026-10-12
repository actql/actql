# Captured Result order: shared strict and check-only preparation

## Problem and repair

The independently authored [Program](../2026-10-12-frontend-imported-order-diagnostic/independent-program.json)
previously succeeded with `stage_results.prepare_local_program` and failed with
`check_local_program` at `stages[1].steps[3]`, `PipelineOrder(UnresolvedOrder)`.
The [original diagnostic](../2026-10-12-frontend-imported-order-diagnostic/README.md)
and its fixed-SHA evidence remain unchanged. Its negative comparison is history,
not the repaired expectation.

Strict preparation resolves Result publication order before importing the
projected producer. Check-only preparation previously retained only the producer's
logical order, losing the conditional CandidateKey/ProjectedFields publication
plan. This prevented the original captured JOIN/CTE consumers from resolving order.

The repair reuses the existing publication policy in both paths:

- `publication_order_policy.resolve` retains either the existing decision or its
  exact pending cursor and charged work/text. Existing `decide` remains strict.
- `pipeline_typing.prepare_produced_publication` retains the original pipeline,
  target, projection, key, inherited order and conditional publication. Existing
  `publish_produced_input` requires a resolved plan and still rejects pending order.
- `relation_results.prepare_checked_inputs` stores that same preparation. Its
  accessors expose the original producer and conditional/pending order without
  creating a Result port, runtime handle or completion certificate.
- The existing `stage_results/local_program.mbt` branch calls this shared API;
  its strict `resolve_all_orders` / `prepare_ports` path is unchanged.

This does not waive order required by an operation, catch and ignore a refusal,
manufacture source order, change capacity limits, or add an evaluator/owner. Wire,
Owned schemas, CIDs, publication permissions and runtime semantics are unchanged.
Model, Store, retention and resource-owner files are outside this change.

## Separate scoped Source reference defect

Once order was repaired, the original CTE-shadow positive assertion exposed a
second defect: `unshared_script_sources` counted a JOIN-right CTE named `records`
as another raw installed Source reference. That retained a `true` acquisition
predicate even though only one consumer referred to the raw Source.

The visitor now resolves binding names in sequential WITH scope before counting
raw references. A binding body sees preceding bindings, not itself; the final
query and set operands see the completed scope. Binding names use existing
`same_name`, including quoted case-insensitive names; published Source paths
retain their separate matching rule. The original predicate and assertions are
unchanged. Added quoted-shadow and self-binding controls preserve this distinction.
Installed GeneratedValues memoization and its physical-input identity are unchanged.

For independent input ids 1 and 2, the two shared-raw JOIN examples require ids
1 and 2. In the shadowed example both operands refer to `chosen`, so its id=1
filter applies to both. These are specification-derived explanations; no runtime
rows were executed in this unit.

## Fixed-source verification

Adopted main: `e99a6c41d8c0ce02e0cb23dbd5d854682078a7a6`, normal merge.
Submitted #1634 and #1638 ancestry is retained; both parents are already in that
main. Their author branches were not changed.

- Clean `ad2d2a282ff5c8f72e92465e5c9066da17b6d14d`, tree
  `cac68c424a8c91d437146c9c78435d590e9add01`: **JS 29/29**,
  run-dPFRC3 / focused-test-sDZqVx, complete exit 0.
  The same Program's strict/check-only success, CandidateKey/projection agreement,
  ProjectedFields/Inherited ownership, pending-object cursor, exact bounded
  accounting, original three refusals, original CTE positives and Catalog-enabled
  Pipe Source positive were executed through their existing checker entry points.
- Clean `c46c71172ca974266bf955aef53a04362897c49f`: affected six-package
  consuming compile on JS (run-zI10C5), Wasm (run-MtJn2j), Native (run-lsEQGv),
  all complete exit 0. Production and generated interfaces are byte-identical
  at the later ad2 source; subsequent changes only strengthen test comparisons.
- ad2 read-only changed-file format run-RArbdh and pinned `moon info` output
  freshness run-PtF1bd: complete exit 0, no tracked changes. `git diff --check`
  succeeded. Interfaces were generated, not edited by hand.
- Every check used the existing nonHeavy guard with 60 seconds / grace 5.
  Final Owner PIDs 91244, 91467, 91898, 92671, 93664 and 95337 were explicitly
  observed absent; all corresponding terminal receipts retain lock release.

Reproduction uses [prepared-checks.mjs](prepared-checks.mjs), with the repository's
pinned Node/MoonBit PATH and MOON_HOME. The exact file selection and commands are
in retained command receipts:

```sh
node reviews/2026-10-12-frontend-checked-result-order-repair/prepared-checks.mjs \
  src/publication_order_policy/plan_test.mbt \
  src/pipeline_typing/result_publication_test.mbt \
  src/relation_results/produced_order_test.mbt \
  src/stage_results/checked_topology_test.mbt \
  src/stage_results/prefix_topology_test.mbt \
  src/stage_results/local_program_test.mbt \
  src/query_program/checked_import_order_diagnostic_test.mbt \
  src/query_program/cte_capture_predicate_test.mbt \
  src/query_program/with_binding_static_order_gap_test.mbt \
  src/source_frontend/pipe_join_input_test.mbt
node reviews/2026-10-12-frontend-checked-result-order-repair/prepared-checks.mjs \
  --compile wasm src/publication_order_policy src/pipeline_typing \
  src/relation_results src/stage_results src/query_program src/source_frontend
```

The second command's `js` and `native` variants select the same consumers.

## Preserved failures and scope limits

- 5c607: run-1ucZSD / focused-test-PA1dOi **10/11**, original CTE-shadow
  predicate assertion failed after the order rejection was removed.
- 2402: run-T0OHR0 / focused-test-jrzcEY failed compiling a new test's missing
  target type annotation; no runtime tests executed. It was corrected explicitly.
- abb407: run-aTo8gn **11/11**, and 5a0bdb: run-3GMGOI **29/29**, remain
  evidence for those exact sources rather than the final submitted HEAD.

[Hash-only evidence inventory](evidence-hashes.json) records originals and
byte-identical retained copies under workspace
`reviews/2026-10-12-b-frontend-core-repair-evidence/checked-result-order` outside
Git. Raw logs, original diagnostic failures and all independent Program fixtures
remain retained. A later documentation-only submission commit does not replace
the exact tested source identities above.

The remaining three failures in B's original 55-case diagnosis are repaired by
these bounded checks. Earlier 52-case repair evidence remains at its own fixed
sources; this is not a fresh execution of all 55, all Core, or all Frontend.
Public Host/packed Local/HTTPS, Provider calls, Native/Wasm runtime, full package
acceptance and Hosted CI were not run. No merge or CI rerun was requested.
