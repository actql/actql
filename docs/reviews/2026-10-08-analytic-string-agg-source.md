# Analytic STRING_AGG source connection

Owner: B. Base main: `e6ab970ae18eb34ac76dfc2ef4b917f1112fa8f1`.
Scope: the existing STRING aggregate in explicit inline ROWS windows.

## Contract and pre-fix counterexample

[GoogleSQL STRING_AGG](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/aggregate_functions#string_agg)
concatenates non-NULL values, retains duplicate occurrences and returns NULL
for an empty or all-NULL frame. The default delimiter is a comma. With OVER,
the call uses window ordering; aggregate-local modifiers are forbidden.
This connection implements the STRING overload and existing explicit ROWS
profile, without adding default RANGE frames, BYTES, coercion or collation.
The pinned GoogleSQL reference is `d82db99a923a46571f543a13899dc791a7b6f743`;
its aggregate-functions reference supplies the same selected rules.

Common analytic typing, preparation and execution already support `string_agg`:
`src/relation_typing/analytic_test.mbt`,
`src/lowering_relation/analytic.mbt` and
`src/execution_relation/analytic_rows_wbtest.mbt` cover that contract.
The ordinary checker accepts the independent complete Values Program in
`src/query_program/analytic_string_agg_test.mbt`. Before the fix, the matching
SQL and Pipe fail in parsing because collection calls unconditionally demand
aggregate-local ORDER BY. Analytic lowering also omits STRING_AGG and passes
zero collection ceilings. The pre-fix focused run is 1/2:
`_build/local-checks/attempts/run-pfuOEq`,
`_build/focused-evidence/focused-test-IaDV7e`.
This is a compiler counterexample, not a pre-fix public Run observation.

## Connection

The existing aggregate parser permits an omitted call-local order immediately
before unquoted OVER. Ordinary collection calls retain the existing explicit
order profile. Window STRING_AGG reuses `lower_aggregate_resolved`, carrying
the caller's existing collection byte ceiling and omitting the prohibited
call-local `order_by` field. It preserves argument expressions, parameters,
decoded delimiter values, input scope and the authored window/frame.
No common evaluator, checker, resource limit, Owner, wire or storage changes.

Aggregate-local DISTINCT, WHERE and ORDER BY are refused as
`UnsupportedAnalytic` for window STRING_AGG. Existing unsupported missing
frames remain explicitly refused. Argument types and value-slot evidence
remain common-checker responsibilities. Syntax acceptance alone is not
execution support for ARRAY_AGG or other broader window shapes.
The normative generic expression/OVER grammar already admits these calls;
this implementation completion does not change normative bodies or pins.

## Independent public acceptance obligations

`scripts/fixtures/analytic-string-agg-source-input.mjs` contains a complete
independent JSON control and authored source cases. Input is deliberately
out of order, with duplicate non-NULL values, NULLs and an excluded sentinel.
Expected values, nullable String contract and column order are not derived
from compiler or runtime output.

- Nine normal cases cover JSON, SQL, LIMIT/OFFSET, Pipe following frames with
  empty tails, duplicate-valued partitions, quoted calls/default comma,
  a Pipe input snapshot, typed empty input and all-NULL input.
- Eight static refusals cover wrong argument type, three forbidden modifiers,
  missing frame, undeclared parameter, sibling alias and removed old alias.
  The existing public harness requires zero admission and provider I/O.
- A demanded expression error must not publish a readable/describable Result.
- Existing acceptance checks Result.describe contracts, column order, rows,
  private-column absence, one acquisition session and no additional acquisition
  or admission on reread, attach or resubmission.
- All cases join ordinary packed acceptance. `--analytic-string-agg-only`
  selects this complete cohort for Local/HTTPS without unrelated campaigns.

Focused working-tree results and clean-SHA package evidence are recorded
separately in the PR body. Full Core, the complete packed corpus, Wasm/Native,
Cloud and live Google-service differential execution are not claimed here.
Other common predicate/default-frame and CTE dependencies remain separate.

## Focused working-tree evidence

With the pinned Node/MoonBit toolchain, both commands completed before commit:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- --target js \
  src/query_program/analytic_string_agg_test.mbt \
  src/query_syntax/analytic_string_agg_test.mbt \
  src/query_program/analytic_countif_test.mbt \
  src/query_program/string_agg_default_delimiter_test.mbt \
  src/query_syntax/string_agg_delimiter_test.mbt \
  src/query_program/analytic_order_expression_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  scripts/analytic-string-agg-source-input.test.mjs \
  scripts/analytic-countif-source-input.test.mjs
```

JS: 24/24, guard `run-Z1UUvB`, focused receipt `focused-test-Kh8paB`.
Node: 4/4, guard `run-hYDfnc`, focused receipt `focused-test-H37ouY`.
Receipts are below this worktree's `_build/local-checks/attempts` and
`_build/focused-evidence`. Formatting and `git diff --check` passed.
These are working-tree checks, not submitted-SHA CI or packed execution.

The first clean-SHA packed attempt used
`9422cacaf9f42aa3995112cdcd672d75d0fbc999` and a normal five-package producer:
guard `run-gctFfS`, external evidence `public-query-evidence-EHARMp`.
Local's nine normal cases and demanded execution error passed. The subsequent
refusal loop stopped because the generic fixture code set did not include
the existing `UnsupportedAnalytic` public projection,
`ClientProgramImplementationLimit`. HTTPS was not reached. The fixture now
explicitly expects that code for the three forbidden modifiers and missing
frame, independently pinned by the Frontend refusal tests. No generic allowed
code set, product refusal or normal expected value is changed. Final acceptance
uses the amended clean SHA and its own normal package manifest; this partial
older-SHA evidence is not presented as final completion.
The amended fixture/registration Node selection passed 4/4:
`run-e5hfbv`, `focused-test-0hjuSu`. MoonBit product/test sources are unchanged
from the 24/24 JS selection above.
