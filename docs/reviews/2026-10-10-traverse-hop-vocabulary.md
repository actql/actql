# Traverse hop vocabulary at the public text boundary

Base: main `040eed2b1a11a3d1f7bae81b68d956d1017fac05`. This is independent of
the SELECT/Pipe/QUALIFY private-window branches and their capacity handoff.

## Existing contract and reproduced gap

`docs/spec/query-text.md`, Named logical SGA calls, already requires
case-insensitive operation/selector vocabulary while preserving object-valued
data. `docs/spec/language.md`, traverse.closed-modes-and-filters, defines
`hops` as an ordered typed list whose entries have direction, edge_types,
edge_where and node_where. Those names are operation arguments, not property
data or producer names. Enum String values and nested expression/value objects
retain their existing separate contracts.

The parser folded root fields and start-selector fields, but not hop fields.
Consequently this valid spelling lowered uppercase keys into the ordinary
Program instead of the checked hop vocabulary:

```aql
DATA n = SELECT 1 AS node_key;
DATA g = PROPERTY GRAPH (
  NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES)
);
DATA seeds = FROM g |> node_rows() |> SELECT id AS element;
FROM g
  |> TRAVERSE(START: {FROM: seeds, ID: 'element'},
              HOPS: [{DIRECTION: 'out', EDGE_TYPES: []}],
              PATH_MODE: 'walk', EMIT: 'nodes', MAX_OUTPUT_ROWS: 10)
  |> SELECT start_id, node_id, depth
```

The independently authored Program uses the same constructor/producer/selector,
`hops: [{direction: 'out', edge_types: []}]`, explicit walk/nodes, and exact
max_output_rows=10. It passes the normal checker. Source lowering differed
only in authored uppercase hop keys. The parser also accepted direction plus
DIRECTION in one hop instead of detecting the folded duplicate.

## Minimal repair and independent obligations

`src/query_syntax/sga_call.mbt` now applies its existing vocabulary folding
rule at traverse.hops as well as traverse.start. No new resolver, Owner,
defaults, execution path, grammar production or machine contract is introduced.
Nested edge/node predicates and literal objects are outside that folding
boundary. Lowering still emits every argument for the ordinary common checker.

- Parser contrast compares uppercase and lowercase hop vocabulary while
  preserving a literal object with distinct Direction/direction keys,
  decomposed Unicode and CR. Mixed-case quoted hop names follow the same rule.
- Duplicate direction, edge-type and node-predicate fields reject with exact
  `Syntax("Duplicate SGA argument")` after folding.
- The complete hand-authored Program, including true node/edge predicates,
  explicit empty label filter and output guard, matches lowercase, uppercase
  and quoted source and passes the common checker.
- Public JSON control and text expect two distinct TRAIL paths through
  parallel self-loops with keys 10/11. Both path orders retain their full
  identities; comparison is multiplicity-aware without inventing SQL ORDER.
- Node emission returns one endpoint with minimum eligible depth 2, rather
  than two rows or an ineligible zero-hop depth. Empty edge-types and a false
  second-hop predicate independently yield empty typed Results.
- Refusals retain mixed-mode and unknown-field checks. String value 'OUT'
  is not changed into 'out'. The five new public refusals require
  ClientProgramInvalidInput before Run admission or Source I/O.
- New cases enter the existing normal and narrow traversal consumer. It
  checks Named Result rows, full Result.describe contracts/column order,
  stream completion and same-request replay without reacquisition.

## Focused evidence

Pinned Node 22.22.0 and MoonBit 0.10.12+1634b282e, using existing bounded,
nonzero-test wrappers. Guards are under `_build/local-checks/attempts`; focused
records under `_build/focused-evidence` in this checkout.

- Before repair: 0/3, `run-u4NUhw` / `focused-test-0jSRsA`: parser argument
  mismatch, missed duplicate, and complete source-vs-Program mismatch.
- Initial repair plus callers: 20/20, `run-AXVjda` / `focused-test-c28QBz`.
- Final strengthened JS (predicates and quoted spelling): 20/20,
  `run-EX1H79` / `focused-test-RGRZBn`.
  Command: `node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_syntax/traverse_hop_vocabulary_test.mbt src/query_syntax/sga_call_test.mbt src/query_program/traverse_hop_vocabulary_test.mbt src/query_program/traversal_nodes_test.mbt src/query_program/traversal_paths_test.mbt`.
- Node fixture checks: 4/4, `run-yjYG0e` / `focused-test-xaDMw5` after fixing each new public refusal to its exact input-error code. The preceding fixture-only run also passed 4/4 (`run-wTjF8v` / `focused-test-WI1OjC`).
  Command: `node scripts/local-checks.mjs test node -- scripts/graph-traverse-hop-vocabulary.test.mjs`.
- Final Node after exact existing emission-category corrections: 5/5, `run-p8Zgji` / `focused-test-VFSYdg`, with the same command.
- Changed-file moonfmt and git diff --check passed.

## Public execution and remaining verification

The existing node/path narrow cohort has 20 positives and 25 refusals after
these six positive/five refusal additions. The first clean normal five-package run at
`9390d276ef6e226ae87698bcab33d987129dcf32` passed all 20 Local positives,
including the six new cases. It stopped during old refusals at
`graph-traverse-unknown-emission`: that fixture relied on a default input-code
allowlist excluding the existing ClientProgramImplementationLimit. The
existing `lower_script_traversal_rows` guard and exact
`traversal_paths_test.mbt` assertions establish UnsupportedGraph for missing,
unknown or parameter-valued emission. Four existing node/path fixtures now
explicitly require that established public code; neither the product refusal
nor the general allowlist was changed. Original failed receipt:
`/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-7ItJNs`,
guard `run-9FRUvc`. Remaining old refusals, new refusals and HTTPS were not
reached by that run. Source, expected rows, input limits and the product
repair are unchanged. A clean pack with the corrected diagnostic fixtures is
pending; lowering/checker success is not execution
success. Submitted-HEAD CI, Wasm/native, full Core and the complete packed
campaign have not been run locally. Final target main; no unmerged dependency,
merge operation or manual CI rerun is requested.
