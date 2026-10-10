# Anonymous aggregate outputs in positional set operands

## Baseline and independent counterexample

Normal main baseline: `d596c9fc5146925e5707e69afe82c2b07807a456`, including
#1234's terminal scalar-expression connection. This is a separate frontend
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

## Executed focused checks and remaining public work

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

Clean fixed-SHA five-package production and public Local/authenticated HTTPS
execution remain required at this implementation-record revision. The existing
runner must compare all twelve normal/eight refusal cases, rows, real description
contracts, hidden-field absence, same-request resend/reread and zero admission
and Source I/O for refusals. Final receipts and package digests are recorded
separately on the Draft PR. Whole Core, Native/Wasm, full packed corpus and
hosted CI success are not claimed. Anonymous public labels, nonterminal scopes,
analytic outputs and the separate DATA-script set connection remain independent
unconnected coverage; the wider frontend goal stays active.
