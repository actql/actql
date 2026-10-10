# Traversal Relation output as a Pipe JOIN input

Date: 2026-10-10. This unit depends on the existing Graph rows/JOIN connection
in #1221 (`17ec72d42932c7d49e1726a5f91c88a9575bf531`). Latest main
`66cebf93c` was normally merged before implementation; integration base:
`4d1145b7a9e5cd2807a46736d5403cefd8fa65cf`.

## Existing contract and counterexample

The existing common traversal checker and execution owner return a Relation
for both explicit `emit: 'nodes'` and `emit: 'paths'`. Their schemas and
multiplicity differ. The existing public source lowerer already preserves
these arguments and dispatches both forms to that owner. However, the Pipe
JOIN prefix classifier recognized only node_rows/edge_rows as Relation
outputs; it still refused a valid traversal prefix.

```aql
DATA n = SELECT 1 AS node_key;
DATA g = PROPERTY GRAPH (
  NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES)
);
DATA seeds = FROM g |> node_rows() |> SELECT id AS element;
DATA r = SELECT 0 AS depth, 10 AS tag
  UNION ALL SELECT 0 AS depth, 20 AS tag;
FROM g
  |> traverse(start: {from: seeds, id: 'element'}, direction: 'out',
              min_hops: 0, max_hops: 1, path_mode: 'trail',
              emit: 'nodes', max_output_rows: 10)
  |> AS v
  |> JOIN r AS rr ON v.depth = rr.depth MAX_OUTPUT_ROWS 10
  |> SELECT v.depth AS depth, rr.tag AS tag
```

The complete independently authored common JSON control passes the ordinary
checker before the source is attempted. The text then failed in syntax:
`_build/local-checks/attempts/run-Fsldm9`,
`_build/focused-evidence/focused-test-xuGuHN`, 0/1. No public Run failure is
claimed by that pre-fix test.

## Repair and obligations

The only product change adds traversal to the existing Relation JOIN prefix
classifier in `query_syntax/pipe_join_input.mbt`. It uses #1221's existing
recursive producer binding and the existing traversal/JOIN lowerers. It does
not interpret traversal predicates, choose a backend, infer identity, declare
query-key uniqueness, materialize a producer, change ceilings or add an Owner.
The existing lowerer/checker still validates the authored emission, selector,
path mode, bounds and correct output fields. Graph-returning operations alone
remain outside this Relation path. No common contract or compilation pin changes.

The independent public fixture uses one node with two differently keyed
self-loops, an explicit two-hop TRAIL traversal and two matching right rows:

- Node emission has one endpoint/minimum depth, so JOIN produces two rows.
- Path emission retains the two ordered distinct-edge alternatives, so JOIN
  produces four rows. Treating the start/query key as unique would lose rows.
- JSON and text controls preserve explicit traversal max_output_rows=10 and
  JOIN MAX_OUTPUT_ROWS=10; neither is silently replaced with a default.
- Projected output, WHERE/LIMIT, empty selector and changed public column
  order exercise ordinary Relation continuation and Result.describe contracts.
- Node-only/path-only field references, projected-away columns, old Graph
  ranges, invalid path mode and zero JOIN ceiling must refuse before Run
  admission/Source I/O. A positive JOIN ceiling of one is a separate execution
  failure: two actual matches cannot become a partial successful Result.
- Same-request submission/attachment and Result rereads use the existing
  shared public acceptance checks and must not execute again.

`scripts/fixtures/traversal-join-source-input.mjs` contains complete authored
text, independent JSON Programs and handwritten ordered rows/column contracts.
No compiler output is used to generate expectations, and no lowered Program
is patched by the tests. The cohort joins ordinary packed acceptance and has
the bounded `--traversal-join-only` selection.

## Focused verification

Repository-pinned Node 22.22.0 and MoonBit 0.10.12+1634b282e, JS backend:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- --target js \
  src/query_program/traversal_join_input_test.mbt \
  src/query_program/traversal_nodes_test.mbt \
  src/query_program/traversal_paths_test.mbt \
  src/query_program/graph_rows_join_input_test.mbt \
  src/query_program/pipe_join_input_test.mbt \
  src/query_syntax/pipe_join_input_test.mbt
node scripts/local-checks.mjs test node -- \
  scripts/traversal-join-source-input.test.mjs \
  scripts/graph-rows-join-source-input.test.mjs \
  scripts/compilation-manifests.test.mjs
```

Post-fix JS: 19/19 (`run-iFETM1`, `focused-test-78dFRN`). After adding the
separate path projection and exact UnknownColumn rejection, the changed test
file passed 2/2 (`run-rQo9NH`, `focused-test-yISYt1`) without repeating callers.
Node: 10/10 (`run-TCyLqr`, `focused-test-GmUBLN`). Read-only compilation
manifests and git diff --check passed. Formatting was retained only on the
changed/new files; formatter-only modifications to unrelated files were
checked and restored to the integration base before committing.

At this document's commit, clean five-package production and packed Local/HTTPS
execution have not yet run. Their exact revision, digests and original receipts
will be added to the PR after execution. Focused tests are not CI, full Core,
Wasm/Native, all packed cohorts or a completed Frontend migration claim.
