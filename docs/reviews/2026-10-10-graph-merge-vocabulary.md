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

The initial product commit had public execution pending. Complete corrected
execution evidence follows below; parser/lowering success alone is not execution
evidence. Wasm/native, full Core, complete packed campaigns
and submitted-HEAD CI have not been established locally. No merge or manual
CI rerun is requested.

## Initial public run and existing refusal-category correction

Normal clean five-package production at
`10384fdc2799821befd6f0176998762fb10efb9e` completed; independent digests
matched its manifest. Guard run-Me3DTk; original receipt
`/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-ycEQsx`.
The union Local consumer passed all 16 positives, including the four new
uppercase/quoted node/edge projections and independent JSON control, plus two
expected execution failures. It stopped on old graph-union-refuse-1 because
the fixture's default code list excluded ClientProgramImplementationLimit.
Later refusals, union HTTPS and the subtraction consumer were not reached.

This is the existing UnsupportedGraph projection: the unchanged composition
lowerer and exact union/subtraction Core refusal tests establish unsupported
empty/binary peer-list shapes, missing peers, extra arguments and composition
after loss of Graph scope. `client_check.mbt` maps UnsupportedGraph to
Limit("implementation_limit"), which the existing public diagnostic projects.
Three old union and five subtraction expectations now explicitly require that
category. No product error mapping, default allowlist, source, expected rows or
limits are changed. The original failed receipt/logs remain preserved, and its
private full installation was removed by the evidence wrapper.

After exact existing refusal-category corrections, the same targeted Node
command passed 8/8: guard run-aU1QNr; focused-test-7BSLST.

## Complete corrected public acceptance

Clean source/fixture SHA: `1c5777512065d31a0f2cb0909199542e5850d2b1`.
One normal five-package producer and independent digest check, followed by the
two existing narrow consumers sequentially under guard run-8m7enQ:
`node /private/tmp/actql-b-graph-merge-vocabulary-packed.mjs`.
Producer: `node scripts/packed-client-packages.mjs /private/tmp/actql-b-graph-merge-vocabulary-1c5777512-pack`.
Consumers: `node scripts/test-packed-public-query.mjs --graph-union-only` and
`node scripts/test-packed-public-query.mjs --graph-subtraction-only`, both with
ACTQL_PACKED_CLIENT_PACKAGES set to that directory. No installed runtime overlay,
test-side Program repair, old Graph fallback or alternative execution Owner.

Local and HTTPS each completed:

| Cohort | Positives | Pre-admission refusals | Expected execution failures |
|---|---:|---:|---:|
| Union | 16 | 14 | 2 |
| Subtraction | 17 | 13 | 2 |

All eight new source positives and eight new typed refusals completed, as did
existing JSON controls, nonassociative union-fold order, subtraction endpoint
closure, nullable/empty results and conflict behavior. Named Result values,
full Result.describe column contracts and declaration order, edge-key order,
stream completion, same-request replay and no additional acquisition remain
checked by the existing public consumer. Refusals preserve zero new Run
admission/Source I/O and submission lookup. Six old union and one old subtraction
refusals still use the unchanged default input-code checks; eight corrected old
implementation-limit cases and all eight new refusals require explicit codes.

Original complete receipts:
- Union: `/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-iqackh`.
- Subtraction: `/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-MzU9br`.

Both receipts are passed/complete, with clean exact-source binding, all ten
commands complete/exit 0, no evidence errors and artifactsRemoved=true. The
absence of both private installations was also checked. Original logs/receipts
and producer tarballs remain retained; the initial failed run is separate.
The five tarballs match the source manifest and independently recomputed SHA-256:

| Package | SHA-256 |
|---|---|
| client-wire | ca7aaf03f3f1d78aff24c42a4ebe94ae2136ce29ba3fdf8ed81478e359e3df60 |
| sdk | 64eca760cdce9f0da1ea53542ede457ec9f5c80603d9b13721077d90c7b91c1e |
| run-host-core | f556604d2d56a7bdd76865289c621a4f69ec766af78e03d942f81666b1acfb54 |
| local-node | 1b90dbf0278487e529a9af9743caf613e54b0048c0be3732d74d2f523f86682f |
| node | a77756e97078c7df0ea0a318e5ccd74bd7aee2891caa148da2688f9c3eb2d9eb |

A final evidence-only documentation commit does not relabel this clean SHA's
execution as verification of another submitted HEAD. Full Core, Wasm/native,
complete packed campaigns and exact submitted-HEAD required CI remain
unestablished. Keep Draft for review/required checks; final merge target is main
after #1184 lands. No merge or manual CI rerun.
