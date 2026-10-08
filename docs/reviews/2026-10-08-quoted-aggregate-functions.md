# Quoted aggregate function connection

This independent unit connects decoded identifiers to the existing closed
aggregate parser. It does not depend on the quoted scalar-function change or
alter common aggregation semantics.

## Requirements and counterexample

The selected GoogleSQL profile treats function names as decoded identifiers.
The fixed reference is
`google/googlesql@d82db99a923a46571f543a13899dc791a7b6f743`:

- [Parser](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/parser/googlesql.tm):
  quoted identifiers are decoded by `token_identifier`, and
  `function_call_expression_base` accepts an identifier path.
- [Resolver](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/resolver_expr.cc):
  `GetFunctionNameAndArguments` passes `ToIdentifierVector()` to the common
  function lookup. Quotation does not select a different aggregate meaning.

Before this change, `QueryParser::aggregate_head` only recognized `Word` tokens.
An installed name such as `` `VAR_POP` `` entered the ordinary scalar path and
failed instead of forming Group; `` `COUNT`(*) `` could not parse its star as
an aggregate argument. The common Program and statistical aggregate already
support these operations.

```sql
SELECT `VAR_POP`(amount + 1) AS v FROM orders
```

The regression compares the entire Program with the existing independently
authored Values/group/projection/Named Result expectation. It keeps the added
operand, argument field, grouping list, output name and declared field order.
The ordinary checker accepts the expected Program and unquoted control. The
quoted compilation then fails before the fix. Receipt:
`_build/local-checks/attempts/run-orFvUT` (one test, zero passed).

## Connection and preserved boundaries

Only the aggregate name-token cases in `query_syntax/query.mbt` change:
`aggregate_head` and `aggregate` accept `Word` or decoded `QuotedName`. The
same finite name table, canonical name, argument parser and modifiers remain.
The existing projection, embedded-aggregate, Pipe, HAVING, ORDER and aggregate
OVER callers use that parser; no alternate aggregate resolver is introduced.
Function recognition still requires a following opening parenthesis. Quotation
does not grant a namespace or turn one identifier containing a dot into a path.
Star restrictions, DISTINCT rules, argument arity, NULL exclusion, input scope,
numeric profile, frame and common type checks remain in their existing owners.
CTE, Source predicate, assert and Effect handlers are not changed.

This removes an implementation gap under the adopted decoded-identifier rule;
it does not introduce a new expression representation, structural grammar,
machine contract, identity preimage or pin. Reference source inspection is not
live Google service execution or a claim of full aggregate compatibility.
Nonaggregate analytic function-name support is a separate boundary.

## Independent verification and public work

- The bounded corrected working-tree gate passed **12/12 JS tests**: new
  parser and complete-Program expectations, existing statistical syntax and
  compiler controls, and aggregate WHERE callers. Receipt:
  `_build/local-checks/attempts/run-An1dZd`; focused evidence:
  `_build/focused-evidence/focused-test-oYVEjt`.
- A later bounded working-tree gate passed **5/5 JS tests**, including
  independent complete Programs for quoted COUNTIF OVER in SQL/Pipe with
  nullable operands and a one-row preceding/following frame, and COUNT-star
  over empty source-free input. The ordinary checker accepts both controls;
  the empty case requires no acquired inputs. Receipt:
  `_build/local-checks/attempts/run-ekNB6B`; focused evidence:
  `_build/focused-evidence/focused-test-w0X5wj`. This supplements the earlier
  12-test gate rather than relabeling it as a later clean-HEAD run.
- Public statistical fixture syntax, including the later source-free
  COUNT-empty case, and `git diff --check` passed.
- Existing fixed positive, failure and refusal cases are retained. New public
  examples add mixed-case/escaped names in SQL/Pipe, aggregate OVER with the
  original prefix order and NULLs, and COUNT-star on empty source-free input.
  Expected variance, typed NULL, count zero, field order and full column
  contracts are independently authored, not generated from product output.
  The default corpus and existing `--statistical-aggregate-only` consumer
  both include these cases; no new acceptance runner is introduced.
- Public Local/HTTPS execution, exact submitted-SHA packages/digests and CI
  remain unverified until recorded separately in the PR body. Selected tests
  do not establish full Core, Wasm/Native or broad packed success.

The PR must retain Draft while public execution is incomplete. A vocabulary
match or complete-Program comparison alone is not public Host acceptance.
