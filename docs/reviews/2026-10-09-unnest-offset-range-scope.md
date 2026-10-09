# UNNEST OFFSET value-table range scope

Adopted main: `1b0ae88c87683b94cfd96e73f96f969cb4ecf355`.
Parent dependency: #1148, `063d4355bf8df78587df9c5fa3c44ee32ba06ef8`,
retaining its #1146 dependency. Final destination is main after the parents
are integrated, not the dependency branch.

## Contract and independent discrepancy

```sql
FROM UNNEST(@items) element WITH OFFSET position
|> RENAME position AS next
|> SELECT element, next
|> ORDER BY next
```

The source was accepted although `position` is a value-table range. The same
omission permitted a later UNNEST alias to reuse `position`. The fixed pinned
GoogleSQL resolver explicitly adds WITH OFFSET through `AddValueTableColumn`
to make the offset name a range and reject conflicting range variables:
[ResolveArrayScan](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/resolver_query.cc).
`ResolvePipeRename` invokes `FillItemStructFromNameListColumns` with scope
unambiguity enabled: range names hide columns. SET and DROP intentionally
allow a matching value-table column. The same checkout's `pipe_set.test`
and `pipe_drop.test` independently show the offset range and its removal.
This is source/reference inspection, not live Google differential execution.

The pre-repair focused run was **2/4** (`run-6kU2Zh`,
`focused-test-mfW6V9`). The RENAME and reused-alias loops failed at their first
counterexamples; the independently authored projected-offset Program and
ordinary post-projection/edit controls passed. It is not a claim that every
negative-loop member was separately executed before repair or that an old
public Run returned wrong rows.

## Minimal existing-contract connection

The UNNEST branch of `compile_steps` now records the offset using the existing
private scalar-range representation and rejects an authored offset that
collides with an existing range. JOIN's existing scope remapping preserves it.
SELECT/AS/SET/DROP already remove or replace those ranges; no separate resolver,
checker, evaluator, execution Owner, wire, capacity exception or fallback is
introduced. Scalar qualified stars retain their ordinary checked refusal.
No grammar/schema/law/registry pin changes or D CTE/assert/Effect/predicate
function changes are required.

The previous scalar-range positive `DROP element |> RENAME position AS next`
was itself incorrect under this selected rule. Its normal source now projects
`position` explicitly before RENAME; its independently expected rows and column
contracts remain unchanged. The complete original source is retained as a
negative obligation. This is a correction from the reference contract, not an
expectation adjusted to a product-issued value. The earlier #1148 execution
remains evidence for its historical source, not proof of correct offset scope.

The complete hand-authored Program in `unnest_offset_range_scope_test.mbt`
fixes typed nullable array parameters, Values, UNNEST with index, explicit
projection, evaluated-offset sort and final column order. It passes the
ordinary checker before exact source Program comparison. A separate public
JSON control uses the same common operations with independent producer names.

## Limited verification

- Initial repaired affected JS callers: **31/31**, `run-gO0haW` /
  `focused-test-kkz6db`.
- Final affected JS callers: **32/32**, `run-JBKA6A` /
  `focused-test-EK49tS`, adding the public single-query compiler and DROP followed
  by legal range-name reuse. These are overlapping selections, not 63 tests.
- Node fixture/normal registration/import checks: **13/13**, `run-kgCpng` /
  `focused-test-LmsSxD`.
- Changed-file formatting and `git diff --check` pass.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_program/unnest_offset_range_scope_test.mbt \
  src/query_program/unnest_scalar_range_target_test.mbt \
  src/query_program/unnest_receiver_scope_test.mbt \
  src/query_program/unnest_join_continuation_test.mbt \
  src/query_program/unnest_pipe_edit_scope_test.mbt \
  src/query_program/pipe_rename_target_scope_test.mbt \
  src/query_program/pipe_edit_range_collision_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  scripts/unnest-source-input.test.mjs scripts/unnest-checked-array-source-input.test.mjs \
  scripts/spec-family-imports.test.mjs
```

## Public execution obligations

The existing normal UNNEST corpus and `--unnest-source-only` both register
seven new positives and eight precise refusals. The intended complete cohort
is **86 positives / 42 refusal loops per Embedded Local/HTTPS**, including all
original cases. Earlier broad-code refusal loops remain distinct from the
new exact `ClientProgramInvalidInput` obligations.

Positive cases include independent JSON, SELECT/AS/SET scope changes, default
offset names, typed empty output and legal reuse after DROP. Input `[2,null,2]`
must preserve the NULL and duplicate values with offsets 0,1,2; SET position
+10 must publish 10,11,12. No expected row, type, order or execution ceiling is
weakened. Direct/quoted/default RENAME, JOIN continuation and later UNNEST
range collisions must be refused before durable Run admission or Source I/O.
Existing assertions include complete types/nullability/column order,
Result.describe, complete streams, private-slot absence and same-Run
resend/attach/reread without additional acquisition/execution.

## Fresh packed Embedded Local/HTTPS evidence

The serialized bounded campaign `run-SsaPbP` normally produced all five
packages at clean product/fixture SHA
`ce8d7c2dd07fb281f9acb29a5541a879f956358b`. The subsequent evidence commit
changes this report only. No overlay, relabeled manifest or prepack bypass.

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-offset-range-ce8d7c2dd-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-offset-range-ce8d7c2dd-pack \
ACTQL_TEST_NPM_CACHE=/private/tmp/actql-b-group-key-slot-collision-integrated-pack/npm-cache \
node scripts/test-packed-public-query.mjs --unnest-source-only
```

Both transports completed **86 positives / 42 refusal loops**. The completed
stdout independently contains all 86 positive names and 29 exact refusal-code
lines per transport; thirteen historical broad-code refusal loops are not
recounted as precise-code evidence. All eight new refusal sources report
`ClientProgramInvalidInput`, zero durable admission and zero Source I/O.
The corrected scalar-DROP positive, nullable object cases and the new DROP
followed by legal reuse all pass without weakening their values or types.

Receipt directory:
`/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-9JDaNM`.
Independent receipt inspection confirms the exact source SHA, passed/complete,
ten complete zero-exit result commands, complete output, no signals/errors or
evidence errors, and `artifactsRemoved:true` with the artifacts directory absent.
README Local/HTTPS and the intentional missing-generated-asset child refusal
also pass. Successful private installations and Stores were reclaimed; logs,
receipts, original package manifest and digests remain.

Original normally packed SHA-256 digests:

| Package | SHA-256 |
| --- | --- |
| client-wire | `ca7aaf03f3f1d78aff24c42a4ebe94ae2136ce29ba3fdf8ed81478e359e3df60` |
| sdk | `64eca760cdce9f0da1ea53542ede457ec9f5c80603d9b13721077d90c7b91c1e` |
| run-host-core | `f5487ba69e88efbab8e99930482c27254b8055f421280045a46c0532f8349d1b` |
| local-node | `dc9b2dfc0e670ee882732ee85e1211b7378c3cac838e61e7378fd8235f017c88` |
| node | `a77756e97078c7df0ea0a318e5ccd74bd7aee2891caa148da2688f9c3eb2d9eb` |

Required CI, full Core/Native/Wasm/Cloud, complete retained-history validation,
broader value-table ordinal behavior and the overall Frontend objective remain
unverified. No manual CI retry or merge is requested.
