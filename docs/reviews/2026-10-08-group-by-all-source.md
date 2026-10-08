# SQL GROUP BY ALL: input-scope key inference

Owner: B. Target: main. Base: `9bc10e00355b16d19b57f7f3c121d234b90d889c`.
This unit connects adopted SQL syntax to existing group/derive/projection owners.
It adds no execution owner, Source acquisition, budget increase or compatibility path.

## Reference and counterexamples

The selected reference is `google/googlesql@d82db99a923a46571f543a13899dc791a7b6f743`,
`docs/query-syntax.md` (GROUP BY ALL) and
`googlesql/analyzer/resolver_query.cc` (`ResolveGroupByAll`). The
[public clause](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#group_by_all)
specifies exclusions, prefix inference and empty-key global grouping.

Before implementation, the independently authored complete-Program test failed
0/1 (`_build/local-checks/attempts/run-Kc86Dg`). Text could not express the
ordinary group operation through GROUP BY ALL.

- `SELECT x AS y, y AS z, COUNT(*) AS n FROM t GROUP BY ALL` must group original
  input x and y. Resolving inferred keys through output aliases changes this.
- `SELECT x + 1 AS next, x, COUNT(*) AS n ... GROUP BY ALL` groups x once,
  even though its simple path occurs later. Two computed expressions alone
  retain two keys: computed keys do not provide input-path prefixes.
- `SELECT COUNT(*) AS x, x AS original ... GROUP BY ALL HAVING x > 1` needs
  separate physical slots for original x and the evaluated aggregate alias.
  The ordinary explicit `GROUP BY t.x` path has the same obligation. Initial
  lowering exposed `DuplicateOutput`; the alias is now mapped to its own slot.
- `(payload).score` and `payload.score` resolve the same input property path.
  Grouped-key reuse must preserve that resolved meaning across parentheses.
- With no inferred keys, empty input still produces the existing global group.
  With an inferred id key, empty input produces zero typed rows.

The expected complete Programs are handwritten in
`src/query_program/sql_group_by_all_test.mbt`. The public JSON control, rows,
NULLs, multiplicity and ordered type contracts are independently authored in
`scripts/fixtures/group-by-all-source-input.mjs`; compiler output never supplies
an expected value.

## Implementation boundaries

`SqlSelectAll` survives parser operation snapshots and hidden aggregate ORDER
handling. A bounded inference module classifies current SELECT expressions
against the original input slots and property suffixes. It excludes aggregate
and window expressions, constants, parameters and covered simple paths; chosen
keys retain SELECT order. Existing star/EXCEPT/REPLACE expansion is reused.

Inferred expressions bypass explicit GROUP alias/ordinal lookup. The existing
checker retains function/type admissibility and resource validation. SQL group
aggregate aliases use distinct physical slots when they collide with keys;
SELECT siblings retain input scope while HAVING/final ORDER use output aliases.
Private physical columns leave through ordinary projection before publication.

This is SQL GROUP BY ALL, not Pipe AGGREGATE ALL or a general GROUPING SETS,
ROLLUP/CUBE, correlated-query or volatile-function implementation. Existing
unsupported expression/type contracts remain explicit rejections.

## Existing-main parser expectation corrected

The old query_syntax test expected a SET prefix before Pipe JOIN to be refused.
The existing producer-composition parser and current query-text specification
already accept it. Restoring exact main query.mbt and running only query_test
index 15 reproduced the same failing refusal assert (0/1), independently of ALL:
`_build/local-checks/attempts/run-gfeK3F`.

The baseline evidence is
`/private/tmp/actql-b-group-all-main-syntax-baseline-20261008-retry/result.json`.
Current source was restored byte-for-byte afterward. The initial attempt lacked
MoonBit in PATH and is not execution evidence. The obsolete negative assertion
now checks the SET-bearing left producer and JOIN structure; no JOIN product
behavior or public expected rows were changed.

## Contract identity

The grammar change updates generated compilation manifests, normative imports,
complete-document canonical vectors and the independent Values Run closure.

- Prior grammar: `sha256:582ecd6f94df7584160874befda4fa5f2a7d028f347599fc11e9685c10ba36e8`.
- Current grammar: `sha256:209990ef9c813fa9c15f88d4b0898be472b4e4f0068e281512ecfe71769a5d0e`.
- Prior Values Run: `sha256:e5068efe3ea2216fc07cd3373f3ca0ba9af030ea9b7514aa33e75067d209e869`.
- Current Values Run: `sha256:0c8106e879020aa6541115ce2199187148b73e07b18170b65ff4c703e8092374`.

The old complete closure stays as a historical independent vector. New Run
expectations come from the existing independent canonical preimage oracle,
not from a product-issued CID. Values Unit/ResultPlan bodies and barrier
semantics are unchanged; their grammar-dependent Run closure changes.

## Limited verification before submission

Pinned Node 22.22.0 and MoonBit 0.10.12+1634b282e:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- --target js src/query_program/sql_group_by_all_test.mbt src/query_program/group_select_input_scope_test.mbt src/query_program/group_property_keys_test.mbt src/query_program/sql_grouped_subexpression_test.mbt src/query_program/group_having_implicit_alias_test.mbt
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- --target js src/query_syntax/group_by_all_test.mbt src/query_syntax/query_test.mbt src/query_program/sql_group_by_all_test.mbt src/run_publication_host/client_values_run_materials_wbtest.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- scripts/compilation-manifests.test.mjs scripts/client-values-run-materials-vector.test.mjs scripts/frontend-profile.test.mjs scripts/group-by-all-source-input.test.mjs scripts/public-query-cases.test.mjs scripts/public-query-profiles.test.mjs
node scripts/compilation-manifests.mjs
node scripts/update-document-metadata.mjs
node scripts/check-actql-spec-family.mjs
node scripts/check-canonical-json.mjs
```

- GROUP/HAVING callers: 36/36, `run-LmQB4y` (before formatting-only changes).
- Final parser/lowering/Run tests: 31/31, `run-pvaApq`.
- Final affected Node tests: 32/32, `run-lJhyVi`.
- Read-only generation/import checks pass; canonical vectors: 380.
  `_build` attempt/evidence paths belong to this worktree.
- Changed MoonBit formatting and `git diff --check` are checked separately.

The normal public corpus and `--group-by-all-only` both include 15 positive
cases and 6 preparation refusals. Public acceptance uses the existing harness
for ordered Result.describe contracts, rows, hidden-column absence, one Source
session, same-request replay and zero Run/provider I/O on refusal.

At this recorded checkpoint, exact-HEAD five-package packing and external
Embedded Local/HTTPS acceptance have not run. Their immutable SHA, tarball
digests, command evidence and results will be recorded in the PR body after
execution. Full Core, Wasm/native execution, full packed campaigns, performance,
manual CI and service differential testing were not run. Draft is preparation;
no merge or broad conformance claim is made.
