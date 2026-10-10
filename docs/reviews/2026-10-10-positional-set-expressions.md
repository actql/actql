# Anonymous terminal expressions in positional set operands

## Adopted baseline and counterexample

Normally integrated main `12f6a10d5169a0810131f273709df2eaa5d16ef3`, which
already contains PIVOT PR #1231 and UNPIVOT PR #1230. Their integration and
prior public receipts remain separate evidence; this follow-up does not reopen
their delivery units or claim complete anonymous-output support.

The selected GoogleSQL reference is
`d82db99a923a46571f543a13899dc791a7b6f743`. Ordinary set operands align by
position and retain the first operand's public names. A terminal right operand
does not need to assign public aliases to every expression just to participate
in that alignment.

The original source remains unchanged:

```aql
(SELECT 'kale' AS product, 51 AS sales, 'Q1' AS quarter
 UNION ALL SELECT 'kale', 51, 'Q1'
 UNION ALL SELECT 'kale', CAST(NULL AS FLOAT64), 'Q2')
|> PIVOT(COUNT(sales) FOR quarter IN ('Q2' AS second,'Q1' AS first))
```

Its independently expected Named Result is
`[{"product":"kale","second":0,"first":2}]`: duplicate non-NULL rows count
twice; the NULL sales value counts zero times. Public columns are product,
second, first, with nonnullable String/number/number contracts. Literal typing
retains product's four-byte UTF-8 bound. The existing independent machine
control has an explicitly unbounded author String schema and identical values.

The clean five-package run at
`55e110643d0f6bcde8f5a3b00c5f94bede629957` passed seven normal cases on each
of Embedded Local and authenticated HTTPS, then rejected this source before
admission. Receipt: `worktrees/.codex-scratch/public-query-evidence-lhOHgz`,
`010.stdout.log`, `010.stderr.log`, `summary.json`; gate `run-N8BIas`.
The eight refusal cases and planned UNPIVOT consumer did not execute. This
failed campaign is not complete public evidence.

The focused lowerer reproduction fails 1/6 (`run-6ymqSm`,
`focused-test-lJ4jYy`). A one-test source-preparation diagnostic using the
already built runtime (`run-XA93oe`, `focused-test-Q0V7Qg`) exposes the exact
cause: SourcePreparation → Frontend → QueryLowering → UnsupportedProjection.
The common checker/kernel is not the cause of this refusal. Diagnostic source
is `/private/tmp/actql-b-pivot-set-preparation.test.mjs`.

## Connection and scope

`compile_set_stages` opts positional right operands into terminal expression
projection. Both current-scope and ordinary SELECT paths in `compile_steps`
create collision-safe private fields only for expressions without authored or
implicit names. The existing simultaneous derive and ordinal set alignment
carry their values; no SQL rewrite, alternate checker, cast, DISTINCT or
frontend evaluator is introduced.

This permission applies only to the last operation in the operand and never to
BY NAME. The new field is not installed as a source-language alias for an
earlier/later operation. The first operand still defines public fields and
order. `projection_alias` retains its original authored/implicit-name rule;
anonymous public output labels and nonterminal anonymous projection scopes
remain independent unconnected coverage. Data-script set lowering has a
separate connection; this change does not claim to have adapted all such paths.

Main's newly aliased positive PIVOT example is retained. Its exact original
anonymous source moves from an implementation-limit refusal to an additional
positive case; values and expected result are not regenerated or weakened.
The ordinary/scoped corpus therefore contains nine PIVOT normal cases and
eight refusals, with the same total of seventeen obligations. The data-only
inventory records the classification change and preserves unrelated cases.
No graph, provider, physical strategy, acquisition, Result owner, capacity limit
or native Effect implementation is changed by this follow-up.

## Verification boundaries

The first fix selection passed 18/18 (`run-pqjcDf`,
`focused-test-zrhv0Q`). A newly added whitebox test initially referenced a
blackbox-only limits helper (`run-4Tm95Y`), then supplied explicit parser limits.
An additional rejection assertion used the wrong expected reason for a
parenthesized continuing operand (`run-74MjOZ`, 21/22); it is replaced by the
direct anonymous-public-output and BY NAME cases this fix actually owns.
These test-authoring failures are not product successes or removed public cases.

The integrated JS selection passed 22/22 (`run-JSmgm5`,
`focused-test-gu4fHV`); the two selected Node fixture/inventory files passed
38/38 (`run-JPfPCF`, `focused-test-yaaOlo`). Restoring main's explicit-alias
MoonBit case as an additional unchanged positive passed all eight PIVOT tests
(`run-jtj9Sj`, `focused-test-rSn9HL`). The clean source revision
`a3b2f77cb174ce9e8ccdf740264b41c3da9907e1` passed normal five-package
production and independent SHA-256 verification, then the unchanged existing
consumer completed both cohorts on Embedded Local and authenticated HTTPS:

- PIVOT: nine normal plus eight refusal cases, 17/17 on each transport.
  Receipt: `worktrees/.codex-scratch/public-query-evidence-7OreHG`.
- UNPIVOT consuming regression: seven normal plus six refusal cases, 13/13
  on each transport. Receipt:
  `worktrees/.codex-scratch/public-query-evidence-y3631T`.

Each receipt has a complete `summary.json`, `010.stdout.log`,
`010.stderr.log` and both terminal worker/inventory records. Both inventories
match their authored case digests with zero missing cases or live children.
Public rows and actual Result.describe contracts, column order, private-field
absence, same-request resend/reread and zero admission/Source I/O for refusals
passed through the existing runner. No failed or unknown case was excluded.
Successful private installations were reclaimed by that runner; retained logs,
receipts and package manifests remain available.

The bounded heavy gate is `run-FtsQOP` (passed, complete, exit zero, locks
released). The normally generated distribution is
`/private/tmp/actql-b-positional-set-a3b2f77cb-pack`. Its manifest identifies
the clean source revision above and these independently verified tarballs:

| Package | SHA-256 |
|---|---|
| client-wire | `ca7aaf03f3f1d78aff24c42a4ebe94ae2136ce29ba3fdf8ed81478e359e3df60` |
| sdk | `64eca760cdce9f0da1ea53542ede457ec9f5c80603d9b13721077d90c7b91c1e` |
| run-host-core | `712228cbe4c27f071c978c7ad7a7d1ad8867ea6fe8d0d5aae9df0552b9ff9c15` |
| local-node | `ef842b9ce3d6dd35e74c9f99b0342ffd871e532eba6a3399bf7e247abb70a049` |
| node | `a77756e97078c7df0ea0a318e5ccd74bd7aee2891caa148da2688f9c3eb2d9eb` |

Commands (with the pinned Node/MoonBit environment and the existing exclusive
bounded local guard):

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_program/pipe_pivot_test.mbt src/query_program/query_set_projection_wbtest.mbt src/query_program/set_inner_by_name_test.mbt src/query_program/set_corresponding_test.mbt src/query_program/set_order_expression_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 180 -- scripts/pipe-pivot-source-input.test.mjs scripts/public-query-profiles.test.mjs
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_program/pipe_pivot_test.mbt
node scripts/packed-client-packages.mjs /private/tmp/actql-b-positional-set-a3b2f77cb-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-positional-set-a3b2f77cb-pack node scripts/test-packed-public-query.mjs --pipe-pivot-only
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-positional-set-a3b2f77cb-pack node scripts/test-packed-public-query.mjs --pipe-unpivot-only
```

The distribution and public results belong to the exact source revision above.
The subsequent evidence-record commit changes only this informative document;
it does not relabel those receipts as execution of a later Git revision.
`git diff a3b2f77cb174ce9e8ccdf740264b41c3da9907e1 HEAD -- packages src adapters spec scripts release`
checks that all package build inputs remain unchanged.

Hosted CI, whole Core and Native/Wasm execution are not claimed. Current-SHA
hosted results will be recorded separately on the independent Draft PR. The
wider frontend goal is still active, including the named unconnected paths
above; no PR merge is performed by B.
