# Whole-row distinct registration comparison

This increment registers the existing `distinct: true` implementation. It does
not deliver a new product operation or retire any existing test. The completed
rename foundation revision and its common source hashes are recorded in
`reuse-baseline.json`; the normal audit verifies those hashes against Git and
current source. The historical take comparison remains separate.

## Marginal rules people add and review

| Addition | Meaning requiring review |
| --- | --- |
| `distinct.mjs` | Exact whole-row variant; admitted total input occurrence order; schema/order preservation; independent complete-row equality including NULL; first occurrence; argument registration |
| `distinct-acceptance.mjs` | Different complete rows with a shared first column; NULL-containing equal rows; interleaved duplicate order observable through take; empty input |
| Registration entries | Actual `DistinctRows` kernel route, descriptor and mutation registration |
| `distinct-mutations.mjs` | First-column-only comparison, reversed survivor order, and checked handoff-port defects; source sites and same-visible-defect shrink anchors |
| `regressions.json` | Three fixed defect reproductions, including their exact anchored rows/edge; these are additional regression work, not ordinary pairwise combination fixtures |
| `distinct.test.mjs` | Independent primitive contract/oracle checks and exact variant rejection |

The comparison is about these meaning rules, not merely which file contains
callbacks. The descriptor and predicates are small operation-specific rules;
no distinct-only generation/shrink/coordinator branch or common theorem is added.
The common coordinator does not receive a replacement lowering/evaluator.

The unchanged generator constructs every admitted existing-operation/distinct
pair and additional typed sequences. Deterministic completion finds a case with
an interleaved duplicate whose distinct survivor order is visible after take;
its concrete predicate is mandatory on every fixed run. A seed's incidental
pair presence cannot substitute for that obligation. People do not write one
ordinary fixture for each filter/select/sort/take/rename predecessor/successor.
Generated case counts are not converted into saved-test counts or hours.

## Actual reuse and new connection evidence

Existing Session/chain Lean models remain unchanged. The actual registered
selected binding-rows adapter and bounded Session are exercised for the
`DistinctRows` kernel, not inferred from a provider name. The normal observations
compare cumulative/delta work, cancellation, terminal/cleanup retry, exact child
input bindings, checked/kernel schemas, child output rows and final chain values.
Parent work includes attempted handoff charges.

The independent oracle compares complete row fields and retains their first
occurrence in admitted order. It uses no product comparison or lowering helper.
The same GeneratedSequence supplies the checked schema, selected kernel and
registered execution. Checked type/nullability, real route connection and
observed values remain distinct evidence. Empty input does not infer types from
runtime cells.

Mutations preserve the same operation, affected input occurrences or checked
producer/consumer edge. The partial-comparison defect must remove an anchored
output class; the survivor-order defect must invert the same two distinguishable
surviving payloads. Another mismatch with the same broad classification does
not qualify. JS exploration/shrinking and finite mutated/restored target replay
are recorded separately from fixed prior-regression replay.

## Obligations retained elsewhere

Whole-row distinct's algorithms, workspace/capacity boundaries, long-key cancel,
control-work and historical regressions remain in their original tests. Keyed
distinct, other value domains, retained Host execution, two consumers, Store,
physical reclamation and backend boundaries are not replaced by this numeric
serial profile. Child/runtime allocation bounds and the 256-byte allowance remain
unproved. There is no claim for arbitrary DAGs or delayed-stop callbacks.

No test deletion or CI speedup is claimed. Timings for fixed target runs,
exploration, shrink and mutated/restored target replay are in the actual reports.
The accepted result is a bounded registration/review-cost comparison under the
listed contracts, not implementation-wide formal refinement.
