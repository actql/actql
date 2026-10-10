# Graph row prefixes as ordinary JOIN inputs

Date: 2026-10-10. Base: `584b3a6144d4a8053ca4a541ef042a6e17c674e9`.

## Counterexample and existing contract

The common checker accepts an independently authored Values → Graph →
`node_rows` → `cross_join` Program with output `{value: 7, tag: 2}`.
The equivalent complete public source was rejected by the parser:

```aql
DATA n = SELECT 1 AS node_key, 7 AS p;
DATA r = SELECT 2 AS tag;
DATA g = PROPERTY GRAPH (
  NODE TABLES (n AS N KEY (node_key) LABEL Person PROPERTIES (p))
);
FROM g |> node_rows() |> AS l
  |> CROSS JOIN r AS rr MAX_OUTPUT_ROWS 10
  |> SELECT l.p AS value, rr.tag AS tag
```

The existing Graph rows contract returns a Relation. The existing Pipe JOIN
composition binds a preceding Relation query into a synthetic CTE. The parser
incorrectly excluded all Graph calls, including the row-producing Bridge.
After connecting that prefix, recursive script lowering also needed the
existing Graph producer bindings to resolve the generated CTE body.

Before the fix, the independent common JSON control passed and the source
failed in syntax: `_build/local-checks/attempts/run-iBFiQT` and
`_build/focused-evidence/focused-test-IF0LIO`. An intermediate parser-only
connection reached the separate lowering failure (`run-igwgdD`,
`focused-test-sXPxHy`). Neither observation is public Host execution evidence.

## Change boundaries

- `query_syntax/pipe_join_input.mbt` recognizes `node_rows` and `edge_rows`
  as Relation-producing prefixes. Their output begins a fresh Relation range
  scope. A Graph-returning call alone remains unsupported as a JOIN input;
  a subsequent `AS` cannot turn it into a Relation.
- `query_program/query_script_program.mbt` passes existing Graph bindings
  through recursive Relation/CTE lowering and dispatches row-producing bodies
  to the existing Graph rows lowerer. A CTE that shadows a Graph removes that
  Graph binding from the recursive scope.
- `query_program/query_cte_scope.mbt` recognizes an existing Graph rows source
  using the same resolver, without inventing a Relation schema for raw Graphs.
- `query_program/query_script_set.mbt` forwards the same bindings when
  traversing existing set operands. Set semantics are unchanged.

JOIN selection, explicit ceilings, Graph identity/property evidence, carrier
ownership and execution remain responsibilities of the existing common
checker/planner/Host. No Graph execution, acquisition, snapshot, Model or
Effect Owner is added or modified. Grammar and compilation pins are unchanged.

## Independent acceptance

`scripts/fixtures/graph-rows-join-source-input.mjs` contains complete authored
text and independent JSON controls. Expected rows and ordered column contracts
are handwritten, not generated from the compiler or execution output.

The selected cohort covers node rows, projected prefixes, an authored CTE,
WHERE/LIMIT, empty input, parallel keyed edges and JOIN multiplicity. Two
controls share one captured Source and require exactly one acquisition,
including repeated submission/attachment and Result reads. Nullable input
properties retain their declared nullability. Removed columns, old ranges,
shadowed Graphs, a Graph-returning JOIN input and an invalid zero ceiling are
preparation refusals. A positive explicit ceiling smaller than the actual JOIN
output is a separate failure case; it cannot publish partial successful rows.

Fixtures are included in the ordinary packed cohort as well as the bounded
`--graph-rows-join-only` selection. No test repairs a lowered Program.

## Verification at this commit

Using the repository-pinned Node and MoonBit toolchain:

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/query_program/graph_rows_join_input_test.mbt \
  src/query_program/pipe_join_input_test.mbt \
  src/query_program/graph_rows_test.mbt \
  src/query_program/set_array_scope_test.mbt \
  src/query_program/data_join_test.mbt \
  src/query_program/data_cte_test.mbt
node scripts/local-checks.mjs test node -- \
  scripts/graph-rows-join-source-input.test.mjs \
  scripts/pipe-join-input.test.mjs \
  scripts/compilation-manifests.test.mjs
node scripts/compilation-manifests.mjs
git diff --check
```

JS: 25/25 (`run-QFFsDE`, `focused-test-XqGBp9`). Node: 10/10
(`run-THNYrX`, `focused-test-X4QJGo`). Read-only compilation manifest and
whitespace checks passed. A previous command named a nonexistent test file
(`run-yvalnw`); this was a selection/setup failure, corrected before the
completed 25-test run, not a product result.

Fresh clean-commit five-package production and packed Local/HTTPS acceptance
have not yet run at the time this document is committed. Their exact revision,
tarball digests, receipt and outcomes will be recorded in the PR after execution.
CI, full Core, Wasm/Native, all packed cohorts and snapshot/restart campaigns
are not established by the focused checks above.

The first packed run at `b3a8f0acad4b9252b2a47a346e6b1b668fe0ca18`
completed all ten Local normal cases and the explicit-ceiling execution
failure. It then stopped because the shadowed-Graph refusal fixture used the
generic input-code set, which excludes `ClientProgramImplementationLimit`.
The existing public path returned that typed refusal for applying the Graph
Bridge to a Relation. The fixture now pins that exact code; the expected
rows, schema, limits and product implementation are unchanged. Evidence:
`worktrees/.codex-scratch/public-query-evidence-5fhThV/{summary.json,010.stdout.log,010.stderr.log}`
(relative to the shared workspace). HTTPS and subsequent refusals were not
established by this failed run. Successful execution must be verified again
using the corrected clean commit and its normal five-package distribution.
