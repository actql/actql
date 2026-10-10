# Graph rows as ordinary set operands

Baseline: main `ce027a937cf780f617d5ed98bb4d56ecbb010877`.
This is independent of #1243's JOIN connection. Both use the established
terminal positional SELECT contract, but JOIN public acceptance retains a
separate physical-capacity dependency. It changes frontend assembly only, without a
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
The final standalone inventory after the refusal-source correction is recorded
below. The temporary combined integration SHA is retained as earlier evidence,
not this PR's release unit.

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
before the failing counterexample above. These focused checks alone did not
establish public execution. The current-main acceptance below records the
subsequent scoped execution, separately from full Core, Native/Wasm, hosted CI
and complete packed-corpus coverage.


## Current-main public acceptance

Adopted main: `0c6538b53f63a3c8a42770092e16035103749e9e` (normal merge,
no conflict). Clean implementation/fixture SHA:
`b54e2fd795dc04d1a465b9b778e76ced1ee58d7b`.

- Selected JS Graph/set/DATA callers: 14/14 (`run-Hr0umc`,
  `focused-test-DVexah`).
- Selected Node fixtures/profile registration: 38/38 (`run-uJi7QO`,
  `focused-test-vlLSt7`).
- Normal exact-HEAD five-package producer, independent manifest/digest check
  and existing `--graph-rows-only` consumer: passed (`run-PCM18C`).
- Embedded Local and authenticated HTTPS each completed all 36/36 cases:
  23 normal and 13 refusal cases. Both inventory hashes equal
  `4f9ff4b2ac79ce815274743fdabbc6b55d6936a448dd888897d04b8cfa5b0037`.
  The full authored registration is 3,315 occurrences, digest
  `27202fc0839224dcf87a8d4a37c6642350c59bba7148619f15fc034ffd39b19b`.
- The existing consumer checked rows, actual describe contracts/nullability,
  column order, internal-field absence, same-request Run reuse and reread.
  Refusals retained zero Run admission and provider I/O. No Source reads were
  added to source-free cases. Both workers exited zero, with no live children.
- Receipt `public-query-evidence-GtQoXO` is complete/passed, has no evidence
  errors and confirms the owned installation artifacts were removed. Logs,
  manifest and receipts were retained. `git diff --check` and the changed-file
  MoonBit format check passed.

Evidence paths relative to the worktree:
`_build/local-checks/attempts/run-PCM18C/{summary.json,output.log}` and
`../.codex-scratch/public-query-evidence-GtQoXO/{summary.json,010.stdout.log,010.stderr.log}`.
Packages/manifest: `/private/tmp/actql-b-graph-rows-set-b54e2fd79-pack`.

| Package | SHA-256 |
|---|---|
| client-wire | ca7aaf03f3f1d78aff24c42a4ebe94ae2136ce29ba3fdf8ed81478e359e3df60 |
| sdk | 64eca760cdce9f0da1ea53542ede457ec9f5c80603d9b13721077d90c7b91c1e |
| run-host-core | 642f838049f32ba9a43860e29f941f845861459aed6fb5421f0d89435cc585b9 |
| local-node | 0942037d2729ae35816d98906cc25638fe339ddc621b766f5381095d4bedb28d |
| node | a77756e97078c7df0ea0a318e5ccd74bd7aee2891caa148da2688f9c3eb2d9eb |

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-graph-rows-set-b54e2fd79-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-graph-rows-set-b54e2fd79-pack node scripts/test-packed-public-query.mjs --graph-rows-only
```

The commands ran under the bounded exclusive local-check owner, using pinned
Node/MoonBit, one normal producer and one scoped consumer. Subsequent evidence
edits do not rename this tested distribution revision to a later submitted SHA.
Full Core, other targets, the full packed corpus and hosted required CI were
not run. This is a bounded frontend repair, not completion of all frontend
coverage. Explicit RESULT directly following a set chain is not established
by these fixtures; the root set uses the existing default Result, while DATA
sets use an explicit subsequent Result declaration.

## Earlier refusal-fixture correction

On temporary combined SHA
`81250607ee8621659276653afa6c9bbc1fc680e3`, the same normal Graph cases passed
both transports, but the newly authored private-field refusal placed ORDER in
a subsequent DATA consumer. That reached existing `UnsupportedOrdering`
implementation-limit classification instead of the set-tail `UnknownReference`
boundary fixed by the MoonBit regression (`run-hURH47`,
`public-query-evidence-TUqie2`). It was not a complete successful cohort.

Move this refusal source to the same set-tail scope as the independent MoonBit
regression; keep `ClientProgramInvalidInput`, the private field and zero
admission/I/O expectations unchanged. The Node fixture guard now checks that
scope explicitly. No product refusal check was weakened, and no expected
row/type/order was changed. The later ordinary Relation ORDER diagnostic is
not certified by this correction. The complete current-main acceptance above
supersedes only this corrected fixture, without relabelling the earlier SHA.
