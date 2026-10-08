# Grouped MIN/MAX DISTINCT: existing Program connection

Date: 2026-10-08. Owner: B. Base: `5e297d6a8c4687dee8f4b6af00cf1d371e4d0e6d`.
Status: implementation and focused lowering verified; pristine packed Local/HTTPS acceptance pending.

## Contract and defect

The selected GoogleSQL reference is `d82db99a923a46571f543a13899dc791a7b6f743`.
Its independently authored `aggregation_12` and `aggregation_14` cases in
`googlesql/compliance/testdata/aggregation_queries.test` establish equal extrema
for regular and DISTINCT MIN/MAX, including empty input. This is selected
language-reference evidence, not a live BigQuery differential test.

The current parser explicitly prohibited DISTINCT MIN/MAX. Merely removing that
prohibition would still emit `distinct: true`, rejected by the existing common
aggregate checker (`relation_typing/aggregates.mbt`). Grouped extrema need no
separate deduplication. Preserve the flag in the query AST and omit only that
redundant Program modifier for grouped MIN/MAX. Keep operands, per-call filters,
parameters and grouping scope unchanged. SUM/COUNT in the same group still see
all input occurrences. No evaluator, provider, order proof or admission rule is
added or weakened.

## Independent obligations

- A complete hand-authored Values Program with ordinary MIN/MAX is compared with
  SQL and Pipe lowering; the independent Program and both actual Programs pass
  the ordinary checker.
- The public fixture contains an independent external-Source JSON Program and
  authored SQL/Pipe. Input occurrences `[1,1,3,NULL]` (after WHERE) give shifted
  extrema `2,4`, SUM `5`, COUNT `4`. Global deduplication would fail the latter.
- Per-call WHERE retains other aggregates' observations. Grouping, HAVING,
  ORDER/LIMIT/OFFSET, typed parameters, quoted calls, all-NULL, typed empty,
  COALESCE and FROM-less calls have explicit row and column contracts.
- Seven public refusals cover invalid operands, an undeclared parameter,
  incomparable JSON and unsupported default analytic DISTINCT. Refusal must
  leave Run admission and provider I/O at zero.
- Normal and narrow packed selections share the same cases. Row order, declared
  columns, nullability, Result.describe, source acquisition count, resend Run
  identity and repeat reads use the existing public acceptance checks.

## Executed evidence

Red: `node scripts/local-checks.mjs test moon -- --target js src/query_program/min_max_distinct_test.mbt`
failed its original one test at parser rejection (`run-RCkZkY`,
`focused-test-RDL9D2`). The expected Program passed checking first. This is not
an execution result or a demonstrated checker failure from an accepted source.

Green: the same first test passed before adding the larger fixture
(`run-RgJ7M3`, `focused-test-umiHJa`). The subsequently expanded two-file
selection executed 6/6 on JS (`run-46caMD`, `focused-test-WTwdn9`):

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/query_program/min_max_distinct_test.mbt \
  src/query_syntax/min_max_distinct_test.mbt
```

The final focused JS caller selection executed 36/36 (`run-iDhd5Q`,
`focused-test-uM5WqX`), including aggregate filter scope, quoted calls,
statistical aggregate controls, Pipe scalar aggregate expressions, ORDER
aggregate expressions and the independently derived Values Run identity.
The focused Node selection executed 24/24 (`run-engLNl`,
`focused-test-j3NxUW`): fixture registration, public profiles, independent
manifest/Run vectors and statistical fixture controls.

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/query_program/min_max_distinct_test.mbt src/query_syntax/min_max_distinct_test.mbt \
  src/query_program/aggregate_filter_scope_test.mbt src/query_program/statistical_aggregate_test.mbt \
  src/query_program/quoted_aggregate_test.mbt src/query_syntax/quoted_aggregate_test.mbt \
  src/query_program/pipe_aggregate_expression_test.mbt src/query_program/order_aggregate_expression_test.mbt \
  src/run_publication_host/client_values_run_materials_wbtest.mbt
node scripts/local-checks.mjs test node -- scripts/min-max-distinct-source-input.test.mjs \
  scripts/statistical-aggregate-source-input.test.mjs scripts/public-query-profiles.test.mjs \
  scripts/client-values-run-materials-vector.test.mjs scripts/compilation-manifests.test.mjs
```

## Identity and coverage

Updating the normative query text changes the grammar manifest and containing
Run identity. Rebuild generated manifests, document metadata, spec-family pins
and canonical vectors with their existing generators. Keep the previous full
Run preimage; derive the new expected Run from the independent Values oracle,
never a compiler/issuer result. Unit and ResultPlan semantics are unchanged.

This unit closes grouped extrema in existing comparable domains. It does not
add default/unordered analytic DISTINCT windows, COUNTIF DISTINCT, statistical
DISTINCT, collation, decimal or nonfinite values. In particular, do not accept
an authored analytic ORDER/frame by discarding DISTINCT: the selected reference
forbids that combination. Full Core, native/Wasm execution, live Google service
comparison and normal required CI are not established by these focused tests.

Generated grammar manifest: `sha256:63ff6bfc27444dcfefa9b2eac663907c405a58042d681e8afe458f69ddd9356e`.
Independent Values Run: `sha256:e40cd007bd1358901d5b312c0f8a9eb2ed3c16667aad81aeeeaa50b88a7d5d91`.
The previous grammar `440dfe0c...` and Run `64f4e124...` are retained as
complete independent predecessor preimages; no saved Run is rebound.
