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
- Fresh packed source `02e3e54ddd7fffc34b088d4d742001128c6fd402`:
  **seven positives and five pre-admission refusals per Embedded Local and
  authenticated HTTP transport passed** (`public-query-evidence-jXcXDD`). The
  real public SDK/Host compared independent rows and full ordered column
  contracts, checked stream completion, same-Run resubmit/lookup/attach with
  no extra acquisition, and no hidden output columns. Refusals had zero Run
  admission and zero provider I/O. The README quickstart and missing-runtime
  asset control also passed, separately from these seven positives.

The acceptance command was `node scripts/test-packed-public-query.mjs
--order-property-only` using the repository-pinned MoonBit and Node toolchains.
Five packages were produced by normal `npm pack`/prepack and installed outside
the checkout with consumer scripts disabled. The receipt records a clean source
tree, completed zero exit status and no evidence errors. Disposable tarballs,
installation and Host Store were removed after saving logs and identity/digest
records. Subsequent evidence documentation does not change tested product code;
submitted-HEAD CI is recorded separately in the PR.

| Tarball | SHA-256 |
|---|---|
| `actql-client-wire-0.0.0-development.tgz` | `6b448edf6ff246e1865858e9ed654e6f973c602e60b65447bcd7bbdd0afaefde` |
| `actql-sdk-0.0.0-development.tgz` | `feeed615674aaa5f179cb4d5feabdb6713f9e986c8d08cc38f1513338730b8c2` |
| `actql-run-host-core-0.0.0-development.tgz` | `1c81124d1abef56cab7d76a72498f113e5ffcc33d4a0288830a2a18e224a1275` |
| `actql-local-node-0.0.0-development.tgz` | `4f80fbd9cdd06068b6cabf9ddc6d323c9d98cbe9bbbb592dd358c3c0c9c1ba1d` |
| `actql-node-0.0.0-development.tgz` | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

The first fresh packed attempt at `67c4f517532d08bd1348954eef10d3b9bd5d42fc`
(`public-query-evidence-QMBuda`) passed the first four Local positives. The
alias-collision case's rows matched, but its schema comparison failed because
the expected object omitted the fixed checked `additional_properties: false`.
[Value contracts](../spec/language.md#value-contracts) explicitly requires that
expansion in checked/protocol contracts and forbids it in author declarations.
The fixture now includes it only in expected Result columns, independently of
the product encoder. Input declarations, rows, value types, NULL behavior and
expected sort orders are unchanged. Logs were retained and the disposable
installation was removed; later Local cases and HTTP were not reached.

No grammar, wire, schema, numeric law, saved-data format or version changes.
Previously rejected valid sources obtain an ordinary Program and its normal
identity. Full Core, all targets, native, proof and performance checks are not
local prerequisites for this bounded Frontend repair; required CI remains
separate from these focused results.
