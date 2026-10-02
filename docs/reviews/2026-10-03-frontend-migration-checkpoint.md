# Frontend migration: independent source checkpoint

This ledger describes B's independent implementation at
`5221799a271e2cb838d1806ea4db9d38b7d43135`, based on main
`0fd6332757176b88e8c4071e4a2cd0be3d6254e3`. It separates source work from
public execution evidence. It does not declare the new Frontend migration
complete or adopt C's unfinished implementation.

## Implemented versus execution evidence

| Surface or boundary | Implemented checkpoint | Acceptance still required |
|---|---|---|
| Retired AQL/PROGRAM/STAGE and STEP/OP public entry | Typed refusal; no compatibility parser or formatter | Preserve existing SQL/Pipe and machine-input regressions when integrating the unified owner |
| JSON/YAML Program | Existing machine admission remains available | Machine execution is not evidence that replacement text executes |
| Relation DATA and explicit RESULT | Shared script parsing and lowering; public preparation retains named roots | Fresh packed Local/HTTP at the adopted integration SHA; no claim from preparation-only tests |
| Pure PROPERTY GRAPH | Bounded parsing and independently authored Program construction | Common unified constructor/checker, public execution, descriptions and snapshot roundtrip |
| Named SGA calls | Nineteen adopted names and argument roles parsed by the shared query parser; DATA aliases and normalize-before-MATCH lower to retained producers | Adapted common Carrier/schema contracts for remaining calls; all promised examples through Named Results |
| Public Graph source | Typed `QueryLowering(UnsupportedGraph)` before a Program is returned | Replace the dependency refusal after the formal unified owner is adopted; verify actual Run/admission and provider counters |
| Source INFER KEEP/AS | Frontend lowering and independent fixture work remain separate from common execution | Formal owner fix and smallest source-input Local/HTTP execution first, followed by NULL, keys and replay |
| Other target Effect, VecA and TEA surfaces | Adopted targets and machine capability are distinct from public syntax support | Feature-specific source, checker and real execution evidence; no bulk completion claim |

The public Graph refusal includes installed Graph aliases and pure constructors.
No retired property-label route, simple-Graph conversion or old consumer fallback
is enabled. Syntax-only normalization must not be reported as common Graph
checker or kernel acceptance.

## Evidence and handoff boundaries

The [unified-source separation record](2026-10-03-property-graph-unified-source.md)
lists the constructor, checker, Graph identity, MATCH/TRAIL and public snapshot
interfaces required from C. Its retained authored fixtures specify independent
schema, rows, parallel edges, composite keys, static labels and NULL exclusions.
The [named-call checkpoint](2026-10-02-sga-query-calls.md) records B's parser,
lowering and canonical identity tests; its provisional-dependency results are
explicitly historical.

`src/source_frontend/unified_dependency_test.mbt` verifies the current typed
refusal and Relation DATA/RESULT preparation. It does not observe Host counters,
deliver a Result or roundtrip a snapshot. Neither these tests nor a green CI run
can substitute for the missing Graph or source-INFER execution evidence.

C's public `125a186ae9396fbfc7865641922e8e8a4ffc87d9` is not adopted as a
unified owner. Integration requires a pushed complete SHA and the corresponding
unified/snapshot validation. No unpushed checkpoint is a release dependency.
When that handoff arrives, use fresh normally packed Local/HTTP installations,
record both owners' SHAs and package digests, and compare authored expectations
through Named Results. Keep old successful runs classified by their old inputs
and dependency SHAs.

The [architecture and migration obligations](../design/frontend-language-migration.md)
remain broader than this implementation checkpoint. Existing JSON/YAML inputs
are retained capabilities, not completed replacements for withdrawn text paths.
