# Grouped COUNTIF DISTINCT: common conditional/count connection

Date: 2026-10-08. Owner: B. Base: `e3d56c9882a490a8a419e3fcf77c79c0d8954349`.
Status: focused syntax/lowering/checker verified; packed public execution pending.

## Selected contract and pre-change counterexample

Pinned GoogleSQL: `d82db99a923a46571f543a13899dc791a7b6f743`.
`googlesql/compliance/testdata/aggregation_distinct_queries.test` has the
independent `aggregation_distinct_countif_1` through `_4`: repeated positive
observations yield one; all-NULL and empty inputs yield zero. Grouping cases
apply the same rule independently per group. `docs/aggregate_functions.md`
permits the DISTINCT spelling and notes its limited usefulness. This is
selected reference evidence, not a live Google service differential test.

The parser prohibited DISTINCT COUNTIF. The ordinary common COUNT_IF checker
also does not admit its DISTINCT modifier. Discarding DISTINCT would change
three TRUE observations from the expected one to three.

The independent complete expected Program instead uses common COUNT with
`distinct: true` and `IF(authored_predicate, TRUE, NULL)`. It passed the ordinary
checker before the red text parse failure. The Boolean condition is demanded
once; FALSE and NULL yield a typed nullable Boolean NULL and do not count.
Neither predicate copying nor input deduplication is required. The existing
expression, aggregate filter, DISTINCT comparison and count owners execute the
Program; no alternate evaluator, type system or admission path is added.

## Obligations and fixture

- Complete SQL and Pipe lowering equals the independent JSON Program and passes
  the ordinary checker, rather than only matching the other text form.
- The public fixture has an independent JSON control. Input occurrences
  `[1,1,3,NULL,-2]` after the Source predicate yield distinct TRUE count one,
  ordinary TRUE count three, COUNT five and SUM three. An input deduplication
  or dropped DISTINCT modifier fails this expectation.
- Twelve positive cases cover quoted/qualified predicates, per-call WHERE,
  GROUP/HAVING/ORDER/LIMIT/OFFSET, no-TRUE, all-NULL, typed empty, parameters,
  TRUE/FALSE/NULL literals and a guarded divide-by-zero predicate.
- Eight refusals cover star/missing/extra operands, undeclared parameters and
  columns, a non-Boolean predicate, JSON null and the unsupported default
  DISTINCT analytic profile. Run admission/provider I/O must remain zero.
- Cases are registered in ordinary and narrow packed acceptance. Named Result
  rows and declared column order/type/nullability, Result.describe, source
  acquisition counts, resend identity and repeat reads use the existing harness.

## Executed focused evidence

Red: one test failed at the original parser prohibition after checking the
independent expected Program (`run-zpUULv`, `focused-test-aLjmkZ`):

```sh
node scripts/local-checks.mjs test moon -- --target js src/query_program/countif_distinct_test.mbt
```

The same initial test passed after the two local connections (`run-de9Qki`,
`focused-test-wuMpVr`). The final focused JS selection executed 39/39
(`run-AcXCYd`, `focused-test-Yv6p62`):

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/query_program/countif_distinct_test.mbt src/query_syntax/countif_distinct_test.mbt \
  src/query_program/aggregate_filter_scope_test.mbt src/query_program/aggregate_filter_test.mbt \
  src/query_program/quoted_aggregate_test.mbt src/query_syntax/quoted_aggregate_test.mbt \
  src/query_program/pipe_aggregate_expression_test.mbt src/query_program/order_aggregate_expression_test.mbt \
  src/query_program/analytic_countif_test.mbt src/run_publication_host/client_values_run_materials_wbtest.mbt
```

Focused Node executed 21/21 (`run-z6KcMc`, `focused-test-7dFhfB`):

```sh
node scripts/local-checks.mjs test node -- scripts/countif-distinct-source-input.test.mjs \
  scripts/public-query-profiles.test.mjs scripts/client-values-run-materials-vector.test.mjs \
  scripts/compilation-manifests.test.mjs
```

The independent Values Program and source lowering pass the ordinary checker;
the Node checks protect public fixture/registration expectations. Ordinary
analytic COUNTIF is covered by its focused JS caller tests. The public JSON
control and source fixtures have not been executed: these checks do not
establish runtime acceptance.

## Identity and remaining boundaries

Normative query-text changes are generated through compilation-manifests,
document metadata, spec-family and canonical vector generators. Grammar:
`sha256:8067b40c487a905f89d3c4fb66d6d3deebe7fc9d5e3f52649e2db64465cf91e2`.
Independent Values Run:
`sha256:c6ac1828f0e78900aba0ef156f9823ae26917f64ffb6802ceeeb87cb645f2000`.
The old complete grammar/Run preimage remains a separate historical assertion;
no stored Run is rebound. Unit/ResultPlan and barrier meanings are unchanged.

Distinct analytic COUNTIF is explicitly refused: default/unordered windows are
not added, and an authored ROWS frame must not be accepted by changing/removing
DISTINCT. Aggregate HAVING MAX/MIN, new scalar types, full Core, native/Wasm,
Cloud and live Google comparison are not established here.

The existing shared-heavy-slot owner must be verified/released before normal
five-package Local/HTTPS execution. Preserve other owners' locks and report
this public execution separately from focused lowering success. This independent
main-based branch does not adopt #1016; its MIN/MAX DISTINCT parser restriction
remains that separate PR's work. When either branch reaches main, preserve both
connections and regenerate the combined normative pins from the actual sources.
