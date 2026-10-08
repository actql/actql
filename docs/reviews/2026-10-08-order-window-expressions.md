# Inline window expressions in ORDER BY

Owner: B. Parent dependency: PR #1002, `ec00b6308f019f44e0b196e1a4ce1843f66f3df2`.
This unit connects already selected window-expression placement to existing
Program analytic/derive/sort/select operations. No execution Owner is added.

## Contract and counterexample

The [GoogleSQL window-call rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/window-function-calls)
and pinned `google/googlesql@d82db99a923a46571f543a13899dc791a7b6f743`
resolver tests distinguish these clause scopes:

- SELECT window operands and OVER keys see the original input snapshot.
- A SELECT-owned ORDER window may consume evaluated SELECT aliases in its
  arguments and OVER keys. Qualified columns retain their input meaning.
- A SELECT alias containing a window cannot feed another window. New analytic
  calls after SELECT DISTINCT and named-window references in ORDER are refused.
- Inline ORDER windows are evaluated before QUALIFY. Pipe ORDER and post-set
  ORDER instead operate on the current projected/combined Relation.

Pinned sources: `googlesql/analyzer/testdata/analytic_functions.test`, sections
"SELECT-list alias" and ORDER alias resolution (including DISTINCT and aliases
containing analytics); `googlesql/analyzer/resolver_query.cc`,
`ResolveOrderBySimple` and `ResolvePipeOrderBy`.

The independent complete Values Program in
`src/query_program/order_window_expression_test.mbt` passed the common checker,
while this source failed to parse before the connection:

```sql
SELECT id FROM orders
ORDER BY ROW_NUMBER() OVER (ORDER BY amount DESC, id) DESC
```

Pre-fix result: 1/2, `run-4EJgPH` / `focused-test-2dxaUR`.
This establishes a compiler gap, not a pre-fix accepted Run or public
misexecution. A second independently authored full Program fixes alias
materialization and one-time evaluation separately from the syntax control.

## Implementation

The shared bounded primary callback extracts ORDER windows and non-window
aggregates from the original token stream. `OrderAnalytic` is a Frontend-only
AST operation carrying SELECT-owned versus current-row scope. It is not a new
Program operation, physical task, wire format or saved representation.

SELECT alias demand shares one materialization helper with QUALIFY. Scalar
aliases are evaluated against the SELECT snapshot and reused by final SELECT.
The new ORDER window resolver does not expand alias expressions into each
argument. Previously evaluated SELECT windows and private operands remain
separate from ORDER outputs, so nested windows are rejected rather than
silently becoming sequential legal calls. Ordinary final projection removes
private window/key/sort columns, including after a Pipe ORDER.

Set ORDER computes its analytic operations over the combined output before
sorting, then selects the original output columns. It does not expand or
reacquire operand producers. Common checker, expression demand, NULL,
partition/order laws, signature/frame, capacity and error contracts are reused.
Existing unsupported frames and function signatures are not invented here.

## Identity and generated artifacts

`docs/spec/query-text.md` corrects the previous blanket input-scope statement
for OVER to distinguish SELECT and ORDER. The generic expression/OVER grammar,
Program and AoA laws are unchanged. The grammar manifest changes from
`sha256:582ecd6f94df7584160874befda4fa5f2a7d028f347599fc11e9685c10ba36e8`
to `sha256:ba59c48eb915694484664a7daf7f839e492c36eae44137993f39130793c59672`.
Normative imports, generated manifest/canonical fixtures and interface are
updated by their existing generators. Historical independent grammar/Run
vectors remain intact.

The fixed ordinary Values fixture's Run CID changes from
`sha256:e5068efe3ea2216fc07cd3373f3ca0ba9af030ea9b7514aa33e75067d209e869`
to `sha256:afb2b3cedb82f86b5296376ac0dd10cee8991082c1f05971768059bb52d77e2b`.
This is derived by the existing independent, hand-assembled preimage oracle,
not copied from a product failure. Old saved identities are not rebound to
these pins.

## Focused evidence and public obligations

Working-tree JS: 26/26, `run-FMdTIK` / `focused-test-eEenXh`:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- --target js \
  src/query_program/order_window_expression_test.mbt \
  src/query_program/qualify_test.mbt \
  src/query_program/window_scalar_projection_test.mbt \
  src/query_program/set_order_expression_test.mbt \
  src/run_publication_host/client_values_run_materials_wbtest.mbt
```

Node: 27/27, `run-i5Hui8` / `focused-test-uorFQ0`, selecting the new and parent
fixture registrations, compilation manifests, SGA normative preimage,
independent Values Run oracle, frontend profile and normative import checks.
Affected package interface generation and read-only manifest/import checks:
`run-EuSOlQ`.

`scripts/fixtures/order-window-source-input.mjs` independently specifies 13
normal cases and 7 preparation refusals. They include JSON control, SQL/Pipe,
alias-versus-qualified input, nullable LAG alias, pre-QUALIFY LAG, grouped
scalar/aggregate alias, Pipe DISTINCT, combined set duplicates, declared
parameter with LIMIT/OFFSET, and typed empty input. Normal cases retain Named
Result rows, full ordered Result.describe contracts/nullability, internal-slot
absence, one acquisition, and same-request/reread/attach no-reacquisition.
Refusals require zero durable admission and provider I/O. Both groups are
registered in ordinary packed acceptance, with `--order-window-only` selecting
only this cohort for bounded verification.

At this record's initial commit, pristine five-package Local/HTTPS execution
has not run. Working-tree focused checks are not submitted-SHA packed or CI
evidence. Full Core, whole packed corpus, Wasm/Native execution, Cloud and a
live Google-service differential have not run. Broader window signatures and
frames remain separate coverage gaps. The parent dependency is retained until
#1002 reaches main; the eventual merge target is main. No merge is performed.
