# DISTINCT analytic clauses: preserve the selected SQL boundary

Date: 2026-10-08. Owner: B. Base: `210e51e8986ca0aef427e4a4fb3259b749466037`.
Status: source/lowering and focused callers checked; pristine packed execution
will be recorded separately against the committed source and package manifest.

## Defect and selected contract

The text entry accepted COUNT/SUM/AVG with DISTINCT and an authored ordered
ROWS frame. These calls reached the ordinary analytic Program operation.
This is not a failure of the common machine operation: its available behavior
is broader than the selected SQL surface's permitted clauses.

Pinned GoogleSQL: `d82db99a923a46571f543a13899dc791a7b6f743`.
`googlesql/analyzer/analytic_function_resolver.cc` explicitly refuses window
ORDER BY and authored frames in the presence of DISTINCT. The independent
cases in `googlesql/analyzer/testdata/analytic_functions.test` cover both
clauses separately. A default/unordered DISTINCT call is a different, valid
reference form; blanket documentation saying all DISTINCT windows are invalid
would also be wrong.

The smallest counterexample is:

```sql
SELECT COUNT(DISTINCT amount)
  OVER (ORDER BY id ROWS BETWEEN CURRENT ROW AND CURRENT ROW) AS n
FROM orders
```

One shared check in `query_program/compile.mbt::lower_analytic_call` refuses
DISTINCT calls before constructing the explicit-ROWS common operation. It also
covers SQL/Pipe projection, named/inherited windows, scalar window expressions,
QUALIFY and ORDER window expressions. The existing `UnsupportedAnalytic` typed
projection is retained. No modifier/frame is removed or rewritten. No common
checker, aggregate, window, capacity, execution or publication owner changes.

The current common connection still requires ordering/frames. Valid
default/unordered DISTINCT windows remain an explicit incomplete connection,
separate from the invalid ordered/framed inputs fixed here. Machine JSON
Programs retain their existing checker and execution contracts.

## Independent expectations

The new MoonBit fixture compares ordinary COUNT/SUM/AVG SQL and Pipe with a
complete hand-authored Values Program and checks both actual and expected
Programs through the ordinary checker. Grouped COUNT/SUM/AVG retain all three
authored DISTINCT flags. Refusals assert the intended `UnsupportedAnalytic`
reason, not a generic error.

The public fixture contains a separately authored Source JSON control.
Input amounts NULL,2,2,8 after the Source predicate yield cumulative non-NULL
counts 0,1,2,3, sums NULL,2,4,12 and averages NULL,2,2,4. The grouped DISTINCT
control yields count 2, sum 10 and average 5. Empty input retains its declared
columns. Six normal and ten refusal cases are registered in the ordinary
packed corpus and `--analytic-distinct-frame-only` cohort. Nine refusals have
forbidden clauses; one deliberately tracks the valid default-profile gap.
The existing harness checks Named Result rows, ordered columns, complete types
and nullability, Result.describe, shared acquisition counts, resend identity,
repeat reads and zero Run admission/provider I/O for refusals.

## Executed checks

- Red: the original one-test refusal failed because COUNT with DISTINCT and an
  authored ordered frame compiled (`run-btnSLI`, `focused-test-eopksy`).
- Green: three directly changed JS tests passed (`run-yNRiyu`,
  `focused-test-WLJwnZ`).
- Caller selection: 26 of 27 JS tests passed; the sole failure was the old
  grammar-bound Values Run expectation after the normative clarification
  (`run-UGaOCQ`, `focused-test-imLdKd`). This failed attempt is retained.
- After independent preimage derivation, the four affected JS tests passed
  (`run-L3CaWY`, `focused-test-lZo3nO`). No product-issued CID supplied the new
  expectation. The other 26 observations are not relabeled as this final run.
- Focused Node: 21/21 passed (`run-FKRzYk`, `focused-test-xGy4ac`): public
  fixture registration, profile selection, independent Values Run preimages
  and compilation manifests.
- Read-only compilation-manifest/spec-family/canonical checks passed; 380
  canonical identities; conformance remains false. Changed MoonBit formatting
  and `git diff --check` passed.

Commands are `node scripts/local-checks.mjs test moon -- --target js` with
the new test plus analytic COUNTIF/STRING_AGG, named-window, ORDER-window,
statistical callers and Values Run tests; the final four-test selection used
only `src/query_program/analytic_distinct_frame_test.mbt` and
`src/run_publication_host/client_values_run_materials_wbtest.mbt`.
Node selection used `scripts/analytic-distinct-frame-source-input.test.mjs`,
`scripts/public-query-profiles.test.mjs`,
`scripts/client-values-run-materials-vector.test.mjs` and
`scripts/compilation-manifests.test.mjs`.

## Identity and remaining coverage

The existing generators synchronize the normative clarification, grammar,
document imports, spec family and canonical fixtures. Grammar manifest:
`sha256:45f35630a2ce2014080976f94214548ae07cc9ef86f005229e3a830bc816411f`.
Independent Values Run:
`sha256:7609abd9743fa5a382782196df757b5ccc7e7808249525ef7995051ea8292259`.
Keep the original complete grammar `440dfe0c...` / Run `64f4e124...` vector.
Unit, ResultPlan and barrier semantics remain unchanged; saved Runs are not
rebound. Parallel grouped extrema and COUNTIF DISTINCT PRs need their combined
normative pins regenerated at integration, preserving all three connections.

No full Core, Native/Wasm execution, Cloud, live Google differential test,
default/unordered DISTINCT implementation or required CI success is established
by the focused checks. Draft remains preparation, not merge verification.
