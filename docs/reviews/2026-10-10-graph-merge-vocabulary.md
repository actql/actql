# Typed Graph merge vocabulary at the public text boundary

Base: #1184 `d9b30fc85968428cb4a54e02e480960795802d85`, on main
`040eed2b1a11a3d1f7bae81b68d956d1017fac05`. This small stacked repair uses
the same parser role table; #1184 must reach main before retargeting this PR.
It does not depend on the separate QUALIFY execution-capacity handoff.

## Existing contract and counterexamples

Named logical SGA calls in `docs/spec/query-text.md` already require
case-insensitive operation vocabulary, with argument roles selected from the
existing operation contract. `docs/spec/language.md` defines GraphMerge as a
closed container with node_properties and edge_properties. Their children are
authored property-name selectors; their String values are the existing exact
GraphFieldStrategy enumeration. They are not further vocabulary objects.
The common Graph checker folds property-name identity, rejects duplicate
selectors under that identity, and checks the unchanged strategy values.

The parser folded root arguments and selectors, but retained authored merge
container keys. Before repair:

```aql
DATA n = SELECT 1 AS node_key, 7 AS p;
DATA g = PROPERTY GRAPH (
  NODE TABLES (n AS N KEY (node_key) LABEL Person PROPERTIES (p))
);
FROM g
  |> UNION_GRAPHS(WITH: [g, g],
                   MERGE: {NODE_PROPERTIES: {p: 'number_sum'}})
  |> node_rows() |> SELECT p, node_key
```

The independent complete expected Program already checks successfully, using
union_graphs.with with two occurrences of the same Graph and
merge.node_properties.p = number_sum. Source compilation differs only in the
uppercase unknown machine field NODE_PROPERTIES. The quoted subtraction
counterexample has the same discrepancy. The parser also wrongly accepts
node_properties plus NODE_PROPERTIES, or edge_properties plus a mixed-case
backtick spelling, in one merge container.

## Minimal repair and independent obligations

Reuse the existing parser's role-sensitive folding at the exact path merge
for union_graphs and subtract_graphs. Preserve property-map names, producer
references, string strategy values, peer occurrence/order and all other data.
No checker, Owner, Graph identity, defaults, ceiling, grammar production or
machine contract changes are introduced.

- Hand-authored parser expectations cover uppercase/backtick merge fields,
  exact duplicate Syntax reason, distinct Score/score data keys, unchanged
  uppercase strategy String, decomposed Unicode and CR.
- Source compilation matches the existing independently authored complete
  union and subtraction Programs, then passes the ordinary common checker.
- Public controls and source expect p=21 and keyed edge weights 6/15 for
  three union occurrences; subtraction's explicit policies retain p=14 and
  edge weights 4/10. Default subtraction would remove these elements, so
  ignoring the merge arguments cannot pass these expectations.
- Quoted merge fields with authored P/W selectors use the existing common
  case-insensitive Graph-name identity; the parser does not rewrite them.
- Mixed-case duplicate container fields, unchanged NUMBER_SUM, a common
  property-map collision, and an unknown merge field require typed rejection
  before Run admission/Source I/O. No default error allowlist is relaxed.
- The additions enter existing normal and narrow public union/subtraction
  consumers. Named Result rows, exact columns/types/nullability, ordered edge
  keys, stream completion, rereading and same-request replay remain checked.

## Focused evidence

Pinned Node 22.22.0 and MoonBit 0.10.12+1634b282e; bounded/nonzero wrappers.
Before repair: 1/5, with four failures for retained uppercase container keys,
missed folded duplicate, and union/subtraction complete Program differences.
Guard run-oKOuYf; focused-test-D04oNb. Value-preservation contrast already passed.
Command: `node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_syntax/graph_merge_vocabulary_test.mbt src/query_program/graph_merge_vocabulary_test.mbt`.

After repair, affected parser and callers: 26/26. Guard run-ocpASi;
focused-test-S61Qvd. Command:
`node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_syntax/graph_merge_vocabulary_test.mbt src/query_syntax/sga_call_test.mbt src/query_syntax/traverse_hop_vocabulary_test.mbt src/query_program/graph_merge_vocabulary_test.mbt src/query_program/graph_union_source_test.mbt src/query_program/graph_subtraction_source_test.mbt`.
Evidence directories are `_build/local-checks/attempts` and
`_build/focused-evidence` in this checkout.

Targeted Node fixture/normal-corpus registration checks: 7/7. Guard run-j1lJAz;
focused-test-nSWyUD. Command:
`node scripts/local-checks.mjs test node -- scripts/graph-merge-vocabulary.test.mjs scripts/graph-union-source-input.test.mjs scripts/graph-subtraction-source-input.test.mjs`.
Changed-file moonfmt and git diff --check passed.

Public execution is pending at this commit. Parser/lowering success is not
public execution evidence. Wasm/native, full Core, complete packed campaigns
and submitted-HEAD CI have not been established locally. No merge or manual
CI rerun is requested.
