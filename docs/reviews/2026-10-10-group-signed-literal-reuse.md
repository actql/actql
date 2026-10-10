# Grouped and selected numeric literal reuse

Date: 2026-10-10. Owner: B. Base:
`584b3a6144d4a8053ca4a541ef042a6e17c674e9`.

## Confirmed defect

```sql
SELECT x + +1 AS next, COUNT(*) AS n
FROM t
GROUP BY x + 1
ORDER BY next
```

The independent complete Values Program groups the evaluated `x + 1` key,
selects that key as `next`, and returns `[{next:2,n:1},{next:3,n:1}]` for
`x = [1,2]`. It passes the ordinary checker. At the base, the source fails
lowering with `Expression(UnknownReference)` because expression comparison
distinguishes a unary sign node from the numeric literal already produced by
the existing expression lowerer. The same comparison also prevents DISTINCT
ORDER from reusing an equivalent selected expression after its input is removed.

The exact pre-fix failure is retained in local check `run-DKyCDO` and focused
evidence `focused-test-dE2RQm`. The earlier `run-KhK3vL` recorded an unwrap
failure; it did not print the typed cause.

## Existing contract and repair

`query_expression/lower.mbt` already admits numeric tokens with
`numeric_literal`, carries numeric atoms through parentheses, and folds unary
signs on numeric literals. It rejects negative zero and unsafe integer tokens.
No arithmetic expression, reference or call is constant-folded by this repair.

The pinned GoogleSQL checkout
`d82db99a923a46571f543a13899dc791a7b6f743`,
`googlesql/analyzer/resolver_expr.cc::ResolveUnaryExpr`, also resolves unary
plus to its numeric operand after type validation. This supports the `+1`
counterexample; it is not a claim that every ActQL nested-sign folding decision
or numeric domain is identical to GoogleSQL.

`query_program/compile.mbt::comparison_numeric_atoms` classifies admitted
literal atoms once per expression in postorder. `same_expression` compares
those values before structural comparison. Invalid atoms cannot establish
equivalence. Existing clause-aware receiver resolution still decides whether
SELECT, GROUP and ORDER refer to the same slot. Numeric references keep their
ordinary type-preserving unary operations; `+x` is not treated as `x`.

No public syntax, expression wire, law, schema, identity pin, execution Owner,
capacity limit or authorization rule changes. Programs newly admitted by this
repair use ordinary evaluated Group or SELECT slots.

## Independent evidence and scope

- `group_signed_literal_test.mbt`: two independently authored complete Programs
  for grouped and DISTINCT output; normal checker admission; different-value,
  invalid-number and alias-receiver controls.
- `group_signed_literal_wbtest.mbt`: failed literal admission never proves
  equivalence, and arithmetic/reference expressions are not folded.
- Existing JS focused runs: new tests 5/5 (`run-VGr8jP`); DISTINCT ORDER 15/15
  (`run-ALebeU`); numeric literal, OVER receiver, unary-plus and ORDER ordinal
  files 15/15 (`run-fZ4PjH`). These selections overlap; counts are not a unique
  aggregate campaign.
- `unary-plus-source-input.test.mjs`: 4/4 (`run-sHvdGZ`), checking independent
  fixture values and the existing normal/focused packed consumer registration.
- The existing unary-plus public corpus gains an acquired JSON control and
  source cases covering repeated keys, NULL, duplicate rows, empty input,
  WHERE, a SELECT-headed Pipe tail, LIMIT, DISTINCT, alias precedence and typed
  pre-admission refusals. Expected rows and ordered contracts are authored
  independently; the harness checks Named Result descriptions and reads.

The new public cases are prepared, not claimed executed in this document.
Exact clean source SHA, five-package digests, retained packed receipts and
Local/HTTPS results are recorded in the PR after execution. Full Core,
Wasm/native execution, Cloud, performance and hosted required CI are separate
unverified scopes until their own evidence is available. No manual CI rerun
or merge is performed by B.
