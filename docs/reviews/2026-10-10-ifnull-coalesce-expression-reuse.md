# IFNULL / two-operand COALESCE expression reuse

## Boundary and independent counterexamples

Base: `origin/main` at `584b3a6144d4a8053ca4a541ef042a6e17c674e9`.

The existing query expression owner already lowers `IFNULL(a, b)` and
`COALESCE(a, b)` to the same ordered common `coalesce` node. The adopted
contract is documented in `docs/spec/query-text.md`, under IFNULL, and in the
common expression demand rules in `docs/spec/language.md`. Google's
[conditional expressions reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/conditional_expressions#ifnull)
also identifies the two-operand equivalence. This change adds no function,
overload, coercion or evaluation rule.

Before this change, these already expressible queries fail frontend lowering:

```sql
SELECT IFNULL(x, 0) AS value, COUNT(*) AS n
FROM t GROUP BY COALESCE(t.x, 0);

SELECT DISTINCT IFNULL(x, 0) AS value
FROM t ORDER BY COALESCE(t.x, 0);
```

The reverse function spellings have the same defect. The independently authored
complete expected Programs use one `coalesce` computation followed by GROUP or
projection/DISTINCT/sort. Both controls pass the normal checker before the
source compilation assertion. `same_expression` previously compares Call names
instead of recognizing this installed alias pair.

Pre-change JS: **0/2**, evidence
`_build/local-checks/attempts/run-n55Hfd` and
`_build/focused-evidence/focused-test-rKRrJm`. The earlier `run-JYVzHb` did not
execute tests because the shell lacked MoonBit on PATH; it is not a product
failure. The actual counterexample run uses the pinned toolchain.

## Fix and preserved obligations

`query_coalesce_expression.mbt` recognizes only unqualified IFNULL/COALESCE
Calls with exactly two operands. Function lookup remains ASCII case-insensitive
for decoded names, including backtick names, just as the existing expression
owner. `compile.mbt::same_expression` compares the original ordered operands
through its existing reference and node callbacks. It does not substitute
expressions, flatten COALESCE, reorder children, infer a default or remove a
fallback that appears unused.

Input references and output-alias references still need to resolve to the same
slot before reuse. Different fallbacks, operand order, receiver, arity,
namespace and NULLIF remain distinct. Common typing, demand, failure,
resource accounting and publication remain owned by the existing implementation.
There is no Frontend evaluator or modified Owner.

The extra complete-Program alias test initially described two separate derive
steps. The existing compiler emits simultaneous SELECT computations in one
derive; its temporary sort name uses the reserved input/derived field count.
That fixture structure was corrected after inspecting the existing construction
and naming code. No operand, value, scope, row or type expectation changed.
The intermediate **19/20** result is retained in `run-asuhpj` /
`focused-test-kxmckl` and is a fixture-authoring error, not another product
regression.

## Focused evidence

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/query_program/ifnull_coalesce_reuse_test.mbt \
  src/query_program/distinct_aggregate_expression_scope_test.mbt \
  src/query_program/ifnull_test.mbt \
  src/query_program/quoted_function_test.mbt \
  src/query_program/order_property_receiver_reuse_test.mbt \
  src/query_program/join_order_test.mbt

node scripts/local-checks.mjs test node -- \
  scripts/ifnull-coalesce-reuse-source-input.test.mjs \
  scripts/ifnull-source-input.test.mjs scripts/compilation-manifests.test.mjs

node scripts/compilation-manifests.mjs
```

JS **20/20**: `run-qwNM23` / `focused-test-gg0JY7`.
Node **11/11**: `run-Gnyt9m` / `focused-test-ruIg90`.
The read-only manifest check passes. Syntax, normative meanings, schema,
grammar and rules pins are unchanged; no new canonical vector is required.

## Public acceptance obligations

`ifnull-coalesce-reuse-source-input.mjs` contains independently authored JSON
controls and source cases for GROUP and DISTINCT ORDER in both directions,
quoted names, Pipe continuation, duplicate/NULL input, typed nullable
parameters, empty input and lazy fallback. It separately fixes output alias
ordering to IDs **4,2,3,1,5**, and qualified input ordering to **5,1,2,3,4**.
Both results keep the same values, types and public column order.

The ordinary packed campaign includes the corpus; the
`--ifnull-coalesce-reuse-only` option limits local execution to this boundary.
The existing harness compares Named Result rows and `describe()` contracts,
checks hidden-field exclusion, one Source read session, same-Run resubmission
and re-reading without additional admission/acquisition. Refusals precede Run
admission and provider I/O. A demanded failing fallback remains an execution
failure with no successful Result, rather than a frontend refusal.

At this document's source commit, exact-HEAD normal five-package Local/HTTPS
acceptance is still to be run; its receipt and actual result will be recorded
in the PR body. Focused source tests are not public execution evidence. Full
Core, Wasm/Native, performance and final integration CI have not been run here.

## Scope of the audit

DATE CAST was checked as another possible connection gap and excluded from
this unit: the common Explicit casts table intentionally does not admit DATE
as a target. Frontend syntax alone cannot supply that capability. Existing
common SUBSTR/LIKE/BETWEEN/typed-subscript gaps remain separate, and this change
does not claim the complete frontend objective has been achieved.
