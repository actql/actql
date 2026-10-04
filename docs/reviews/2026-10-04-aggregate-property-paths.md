# Nullable object paths in aggregate arguments

## Baseline and existing contract

This independent repair starts at main
`44e07a2de522d4dfc6d7924d4672e88d237aa6e3`. It does not depend on the
pending ORDER property or grouped SELECT/HAVING repairs.

The existing [group contract](../spec/language.md) accepts a row-local
`expr` instead of a direct `field`. Its owner evaluates that expression, excludes
NULL before DISTINCT and folding, and supplies the declared aggregate output
contract. COUNT counts non-NULL values; COUNTIF counts true values. SUM/AVG
retain their numeric observation requirements. An empty global group returns
one row: COUNT is zero, while SUM/AVG/MIN are NULL. The selected
[query scope](../spec/query-text.md#scope-and-lowering) resolves SELECT arguments
against the input snapshot and keeps current Pipe columns separate from an
older range alias. The limited OVER aggregate calls share this argument boundary.

Google's [aggregate reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/aggregate_functions#count)
also distinguishes COUNT(expr), DISTINCT and COUNTIF. No Google service
differential execution was performed. This unit connects the existing selected
profile and common object contract; it does not adopt additional aggregate
clauses or claim full GoogleSQL STRUCT coverage.

## Counterexample and minimal repair

Two new tests fail on the baseline (**0/2**, `run-NqcOs9`,
`focused-test-et877z`):

```sql
SELECT COUNT(payload.score) AS n, MIN(objects.payload.score) AS m FROM objects;
FROM objects AS before
|> AGGREGATE COUNT(before.payload.score) AS n, MIN(payload.score) AS m
|> SELECT n, m;
```

`lower_aggregate_resolved` treated every reference as a direct column. A dotted
property argument therefore failed before reaching the existing common `expr`
path. Computed aggregate arguments also used the scalar-only append entry.

The repair preserves the direct-field path for a completely resolved column.
Other arguments use `append_with_properties`, with the same bounded prefix
resolution and common property expression as ordinary projections. The argument
stays inside the aggregate; no preceding derive or independent evaluator changes
its evaluation position. Common typing rejects a missing field, scalar receiver
or non-boolean COUNTIF. A displaced Pipe range remains inaccessible.

There are no checker, planner, provider, Host, wire, grammar, schema, numeric-law
or saved-data changes. Previously rejected valid text receives an ordinary
Program and its normal identity. CTE/assert/Effect assembly is untouched.

## Independent expectations

The fixture defines these six typed rows independently of the lowerer:

| ID | Bucket | Nullable payload score | Other score |
|---|---|---|---|
| 2 | A | 10 | 100 |
| 1 | A | 20 | 200 |
| 3 | A | NULL receiver | 300 |
| 5 | A | 20 | 400 |
| 6 | A | 30 | 500 |
| 4 | B | NULL field | 600 |

For bucket A, COUNT is 4, COUNT DISTINCT is 3, COUNTIF(score >= 20) is 3,
SUM is 80, AVG is 20, MIN is 10 and MAX is 30. Bucket B has zero counts
and NULL folds. Thus nullable receivers, nullable fields and duplicate values
are observable separately. After Pipe SET replaces payload with other, the
current receiver has count 6 while the prior range retains count 4. A SELECT
sibling alias named payload does not change another argument's input receiver.

The [MoonBit tests](../../src/query_program/aggregate_property_paths_test.mbt)
include a complete handwritten expected Program, check both Programs with the
ordinary checker, and compare canonical Program semantics. They also retain
numeric evidence requirements, explicit OVER frame, scope refusals, resource
work limits and original source diagnostics.

The [public fixtures](../../scripts/fixtures/aggregate-property-source-input.mjs)
contain **eight positives and four preparation refusals**. A complete handwritten
JSON control and SQL/Pipe sources use the same independently specified rows,
types and expected results. Authored text uses ordinary DATA, parameter
declarations and values; the harness never patches a lowered Program or supplies
a substitute checker. Expected column order and nullability are explicit.
The cases are registered in the normal packed corpus as well as its focused
selection. Common limited OVER argument handling has a separate public case.

## Executed and pending evidence

- Focused JS aggregate selection: **12/12** (`run-LarSIj`,
  `focused-test-HVSv0m`), comprising eight new and four existing tests.
- Affected existing analytic callers: **3/3** (`run-56Pnht`,
  `focused-test-9OjQQP`). These counts are separate selections, not a claimed
  combined coverage of all aggregate or analytic behavior.
- Changed MoonBit formatting, three JavaScript syntax checks and diff checks
  pass. An initial test helper failed to compile before baseline reproduction;
  it was corrected and is not counted as a successful test execution.
- Fresh packed Embedded Local/authenticated HTTP acceptance is pending. The
  selected command is `node scripts/test-packed-public-query.mjs
  --aggregate-property-only`, using normal prepack and pinned toolchains.
  It must compare Named Result values and complete ordered column contracts,
  stream completion, same-Run resubmit/attach, hidden-column exclusion and zero
  Source reads. Refusals must have zero Run admission and provider I/O.
- Submitted-HEAD required CI is separate and pending. Full Core, all targets,
  proof, native and performance campaigns are not local checks for this unit.

This does not close nested GROUP keys, HAVING property paths, non-aggregate
analytic arguments, collection-specific argument ordering or the whole Frontend.
