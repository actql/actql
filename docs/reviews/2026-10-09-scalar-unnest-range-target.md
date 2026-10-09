# Scalar UNNEST range names and Pipe RENAME

Status: Frontend repair; focused checks complete. Public packed execution and
submitted-HEAD CI are recorded separately when available. This branch depends
on #1146 at `50b2c190f293ead019d581dd153b4e88231064ac`; the final merge target is
main after that parent is integrated. Adopted main:
`1b0ae88c87683b94cfd96e73f96f969cb4ecf355`.

## Existing selected contract

Pinned GoogleSQL `d82db99a923a46571f543a13899dc791a7b6f743`,
[resolver_query.cc](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/resolver_query.cc):
`ResolveArrayScan` explicitly treats every array alias as a range variable.
`ResolvePipeRename` calls `FillItemStructFromNameListColumns` with scope
ambiguity checking; a range hides a same-named column and cannot be renamed.
SET and DROP intentionally allow a matching whole column and remove its range.
This is an existing adopted Pipe rule, not a new interpretation or an assertion
of live Google-service conformance.

```sql
FROM UNNEST(@items) element WITH OFFSET position
|> RENAME element AS next
|> SELECT next, position
|> ORDER BY position
```

The original range target must be refused. The old lowerer accepted it because
only object UNNEST recorded range names. An explicit SELECT or AS first creates
an ordinary column scope; SET of the whole value also removes the range.

## Counterexample and repair

Main pre-fix diagnostic `run-RtTKAW` / `focused-test-jVp8tF`: **1/2**.
The independent complete projected-column Program passed normal checking and
matched lowering; the original range RENAME was wrongly accepted. An earlier
0/2 diagnostic had an independently authored direct-query layout compared with
script layout; that second mismatch was test structure, not a product defect.
The corrected expectation explicitly includes the script's projection boundary.

The existing private scope now retains scalar value-table range kind across
JOIN remapping. Those ranges have no member columns; star resolves the scalar
receiver through the existing checked object-star probe and preserves the
existing UnknownColumn refusal. The first attempt (30/31) exposed that routing
regression before this metadata was added. A scalar range is not treated as a
closed-object receiver, so ordinary comparable DISTINCT remains enabled.

Scope reset, SET and DROP clear this metadata together with their existing
range transitions. Duplicate UNNEST aliases also observe the retained range.
No new evaluator, Owner, wire, fallback, capacity exception, common Program
meaning or grammar/law/schema/registry pin changes. D's CTE/assert/Effect/source
predicate implementation is unchanged. One existing JOIN routing expression
receives formatter-only reflow.

## Independent checks

- Related JS callers: **47/47**, `run-mvFyIE` / `focused-test-7igV5Q`.
- Final four new scalar tests: **4/4**, `run-sHBxvC` / `focused-test-WVFD0K`.
  These overlap the earlier selection and are not summed as 51 distinct tests.
- Node fixture/import checks: **12/12**, `run-GYWfyK` / `focused-test-qmZXiW`.
- Two intermediate 48/49 runs failed on an incorrectly authored repeated
  UNNEST syntax. The adopted Pipe shape is `|> CROSS JOIN UNNEST(...)`;
  this corrected source is accepted by the parser before exact scope refusal.

The complete hand-authored normal Program fixes parameter types, UNNEST ports,
projection boundary, offset ordering, public names and Named Result. New public
controls separately compare JSON, SELECT/AS/SET, DROP and scalar DISTINCT.
Expected rows preserve NULL, duplicates and offset order. Five exact refusals
cover bare/backtick names, a JOIN continuation and a duplicate range alias.
Every case is registered in the existing normal packed corpus.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_program/unnest_scalar_range_target_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  scripts/unnest-source-input.test.mjs scripts/unnest-checked-array-source-input.test.mjs \
  scripts/spec-family-imports.test.mjs
```

Caller selection also included UNNEST source/closed-object receiver/star/JOIN,
ordinary RENAME/range collisions, correlated and joined stars and object-column
stars. Full Core/all-target/all-packed/performance, retained-history validation,
live Google conformance and submitted-HEAD CI remain unverified locally.
The full public-text Frontend objective remains active. No merge is requested.
