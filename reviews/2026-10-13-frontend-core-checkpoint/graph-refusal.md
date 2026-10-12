# Graph row continuation and unresolved-producer controls

This unit follows the separate WITH/JOIN dispatch repair. Its only product hunk
is immediately after `after_graph_row_calls` in `graph_rows_program.mbt`.

The original selection at the adopted main still failed: `run-pv8UMx`, 33/40.
The isolated `run-KBtg8c` returned `UnsupportedGraph` for:

```aql
FROM g |> node_rows() |> union_graphs(with: g)
```

The row bridge has consumed the Graph and now yields a Relation. Closed Graph
and NONE-input heads cannot consume that Relation. The adopted refusal is an
authored Carrier violation (`InvalidQuery`), as the unchanged original union,
subtraction, Subgraph, Delta and classification tests already specify. Reject
that transition at the bridge, retaining ordinary VecA/TEA continuation dispatch
and the original peer scope. No Graph schema, identity, operation, evaluator,
Catalog rule, cap, wire reason or contract pin changes.

Three missing-Graph controls still expected the older unqualified
`UnknownRelation`. Current source resolution already issues the retained
`UnresolvedRelation` witness. Migrate those independent expectations to the exact
one-part, unquoted `g` path. No Source is invented, no label supplies a producer,
and retired annotations remain rejected. The original query strings are
unchanged; expected values are not obtained from product output.

Working-source evidence:

- `run-ICbeHF`: 39/39 Graph refusal and existing Carrier callers after the hunk.
- `run-UIgJ9w`: 49/49 including public-lowering and exact unresolved-input controls.

These retain the original seven failing case identities:
`graph_union_source_test:60`, `graph_subtraction_source_test:39`,
`graph_delta_source_test:111`, `graph_profile_test:2`,
`subgraph_source_test:190`, `graph_refusal_classification_test:11`, and
`source_frontend/lower_test:307`. The selected `compile_test:42` missing-Graph
caller is also migrated and must execute through the nonzero recipe separately.

Raw source and failed/successful command evidence remain in the workspace
`reviews/2026-10-13-b-core-checkpoint-evidence/`. No prior failure becomes a pass.
The parent unit closes 24 assigned failures; this unit targets eight additional
cases. All other original assigned failures remain unclosed.

Run `graph-prepared-checks.mjs` with the pinned toolchain: existing non-Heavy
guard, 60 seconds, TERM grace 5. New installed E2E scenarios: **0**. No full Core,
public producer/consumer, provider, Hosted CI or target execution is requested.
