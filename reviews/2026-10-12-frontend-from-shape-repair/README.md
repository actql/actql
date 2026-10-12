# FROM postfix and Graph static refusal fixture repair

Original full-Core source: `d62f4de55f98badeb37af933f6fdb0e5dbfeae22`.
Adopted main: `1442806de57d028e29e650814278b58985e8ac02`.
Tested fixture source: `1b7bea02b499a0bdb67cd13b2fc7f13a22736eea`.
Submitted HEAD adds only this evidence documentation; no product code changed.

## Four original failures

- FROM PIVOT and FROM UNPIVOT complete independent Programs previously required
  one producer Stage plus a consumer Stage. The adopted WITH binding contract
  adds no Stage boundary. Both original full Programs remain byte-equivalent
  structured JSON in `original-independent-programs.json` and as checked
  staged controls in their tests. Current complete expectations independently
  concatenate the same original Values, postfix, projection and sort bodies
  in one main pipeline. Private names are counted from installed Context
  inputs under the existing reserved-length allocator: PIVOT has one installed
  input (cte_1/seed_2), UNPIVOT two (cte_2/seed_3).
- Empty derived FROM PIVOT keeps WHERE FALSE, the exact global count pivot,
  identity projection A, ordered exported schema A and ordinary common check.
  Its old generated-stage name was not part of that value/type requirement.
- Any-direction Graph hop checking sees the intersection of endpoint property
  definitions. Source has no score, Target does. The exact existing common
  `GraphMatch(UnknownField("score"))` refusal now occurs at WITH static admission
  before a complete invalid Program can be returned. The original source is
  unchanged, the endpoint-specific UnsupportedGraph control is retained, and
  no field/presence evidence is fabricated.

No data, Source declarations, nullable contracts, duplicate policy, order,
keys, count semantics, ceilings, checker, runtime or pins changed. Expected
Programs were not generated from product output. The two-stage controls are
kept as valid machine Programs, not claimed as current lowering.

## Actual bounded evidence

Tracked `prepared-checks.mjs` uses existing guard and nonzero focused runner:
60 seconds / grace 5 / non-Heavy, repository pinned toolchains.

- `run-nGO3fY`, baseline `b25346bdb`: JS 13/17; all four original failures recur.
- `run-17TtI5`, fixture `4917e81ca`: JS 33/34. This unit's initial independent
  PIVOT oracle incorrectly counted two installed inputs. It was corrected from
  Context plus allocator source inspection; the failed receipt is retained.
- `run-S3cYTv`, exact `1b7bea02b499a0bdb67cd13b2fc7f13a22736eea`:
  **JS 34/34**, selecting from_pivot_test, from_unpivot_test,
  from_pivot_identity_projection_test, graph_any_direction_test,
  graph_property_predicate_test and pipe_pivot_test in src/query_program.
- `run-3JeWQa`, same source: read-only formatter passed for the four changed
  test files. Diff check passed. `run-iU02Nx` was write formatter only.

The final guards completed exit 0, released their own locks, and original raw
logs/receipts were copied byte-identically with SHA-256 checks to
`/Users/t14i/workspace/20260822/reviews/2026-10-12-b-frontend-core-repair-evidence`.
Hash-only manifest is `evidence-hashes.json`; original _build evidence remains.

This adds bounded repair evidence for four original failures: 51/55 total
across the submitted repair units. The remaining Source/Catalog and captured
Order four cases stay unresolved, with their positive intent and original
failures retained. No public Local/HTTPS, packed, Native/Wasm runtime, full-Core
or Hosted CI was run. There is no unmerged product dependency; target is main.
