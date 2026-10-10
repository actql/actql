# Anonymous aggregate outputs in positional set operands

## Baseline and independent counterexample

Adopted main baseline: `d4c8ed4987e8e25d4fc4f408b98705d90e7b7f53`, including
#1234's terminal scalar-expression connection at
`d596c9fc5146925e5707e69afe82c2b07807a456`. This is a separate frontend
follow-up; no shared computation, acquisition or Result owner is replaced.

```aql
SELECT 0 AS n UNION ALL SELECT COUNT(*)
```

Each source-free SELECT begins with one row. The independent result multiset
is `[{"n":0},{"n":1}]`; `COUNT(*) + 1` produces two in the right operand.
The named control already parses, lowers and passes the ordinary checker.
The anonymous direct aggregate fails parsing (`run-rgQ7Rl`,
`focused-test-X09xC6`), specifically at `value_projection`'s mandatory
function-output-name condition. The earlier two probe logs retain unwrap-only
failures; those alone did not identify the boundary. This is compiler evidence,
not a claim that a public Run failed.

The selected GoogleSQL reference remains
`d82db99a923a46571f543a13899dc791a7b6f743`. The adopted EBNF's
`select_item = expression, [ "AS", identifier ]` already permits an absent
alias; positional sets use the first operand's output names. No new public
syntax or normative grammar/common contract is introduced.

## Connection

- Ordinary aggregate parsing retains `Projection.name = None` rather than
  treating a missing output alias as malformed syntax. The analytic name
  requirement and Pipe AGGREGATE's named-output contract remain unchanged.
- Only a positional right operand can allocate a collision-safe private
  aggregate field. The existing Group operation evaluates the call and owns
  its type, NULL, filter, key, argument and collection-limit rules.
- The ordinary and rebound SELECT paths bind that evaluated slot using the
  existing aggregate-call comparison and pre-group input scope. Function,
  argument, filter, DISTINCT, delimiter, ordering and receiver meaning are
  compared. Syntax equality alone or an output-alias receiver is insufficient.
- Private fields are projected through the existing ordinal alignment. They
  never become authored aliases. Unnamed public results and BY NAME operands
  still fail with `UnsupportedProjection`, before Run admission.

One existing parser test called `SELECT COUNT(*) FROM records` malformed.
That negative conflicts with the adopted optional-alias grammar. It is now a
positive AST check proving no alias was invented; incomplete `AS` remains a
syntax refusal. This correction is contract-derived, not copied from product
output. The independent rows/schema and resource ceilings are unchanged.

## Independent public obligations

The existing PIVOT cohort retains every prior normal/refusal case and adds
three normal cases through the same ordinary registration and scoped runner:

1. An independently authored JSON Values/PIVOT control with COUNT-derived
   values one and zero and exact output contracts.
2. Anonymous `COUNT(*)` on an empty right input: global aggregation still
   supplies one zero-valued row. PIVOT yields `[{"second":0,"first":1}]`.
3. Anonymous `COUNT(*)` versus `COUNT(CAST(NULL AS FLOAT64))` in one operand:
   the two evaluated values remain one and zero. Expected output is
   `[{"other":0,"second":1,"first":1}]`. Reusing the wrong aggregate
   changes the retained key and public rows, so this is a semantic counterexample.

Actual Result.describe must report declared field order and number nullability:
other is nonnullable COUNT output; MAX buckets remain nullable. The source and
JSON control have the same independent values/types. No test-side Program patch,
DISTINCT, fill, coercion or limit increase is used. The updated data-only inventory
contains 3,291 occurrences, with only these three normal registrations added.

## Executed checks and remaining coverage

The minimal post-fix counterexample passed 1/1 (`run-QKqJCe`,
`focused-test-h8vWcV`). The first consuming selection passed 24/25
(`run-yvZelf`, `focused-test-q4BUar`), exposing the obsolete malformed-COUNT
expectation above. After the contract-derived correction:

- JS parser/lowerer plus named aggregate, optional alias, aggregate-filter and
  PIVOT callers: 26/26 (`run-4V6ldW`, `focused-test-DCAgdf`).
- Public fixture/inventory Node tests: 38/38 (`run-EJiqIt`,
  `focused-test-YMnFiD`).

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_program/positional_set_aggregate_test.mbt src/query_program/pipe_pivot_test.mbt src/query_program/query_set_projection_wbtest.mbt src/query_program/select_aggregate_expression_test.mbt src/query_syntax/select_aggregate_expression_test.mbt src/query_syntax/optional_output_as_test.mbt src/query_syntax/aggregate_filter_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 180 -- scripts/pipe-pivot-source-input.test.mjs scripts/public-query-profiles.test.mjs
```

The additional authored-HAVING counterexample
`SELECT 0 AS n UNION ALL SELECT COUNT(*) HAVING aql_set_aggregate_1 > 0`
is rejected with `Expression(UnknownReference)`, not a generic error. The four
aggregate test cases passed 4/4 (`run-vHVVwc`, `focused-test-viQ5zQ`). No product
change was needed for this boundary; the check uses the existing name resolver.

Public execution used clean implementation SHA
`83a8c620f811568fed3e07fd0f194dc0d928200b`. The normal producer generated all
five packages, and an independent SHA-256 comparison verified their manifest.
The existing `--pipe-pivot-only` cohort passed **20/20 on Embedded Local and
20/20 on authenticated HTTPS**: twelve normal and eight refusal cases in each.
The checks include actual rows, Result.describe contracts and declared column
order, hidden-field absence, same-request resend/reread, and zero Run admission
and Source I/O for preparation refusals.

- Bounded gate: `_build/local-checks/attempts/run-ZDP2q6/summary.json`.
- Retained command evidence (workspace-relative):
  `worktrees/.codex-scratch/public-query-evidence-7bKxxj/summary.json` and
  `010.stdout.log`; the two transport completion receipts report 20/20,
  terminal success and zero live children.
- Package directory: `/private/tmp/actql-b-positional-aggregate-83a8c620f-pack`.
- Case inventory SHA-256:
  `624e7c6e324ed3e77f57fff9c691928f341cb12d1e816d1d8a808209dab583d3`.
- The runner removed its disposable installation and Host artifacts after
  retaining the evidence; `artifactsRemoved: true`, `evidenceErrors: []`.

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-positional-aggregate-83a8c620f-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-positional-aggregate-83a8c620f-pack node scripts/test-packed-public-query.mjs --pipe-pivot-only
```

These commands ran inside the existing bounded gate. Package SHA-256 values:

| Package | SHA-256 |
|---|---|
| client-wire | `ca7aaf03f3f1d78aff24c42a4ebe94ae2136ce29ba3fdf8ed81478e359e3df60` |
| sdk | `64eca760cdce9f0da1ea53542ede457ec9f5c80603d9b13721077d90c7b91c1e` |
| run-host-core | `712228cbe4c27f071c978c7ad7a7d1ad8867ea6fe8d0d5aae9df0552b9ff9c15` |
| local-node | `ab4d835e2444d4e3e742eeea32feb2e8442df81608ecbf3aa5fafd020f299601` |
| node | `a77756e97078c7df0ea0a318e5ccd74bd7aee2891caa148da2688f9c3eb2d9eb` |

The subsequent evidence/test commit does not alter implementation or public
fixtures. Public success above belongs to the named implementation SHA and its
normal packages; it is not a new-HEAD packed run or hosted CI success.
Whole Core, Native/Wasm and the full packed corpus remain unexecuted locally.
Anonymous public labels, nonterminal scopes, analytic outputs and the separate
DATA-script set connection remain unconnected coverage; the wider frontend goal
stays active. This unit introduces no unmerged implementation dependency.
