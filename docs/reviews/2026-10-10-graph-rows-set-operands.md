# Graph rows as ordinary set operands

Baseline: main `ce027a937cf780f617d5ed98bb4d56ecbb010877`.
This complements #1243's JOIN connection: both use the established terminal
positional SELECT contract. It changes frontend assembly only, without a
Graph execution owner, schema inference, legacy carrier conversion or limit
change.

## Fixed counterexamples

```aql
DATA n = SELECT 1 AS node_key, 7 AS p;
DATA g = PROPERTY GRAPH (
  NODE TABLES (n AS N KEY (node_key) LABEL Node PROPERTIES (p))
);
FROM n |> SELECT p AS value
|> UNION ALL (FROM g |> node_rows() |> SELECT p + 1)
|> ORDER BY value
```

The independent result is `[{"value":7},{"value":8}]`. An explicit `AS other`
in the right operand passes the common checker; removing it fails with
`UnsupportedProjection` (`run-SsfW3i`, `focused-test-qDYWsc`). The Graph-row
suffix omitted the existing positional-output flag. Forward it through
`lower_script_relation_term` and `lower_script_graph_rows` into `compile_steps`.
The same connection covers edge_rows; no bridge identity or presence rule is
reimplemented.

A second counterexample puts the bridge on the left:

```aql
FROM g |> node_rows() |> SELECT p AS value
|> UNION ALL (FROM n |> SELECT p + 1 AS other)
|> ORDER BY value
```

This has the same independent values, but fails with `UnsupportedGraph`
(`run-ZVJFsn`, `focused-test-ltqJJQ`, 2/3). Root/DATA Graph dispatch bypassed
the ordinary set owner. Route only Graph-row set queries through that existing
owner. It explicitly marks its first term as a consumed set head; direct
Graph-row calls still reject an unconsumed set. A whitebox refusal fixes that
boundary so routing cannot silently drop a set suffix. Graph MATCH, CTE,
assert, predicate and Effect implementations are not changed.

## Independent public obligations

The existing Graph-row fixture gains ten normal cases and two refusals:

- Authored JSON controls, named/anonymous text and definition-selected or
  unselected node bridges. Nullable `p + 1` preserves two NULL rows; ordered
  numeric values are seven and eight. Columns retain one nullable number.
- Edge control/text preserve the composite `(part, edge_key)` identities and
  two parallel edges. Ordered values are `10,11,11,12`; the shared eleven is
  not deduplicated. The result column is nonnullable number.
- A root Graph-row head uses the existing default Named Result `answer`.
  DATA-bound sets use a subsequent `FROM combined ... RESULT values`.
  RESULT declaration is explicit there; no new Result is added by this fix.
- Empty typed Graph inputs retain the nullable Result contract and return no
  rows. BY NAME retains `UnsupportedProjection`/implementation-limit refusal;
  the actual private `aql_set_anonymous_4` remains inaccessible after alignment.
- All source-free cases retain zero Source reads. The existing public consumer
  checks actual rows/describe contracts/column order, internal-field absence,
  same-request resend/reread and zero admission/I/O on preparation refusal.
  JSON controls are authored ordinary Programs, never patched source output.

The ordinary and `--graph-rows-only` registrations contain all 36 cases:
23 normal and 13 refusal cases. The standalone Graph addition's inventory is
3,315 occurrences with digest
`445ca703bc5abc13f16e109e3a0b102365f8b04561d9e417c4371fec11c7b2da`.
These registration identities enumerate authored fixtures, not product output.
The combined #1243 inventory is recorded separately after integration.

## Focused verification

- Initial connection and callers: 8/8 (`run-4CRY8Z`).
- Exact BY NAME/private-field boundaries and callers: 9/9 (`run-k04DuH`).
- Both set-head entries and direct-call guard, with DATA/Graph callers: 14/14
  (`run-6zVALl`, `focused-test-kv2Sce`).
- Final Node fixture/profile assertions: 38/38 (`run-HNNome`,
  `focused-test-Jdi2SN`).

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_program/graph_rows_positional_set_test.mbt src/query_program/graph_rows_test.mbt src/query_program/graph_rows_program_wbtest.mbt src/query_program/data_positional_set_test.mbt src/query_program/data_set_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 180 -- scripts/graph-row-positional-set.test.mjs scripts/public-query-profiles.test.mjs
```

The first test-authoring attempt used an unsupported Debug conversion for
query_program.Issue and executed no tests (`run-s4O5me`). It was corrected
before the failing counterexample above. No public execution or full Core,
Native/Wasm, hosted CI or complete packed-corpus success is claimed here.
Normal five-package production and the scoped public consumer must still run
on the combined clean SHA; its receipts belong to that actual SHA.
