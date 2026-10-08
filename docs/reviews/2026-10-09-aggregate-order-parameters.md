# Aggregate-local ORDER parameter connection

Inspected main: `b693899a4c15e0cd30ba638d11a626556e30f141`.
Stacked Frontend dependency: #1023 at
`f952bcb06a87ba68314e8f928866aa2818d0246d`, retaining #1022's resolved
DISTINCT receiver checks. Final destination is main after those parents land.

## Independent discrepancy

```sql
SELECT STRING_AGG(name, '|' ORDER BY @key DESC NULLS LAST, id) AS names
FROM objects
```

The parser accepts this expression but `aggregate_order_fields` rejected its
ParameterReference receiver. An independently authored complete Values Program
derives `{$param:"key"}` into a private column and passes normal checking with
both a number and SQL NULL. A nullable closed object parameter projected through
the existing `property` expression also passes with a number, nullable member
or NULL receiver. Source counterparts failed **1/2** before repair
(`run-9Lbspr` / `focused-test-hevZI2`); no pre-repair public execution is claimed.

The selected GoogleSQL analyzer reference is
`d82db99a923a46571f543a13899dc791a7b6f743`:
`resolver_expr.cc` resolves aggregate order expressions then refuses ordinals;
`resolver_query.cc` distinguishes untyped literal ordinals from ordinary resolved
expressions. Parameters remain expressions, not integer ORDER positions.
DISTINCT still requires the ordering expression to match its aggregate argument.
This is source inspection, not a live Google service differential execution.

## Existing owner connection

Admit a ParameterReference root in static Property/Parenthesized receiver chains
and delegate the original AST to `append_with_properties`. Keep the existing
parameter name resolver, declaration/value checker, NULL/member typing, work
budget, private slot allocator, collection limits and normal execution owner.
Parameters never resolve through an input-column name. No literal inference,
SQL interpolation, arbitrary expression hoisting or alternative execution path
is introduced. Broader computed aggregate ordering remains a separate gap.

The public collision has input string `name` and numeric parameter `name`.
`ORDER BY @NAME DESC NULLS LAST, id` concatenates `z|a|a|m`; incorrectly ordering
the input name would yield `z|m|a|a`. The authored Source predicate `id > 0`,
duplicates, nullable argument, FILTER and secondary order are retained.
Independent JSON controls use the same ordinary value/property/group contracts.
DISTINCT on one parameter is checked and tested separately from refusing an
ordering parameter that differs from the input argument.

## Focused verification

After the initial receiver repair, the two independent control/source tests
passed **2/2** (`run-qogWAL` / `focused-test-d0YGSp`). Expanded tests first passed
**36/37** (`run-GOtjXB` / `focused-test-byAM1y`): one test incorrectly expected
Rejected for a missing value. Existing parameter binding instead returns
NeedsInputs; the test now fixes that outcome, without changing the product.
The public preparation still refuses missing input before Run admission/I/O.

Final focused JS: **37/37**, `run-473s3G` / `focused-test-kwS4Dq`.
Fixture/profile/manifest Node: **24/24**, `run-c0s89e` / `focused-test-dHQEMn`.
Read-only compilation-manifest and catalog dependency-pin validation passed.
There is no grammar, schema or normative pin change in this connection.

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/query_program/aggregate_order_parameter_test.mbt \
  src/query_program/aggregate_property_order_test.mbt \
  src/query_program/distinct_aggregate_order_test.mbt \
  src/query_program/parameter_reference_case_test.mbt \
  src/query_program/aggregate_filter_test.mbt \
  src/query_program/aggregate_filter_scope_test.mbt
node scripts/local-checks.mjs test node -- \
  scripts/aggregate-order-parameter-source-input.test.mjs \
  scripts/aggregate-property-order-source-input.test.mjs \
  scripts/public-query-profiles.test.mjs scripts/compilation-manifests.test.mjs
```

## Public obligations and remaining scope

The existing normal and selected aggregate-property-order packed corpus now
contains **37 normal, 20 refusal and one expected execution-failure case per
Embedded Local/HTTPS**. This includes **13 new normal and ten new refusal cases**.
All previous expectations are retained. The new cases cover scalar/object/NULL
parameters, quoting/case, input-name collision, FILTER, duplicate/empty input,
and DISTINCT. Rejections cover undeclared/missing/wrong values, declaration
ambiguity, missing/non-object members, non-orderable objects, mismatched
DISTINCT argument and numeric ordinal. Existing harness checks ordered contracts,
Result.describe, private-column exclusion, one Source session, same-request
resend/repeated reads without reacquisition, and admission/I/O counters.

Exact-HEAD normal five-package production and public execution are pending at
this evidence commit. The PR body must record actual post-commit evidence and
digest correspondence. Focused checks do not establish public execution or CI.
Full Core/Native/Wasm/Cloud and the remaining Frontend coverage gaps remain
unverified. No manual CI rerun or merge is authorized by this completion unit.
