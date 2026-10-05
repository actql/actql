# HAVING object properties through the common expression lowerer

## Counterexample and existing meaning

At main `64046e37a1cadb2148edeab7cbf85b96d125b518`, the source below
parses but lowering rejects the visible object alias with `UnknownReference`:

```sql
SELECT x, @assessment AS assessment, COUNT(*) AS n
FROM t
GROUP BY x
HAVING assessment.score > 10
ORDER BY x
```

`assessment` has the existing nullable closed-object parameter contract with
a nullable numeric `score`. An independently written complete Values / Group /
derive / property / filter / SELECT / sort Program passes the ordinary checker
before the source probe. Pre-fix gate `run-xevb5o` executes that ordering and then
fails source compilation (0/1). An earlier attempt with the incorrect author
key `parameters` instead of the existing `params` never established this probe
and is excluded. Private-slot numbering and UTF-16 span assertions were corrected
against the existing naming rule and the authored source; no expected rows,
types, predicate or order were changed to match product results.

The adopted [SELECT/HAVING alias scope](../spec/query-text.md#scope-and-lowering)
and common [typed access](../spec/language.md#typed-access) already express this
case. Google's [field access operator](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/operators#field_access_operator)
provides the selected STRUCT field-access meaning. This connection does not
claim general JSON or GRAPH_ELEMENT access, a new object type, or full GoogleSQL
compatibility.

## Connection and responsibility

`compile_steps` already resolves the HAVING receiver against its grouped scope,
derives a selected computed alias once, and shares that physical slot with SELECT.
Its predicate alone called the exact-reference expression lowerer. It now calls
`append_with_properties`, the same bounded prefix resolver used by the other
object-bearing query clauses. Longest valid column/range prefix resolution and
ordinary common property nodes remain unchanged.

The common checker owns field presence, receiver type and nullability; common
expression evaluation owns NULL propagation and demanded failures. This change
does not restore ungrouped inputs, expose old aliases, expand the selected
expression per reference, invent field-presence evidence, or bypass checking.
No grammar, AST, common contract, pin, execution Owner, Model/Effect storage,
capacity or serialization format changes are needed.

## Independent acceptance

The authored fixture uses an acquired numeric Relation with unsorted rows,
a duplicate ID, nullable input data, and a filtered-out row. The selected object
comes from a CASE over the grouped ID and typed parameters. HAVING must retain IDs
1 and 3 with counts 1 and 2. Its independent JSON control retains exactly the
predicate, CASE arguments, common Group and ordered output.

The bounded public corpus covers:

- Computed aliases, nested/quoted properties and a subsequent Pipe projection.
- NULL receivers, NULL fields, and empty input with the same checked schema.
- An object alias named `id` colliding with the numeric input: `id.score` and
  `records.id` retain different meanings and select different expected rows.
- Unknown property, non-object receiver, qualified nonexistent alias and removed
  ungrouped receiver rejection before Run admission/provider I/O.
- A demanded division failure: no readable or describable successful Result.

Use the existing normal five-package producer and the existing packed public
acceptance application; no test-side Program corrections or separate Host path:

```sh
node scripts/local-checks.mjs test moon -- --target js src/query_program --filter '*HAVING*'
node scripts/local-checks.mjs test node -- scripts/having-object-property-source-input.test.mjs scripts/public-query-profiles.test.mjs
node scripts/packed-client-packages.mjs <outside-checkout-directory>
ACTQL_PACKED_CLIENT_PACKAGES=<outside-checkout-directory> node scripts/test-packed-public-query.mjs --having-object-property-only
```

The cases also join the ordinary packed corpus. Named Result rows, declared
column order and complete Result.describe contracts are independent expectations,
including nested nullability and the existing closed-object expansion. The shared
harness checks one Source acquisition, same-Run resend/attach/read without extra
admission or I/O, and internal-column absence through exact rows/columns.

Working-tree HAVING callers passed 13/13 (`run-g7KbGQ`), and fixture/profile Node
checks passed 9/9 (`run-xtZnb5`). These are not a substitute for the subsequent
clean-SHA distribution evidence recorded in the PR. Full Core, Wasm/Native
execution, proof/performance, Cloud and hosted required CI remain separate.

D's cancellation, Model-wire and CTE/assert/Effect work; H's Effect value/hook
and Ledger work; A's expression progress/retention; and C's Graph contracts are
outside this unit. The final merge target is main; no sibling aggregate PR is
required for this existing HAVING projection connection.
