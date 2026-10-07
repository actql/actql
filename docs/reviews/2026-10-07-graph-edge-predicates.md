# Anonymous MATCH edge predicates: frontend contract connection

## Selected existing contract

Baseline: `9845c40fbbbb514c12e8b68ac798892afdd81341`.
This change connects existing MATCH WHERE/property-map syntax to ordinary
`traverse.edge_where` and per-hop `hops[].edge_where`. The common
`traverse.closed-modes-and-filters` and
`traverse.hop-predicate-static-definition-scope` requirements in
`docs/spec/language.md` already define this behavior. This is a frontend
connection, not a new traversal algorithm or numeric/identity contract.

Only true predicates retain an edge; false and SQL NULL do not. The authored
static label selects candidate definitions. Each referenced property must
exist with compatible type in every candidate definition; empty runtime input
cannot supply missing-property evidence. Within a selected definition,
traversal uses its full declared property scope, rather than a label-specific
projection. Ordinary nullable-object property evaluation stays with the common
expression checker and runtime.

## Counterexample and repair

One node has three independently keyed R self-loops with weights 10, 20 and
NULL. The fixed WHERE `weight > 10` must retain only the weight-20 edge. For
bounds `{0,2}`, WALK produces depths `[0,1,2]`, TRAIL `[0,1]`, and ACYCLIC `[0]`.
Different per-hop predicates `weight > 10` then `weight IS NULL` produce one
two-hop path. Omitting those conditions would instead produce nine paths.

The baseline lowerer rejected every constrained edge with `UnsupportedGraph`.
Its parser additionally rejected a constrained quantified edge as
`GRAPH_PATTERN_UNSUPPORTED_SHAPE`. The independently handwritten complete
fixed and bounded Programs passed normal checking. With the valid input
fixture, the pre-fix focused run executed three tests: one passed, two failed.
Earlier drafts of the test lacked a GeneratedValues `as` binding or used an
incorrect machine endpoint field; those authoring failures are not product
counterexample evidence. The machine endpoint is `target`, while the surface
clause is DESTINATION KEY.

The repair shares existing node/property expression construction and schema
name projection with anonymous edges. It preserves the predicate tree,
parameter references, direction, static edge label and exact hop bounds.
The shared Graph checker determines presence/type compatibility. The
frontend does not issue presence, uniqueness or identity evidence.

Named edge bindings, unsupported endpoint/intermediate-node constraints,
invalid/open bounds and implicit element export retain their existing refusal
boundaries. A key excluded by NO PROPERTIES remains unavailable in predicates;
the former generic edge-predicate negative fixture now describes that specific
missing-property obligation.

## Independent acceptance and evidence

`scripts/fixtures/graph-edge-predicate-source-input.mjs` contains authored
source and ordinary JSON controls, rows and ordered column contracts. It is
included through the existing Graph predicate corpus in both normal packed
acceptance and its narrow selector. The unchanged public harness compares
Named Result rows and Result.describe columns, repeats reads/attach/same-request
submission, and checks admission and real source-I/O counters on refusals.
No Program is corrected after lowering, and no alternate executor or legacy
Graph route is introduced.

The new positive corpus covers fixed/per-hop constraints, property maps,
quoted names, SQL NULL, nullable object receivers, typed parameters, empty
results, static candidate selection, full definition property scope, and all
three bounded path modes. Refusals cover foreign/missing receivers, missing
members, scalar receivers, incompatible types, output aliases, named edge
bindings and static missing properties even for an empty candidate definition.

Focused JS verification (affected new tests plus node/keyed/bounded callers):
24/24 passed. Command:

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/query_program/graph_edge_predicate_test.mbt \
  src/query_program/graph_property_predicate_test.mbt \
  src/query_program/keyed_graph_program_wbtest.mbt \
  src/query_program/bounded_graph_modes_test.mbt \
  src/query_syntax/bounded_graph_modes_test.mbt
```

Pre-fix evidence: `/private/tmp/actql-b-edge-predicate-baseline.log`, focused
receipt `focused-test-uecuWi`, attempt `run-TX6sr1`. Post-fix focused evidence:
`/private/tmp/actql-b-edge-predicate-focused.log`, receipt
`focused-test-roZdN5`, attempt `run-oTF9VV` (under this worktree's `_build`).

Fresh normal five-package source acceptance passed at
`22e87b27292f6bb7ae2e6e7ee7a4e7d99d3d93c1`, after adopting main
`95ba84870c27da71dc8b143e56170847aa4b60b9`. Embedded Local and HTTPS each
completed 25 positive cases (16 new edge cases and 9 retained node cases) and
13 pre-admission refusals. The unchanged harness verified ordered rows,
Result.describe contracts, read/attach/resubmit identity, and no Run admission
or source I/O on refusals. This is local evidence, not hosted CI success.

Commands, using the pinned Node/MoonBit toolchain and existing bounded
`runLocalCheck` heavy-work exclusion (300s producer, 900s narrow consumer):

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-edge-predicate-22e87b272-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-edge-predicate-22e87b272-pack \
  node scripts/test-packed-public-query.mjs --graph-property-predicate-only
```

Producer manifest: `/private/tmp/actql-b-edge-predicate-22e87b272-pack/packed-client-packages.json`.
Consumer receipt: `../.codex-scratch/public-query-evidence-gYw0Au/summary.json`.
It records passed/complete and `artifactsRemoved: true`; the successful temporary
installation and Stores were reclaimed after evidence preservation. Logs:
`/private/tmp/actql-b-edge-predicate-22e87b272-pack.log` and
`/private/tmp/actql-b-edge-predicate-22e87b272-packed.log`. The producer checked
its exact clean build-input revision and all five tarball SHA-256 digests; the
consumer audited the actual external dependency graph. Untracked prior review
evidence outside build-input directories was retained, not used as package code.

At that integration SHA, the changed dependency/request-name Node checks passed
5/5 (receipt `focused-test-HNquMV`, attempt `run-yMYLGx`). Final source formatting
and this evidence update are later than the packed execution: do not rewrite
that run as execution at a later SHA. Hosted CI, other public corpora,
Wasm/native, full Core, proofs and performance remain unverified here.
