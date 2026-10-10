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
- Final five new scalar tests, including the public single-query compiler:
  **5/5**, `run-VnsTHq` / `focused-test-Sd91Db`. These overlap the earlier
  selection and are not summed as 52 distinct tests.
- Node fixture/import checks: **12/12**, `run-GYWfyK` / `focused-test-qmZXiW`.
  Final format assertions: **7/7**, `run-p7ogRR` / `focused-test-XrMCMT`.
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

## First public diagnostic and fixture routing correction

Normal clean five-package campaign `run-HsYe2W`, SHA
`a048ea628090bbf789b933e5352d1816f7ccb7a7`, stopped after two Local JSON
controls. Receipt `worktrees/.codex-scratch/public-query-evidence-vNz7RV` retains
the failed command/logs. Local text and HTTPS were not completed.

The new FROM-headed Pipe controls had inherited `format: sql` instead of the
existing `aql-text` routing. Public preparation correctly refused WrongQueryForm;
this was a fixture format error, not a product execution failure. The five new
positive texts and five scope refusals now explicitly select aql-text. Synthetic
preparation diagnostics using that same unchanged packed runtime pass all five
positives after correcting the format. This is not pristine new-SHA execution
evidence. New Node assertions prevent a format refusal from masquerading as the
intended scope refusal. Values, types, column order, predicates and bounds remain
unchanged. Fresh execution follows the corrected committed fixture below.

## Fresh packed public execution

Clean normally packed product/fixture SHA: `5a5fb1d75ae4e2e8f5d35e8210481a4a3d865426`. One serialized
bounded campaign, `run-9pLYAR`, normally produced the original five packages,
verified their digests and ran the existing UNNEST cohort.

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-scalar-unnest-corrected-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-scalar-unnest-corrected-pack \
ACTQL_TEST_NPM_CACHE=/private/tmp/actql-b-group-key-slot-collision-integrated-pack/npm-cache \
node scripts/test-packed-public-query.mjs --unnest-source-only
```

Both Embedded Local and HTTPS complete **79 positives / 34 refusal loops**.
Twenty-one exact refusal codes per transport are logged; older broad-code checks
are kept separate. New range-target refusals require ClientProgramInvalidInput,
zero durable admission and zero Source I/O. Original controls are retained.

The existing consumer verifies independent JSON/text rows, full column types,
nullability and order, stream completion, private-slot absence and same-Run
resend/attach/reread without additional acquisition or execution. Scalar NULL
and duplicates are preserved; DISTINCT publishes 2 then NULL. SELECT/AS/SET
make an ordinary renameable column; whole DROP removes its range.

Receipt `worktrees/.codex-scratch/public-query-evidence-1cULoH` independently
confirms exact SHA, passed/complete, ten clean complete zero-exit commands,
all expected positive names and exact codes in both transports, no evidence
errors and artifactsRemoved=true. README Local/HTTPS and the intentional
missing-generated-asset check also pass. Successful installations and Stores
were reclaimed; logs/receipt remain. No overlay, relabeling or prepack bypass.

| Package | Original SHA256 |
|---|---|
| client-wire | ca7aaf03f3f1d78aff24c42a4ebe94ae2136ce29ba3fdf8ed81478e359e3df60 |
| sdk | 64eca760cdce9f0da1ea53542ede457ec9f5c80603d9b13721077d90c7b91c1e |
| run-host-core | f5487ba69e88efbab8e99930482c27254b8055f421280045a46c0532f8349d1b |
| local-node | 621db8e37d46f13ae6c4732970bcf341740503d395e9711ddfabdc2cbc103ffd |
| node | a77756e97078c7df0ea0a318e5ccd74bd7aee2891caa148da2688f9c3eb2d9eb |

The subsequent evidence commit changes this report only. Submitted-HEAD CI is
checked after publication; local success is not CI success. Keep Draft and the
unmerged #1146 dependency; no merge or manual CI retry.
