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
repair are unchanged.

The corrected clean source is `5178858fd6d20e0ada222f648bd5a87d18a366bb`.
Normal five-package production, independent digest verification and the
existing node/path consumer ran under guard `run-pIT1GT`, using
`node /private/tmp/actql-b-traverse-hop-vocabulary-packed.mjs`. Producer:
`node scripts/packed-client-packages.mjs /private/tmp/actql-b-traverse-hop-vocabulary-5178858fd-pack`.
Consumer: `node scripts/test-packed-public-query.mjs --graph-traverse-paths-only`,
with ACTQL_PACKED_CLIENT_PACKAGES pointing to that pack directory.
Local and HTTPS each completed all 20 positives and 25 refusals. Every new
normal/refusal case, including the independent JSON control, completed. The
sixteen old refusals without explicit codes still use the unchanged ordinary
input-error checks; the four emission contrasts and five new refusals require
their explicit distinct codes. All refusals check zero new Run admission and
Source I/O, retained submission lookup and the existing access contract.

Original complete receipt:
`/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-yy1FS4`.
Its source is clean and matches the manifest, all ten commands exit 0, output
is complete, and evidenceErrors is empty. SHA-256 digests were independently
recomputed from all five producer tarballs and compared to that original
receipt. Temporary full installations were removed after evidence preservation;
artifact absence was checked for both the successful and initial failed run.

| Package | SHA-256 |
|---|---|
| client-wire | `ca7aaf03f3f1d78aff24c42a4ebe94ae2136ce29ba3fdf8ed81478e359e3df60` |
| sdk | `64eca760cdce9f0da1ea53542ede457ec9f5c80603d9b13721077d90c7b91c1e` |
| run-host-core | `f556604d2d56a7bdd76865289c621a4f69ec766af78e03d942f81666b1acfb54` |
| local-node | `db411676120dd62dbf6d1a397c82e9b791fa4ccef9c2f26bcbb3050a1aaade07` |
| node | `a77756e97078c7df0ea0a318e5ccd74bd7aee2891caa148da2688f9c3eb2d9eb` |

Final evidence-only changes do not move the packed execution claim to a later
submitted SHA. Submitted-HEAD CI, Wasm/native, full Core and the complete packed
campaign have not been run locally. Final target main; no unmerged dependency,
merge operation or manual CI rerun is requested.
