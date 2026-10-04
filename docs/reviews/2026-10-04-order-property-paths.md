# Nullable object paths in SQL ORDER BY

## Baseline and contract

The independent branch starts at main
`76674a6b791d0b414444c8adc5014517972411c2`. It does not depend on the pending
grouped SELECT/HAVING repairs. This unit connects existing expression semantics;
it adds no STRUCT constructor, type system, execution owner or provider.

The adopted [query scope](../spec/query-text.md#scope-and-lowering) permits a
normal SELECT to order by a visible non-output input expression, resolves output
aliases first and retains qualified input references. The existing common
`property` expression propagates a nullable object receiver and rejects missing
fields or a non-object receiver. A removed input does not return after DISTINCT.

Primary references are Google's [ORDER BY clause](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#order_by_clause)
and [field access operator](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/operators#field_access_operator).
They describe alias precedence, non-selected ordering columns and typed nested
field access. No Google service differential execution was performed. The
repository's pinned common object contract remains authoritative for this
implemented subset; this is not a claim of all GoogleSQL STRUCT behavior.

## Counterexample and repair

Both new baseline tests failed (`run-ZDY8ka`, `focused-test-MS7hQ4`):

```sql
SELECT id FROM objects ORDER BY payload.score + 1 NULLS LAST;
SELECT id, other AS payload FROM objects ORDER BY payload.score;
```

SELECT and Pipe expressions already use `append_with_properties`, whereas
`append_order_expression` used the scalar-only append entry. An additional
direct-Reference branch treated every unresolved dotted path as an unsupported
sort column, before the expression lowerer could resolve an object prefix.

The repair changes these two local ORDER boundaries. Existing direct columns
retain their direct sort path. Other paths use the existing prefix resolver and
common property expression in one hidden sort slot. The output alias points to
its already evaluated physical value; a qualified input path points to the
input snapshot. The ordinary projection removes helper fields. Graph macros,
CTE/assert/Effect assembly, checker, strategy, Host and SDK are unchanged.

## Independent expectations

The typed input has three rows:

| ID | Input payload score | Other score |
|---|---|---|
| 2 | 10 | 30 |
| 1 | 20 | 5 |
| 3 | NULL receiver | 15 |

Sorting `payload.score NULLS LAST` returns IDs **2,1,3**. After `other AS payload`,
sorting `payload.score` returns **1,3,2**; sorting `objects.payload.score NULLS
LAST` still returns **2,1,3**. Wrong alias resolution produces a different order.

The [MoonBit cases](../../src/query_program/order_property_paths_test.mbt)
include a complete handwritten Program, compare canonical Program semantics,
and check both expected and generated Programs through the common checker.
They retain the original nullable object, exact field contracts, sort/null
placement and final ID-only projection. Invalid DISTINCT scope, missing fields
and scalar receivers remain rejected at their existing ownership boundaries.
An object-parameter DATA case checks ordinary declaration/value binding.

The [public fixtures](../../scripts/fixtures/order-property-source-input.mjs)
contain **seven positives and five preparation refusals**. A handwritten JSON
control uses Values, while authored text builds the same typed rows from bound
object parameters and ordinary SELECT/UNION ALL DATA. The normal packed corpus
includes these cases. Tests never patch the lowered Program or infer a schema
from observed rows. Public checks compare Named Result rows and ordered full
column contracts, no private sort columns, stream completion, same-Run resubmit
and attach, and zero Source acquisition. Refusals must have zero Run admission
and zero provider I/O.

## Executed evidence

- New focused cases: **5/5** (`run-825mwA`, `focused-test-HHZE5t`).
- Affected existing/new ORDER callers: **42/42** (`run-0eiJ9T`,
  `focused-test-z1Tjy4`), before the fifth test-only DATA case was added. Counts
  overlap and are separate executions, not a combined unique test count.
- Changed MoonBit formatting, three JavaScript syntax checks and diff checks
  pass. The initial test helper lacked the declaration decoder and failed to
  compile; it was corrected before publication, not counted as an execution pass.
- Fresh packed Local/HTTP execution is pending. Authored rows and successful
  checker tests do not establish public execution acceptance.

No grammar, wire, schema, numeric law, saved-data format or version changes.
Previously rejected valid sources obtain an ordinary Program and its normal
identity. Full Core, all targets, native, proof and performance checks are not
local prerequisites for this bounded Frontend repair; required CI remains
separate from these focused results.
