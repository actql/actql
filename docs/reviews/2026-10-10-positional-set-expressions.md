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
(`run-jtj9Sj`, `focused-test-rSn9HL`). Normal fixed-SHA five-package production, independent digest
verification and all nine normal/eight refusal cases through Local/HTTPS remain
required. Public rows, actual Result.describe contracts,
column order, hidden-field absence, resend/reread and zero admission/provider
I/O for refusals use the existing runner. UNPIVOT's completed-scratch regression
will reuse the same verified distribution after the PIVOT consumer succeeds.
Hosted CI, whole Core and Native/Wasm execution are not claimed. The wider
frontend goal is still active; no PR merge is performed by B.
