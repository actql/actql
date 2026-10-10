# Reusing an admitted unary-plus GROUP key value

## Existing meaning and reproduced defect

Base: `584b3a6144d4a8053ca4a541ef042a6e17c674e9`.

```sql
SELECT x, COUNT(*) AS n FROM t GROUP BY +x ORDER BY x
```

With Number inputs `x=1,2`, the independent expectation is
`[{"x":1,"n":1},{"x":2,"n":1}]`. Unary plus is numeric identity, not a
permission to drop numeric type checking. The pinned GoogleSQL source
`d82db99a923a46571f543a13899dc791a7b6f743`,
[`Resolver::ResolveUnaryExpr`](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/resolver_expr.cc),
resolves its operand, requires a numeric type and returns that resolved operand.
This does not establish all GoogleSQL numeric domains or coercions here.

ActQL's existing source expression lowerer represents nonliteral unary plus as
two numeric negations. The common signature accepts Number or Decimal, preserves
the operand contract and NULL, and rejects nonnumeric operands. Neither that
lowerer nor the shared signature is changed.

An independently authored complete Values Program retains
`derive.key = {negate:{negate:{field:"x"}}}`, groups that key, and projects it as
`x`. It passes the ordinary checker. Before the fix, source compilation instead
rejects `Expression(UnknownReference)` after grouping removes the original `x`.
The focused regression failed 0/1 at `run-377EYy / focused-test-IYjUkO`.
This is a compiler reproduction, not a pre-fix public Run reproduction.

## Localized correction

`query_group_key_value.mbt` identifies the operand beneath only leading unary
plus and grouping parentheses. `compile_steps` records that tree as another
meaning of the already evaluated SQL GROUP key slot. The original derive,
including every numeric negation, remains in the generated Program and must
pass common checking and execution.

The existing scope-aware comparison and grouped-expression binding reuse that
slot for SELECT, HAVING and ORDER consumers. Repeated operand keys may also use
it without adding another grouping column. Comparison/copying consumes the
existing bounded expression-work budget. No global expression-equivalence rule
is relaxed: `+text` cannot become a bare Text reference through this fix.

The correction does not strip minus or inner arithmetic, restore another input
column, revive an expired range, or change Pipe AGGREGATE's named-output scope.
No public grammar/API, common contract/pin, checker, evaluator, capacity policy,
execution owner or Host routing is changed. There is no dependency on the
separate signed-numeric-literal comparison PR.

## Independent checks and public obligations

- Full expected Program comparison and ordinary checking for `+x`, `+(t.x)`
  and quoted/case-varied column receivers.
- Nullable object member keys and larger SELECT/HAVING/ORDER expressions reuse
  one property computation and retain the numeric operation.
- Ungrouped values, minus/arithmetic keys and expired ranges retain the exact
  `Expression(UnknownReference)` rejection.
- Boolean and String key operands retain numeric negations and the ordinary
  checker's `InvalidInput` classification.
- Nested plus and a repeated bare key retain one key slot and all four
  negations.

The final JS selection, including GROUP ordinals and grouped ORDER consumers,
passed 30/30 at `run-zYtsqV / focused-test-a2ctCD`. The independent Node fixtures
passed 4/4 at `run-KJHjf1 / focused-test-f5tdki`. The earlier affected JS selection
passed 14/14 before the final exact-category assertion was added; it is not
additional unique test coverage.

The existing normal and focused unary-plus packed corpus now includes seven
new successes: an independent captured JSON Program, authored SQL, nested and
repeated keys, SELECT-headed Pipe filtering/LIMIT, empty input, and two alias
collision controls with opposite output orders. Cases check exclusion of ID 0,
duplicate zero keys, NULL key, declared column order and complete Result
contracts. Three exact-code refusals cover nonnumeric keys, another
ungrouped column and a removed range. A demanded division-by-zero key must still
fail execution; normalization must not turn it into a successful Result.

These cases use the existing public SDK/Host harness. It checks Named Result
rows and descriptions, hidden-column absence, completed streams, one Source
acquisition, same-request Run identity, reread/reattach without extra I/O, and
rejection before admission/provider I/O. No Program is patched after lowering.
Exact-HEAD normal five-package Local/HTTPS execution is pending at this
committed snapshot; its actual receipt and digest results belong in the PR
description. Full Core, Wasm/Native runtime, Cloud, broad conformance and required
hosted CI are not established by the focused tests.
