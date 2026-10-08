# Window calls as SELECT expression operands

Owner: B. Base main: `63cb4ea82aaf4269e73c7a412011c980a722a407`.
This is a Frontend connection to existing analytic and expression operations.

## Selected contract and pre-fix counterexample

The selected [GoogleSQL window-call rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/window-function-calls)
allow a window call as an operand in a SELECT expression. The call arguments,
OVER keys and sibling SELECT expressions see the input snapshot, rather than
aliases introduced by that SELECT. Windows run after grouping and before the
result scalar projection. Nested windows remain disallowed.

The common Program already represents analytic computation followed by derive
and select. The independently written complete Values Program in
`src/query_program/window_scalar_projection_test.mbt` passes the ordinary
checker. The corresponding source failed to parse before this connection:

```sql
SELECT id, ROW_NUMBER() OVER (ORDER BY id) + 1 AS pos
FROM orders
ORDER BY id
```

Pre-fix focused execution: 1/2, `run-8pt6H6` /
`focused-test-YVw1RU`. This establishes a compiler gap; it does not claim a
pre-fix accepted public Run or backend misexecution.

## Connection and scope

- SELECT uses the bounded primary callback already used by QUALIFY, with
  the same token stream, expression/syntax/work accounting and source spans.
  Whole window and aggregate projections retain their existing representations.
  Embedded non-window aggregates retain their existing private-name prefix.
- `AnalyticExpressions` carries explicit Frontend-only private output bindings.
  It lowers through the same analytic branch as an ordinary window projection.
  It is not a new Program operation, execution stage, Owner or wire format.
- Private call names avoid every authored identifier using the existing
  bounded name allocator. A colliding input field gets a distinct physical
  output slot. The original SELECT input snapshot stays intact for call
  arguments, keys, ordinary references and star expansion.
- Only post-window scalar projections and their existing QUALIFY alias-demand
  path resolve private call operands. SELECT siblings cannot read newly
  declared aliases. Pipe materialization clears those private bindings.
- All scalar typing, NULL propagation, conditional demand, analytic frames,
  capacity, ordering and failures remain common checker/execution obligations.
  No default frame, new function signature, stronger key or order evidence is
  invented. Hidden slots are removed by ordinary final select.

The generated query_syntax interface was refreshed with the pinned generator
for that package on JS/Wasm/Native. The common Program, law bodies, selected
generic expression/OVER grammar and their pins are unchanged. This connects
an already selected expression placement; it does not assert complete window
function coverage or backend conformance.

A caller test retained an obsolete negative for Pipe
`AGGREGATE COUNT(*) + 1 AS n`. Base main already parses that operation using
aggregate-expression extraction. The test now checks this positive and keeps
the unsupported ordinary Pipe `SELECT COUNT(*) + 1 AS n` as a negative.
No Pipe AGGREGATE implementation was added or changed for that correction.

## Independent public acceptance obligations

`scripts/fixtures/window-scalar-source-input.mjs` contains the independent
JSON control, complete ordered type contracts and manually determined rows.
The Source input is deliberately out of order and includes NULL and duplicate
amounts. Window order differs from final Result order.

- Twelve normal cases: JSON control, SQL/Pipe arithmetic and a parameter,
  LIMIT/OFFSET, multiple distinct windows, named-window CASE, evaluated alias
  demand in QUALIFY, nullable LAG, grouping before a window, an authored column
  resembling a private name, DISTINCT window values, and typed empty input.
- Seven preparation refusals: invalid ranking arity, undeclared/unused parameter,
  sibling window input, removed range alias, nested window and operand type.
  Refusal requires zero durable Run admission and provider I/O. Invalid ranking
  arity retains the existing `ClientProgramInvalidInput` category.
- One demanded arithmetic failure must publish no readable/describable Result.
- The existing driver checks Named Result rows, full Result.describe contracts,
  column order and hidden-column absence. It checks one acquisition session and
  no extra acquisition/admission on reread, attach or same-request resubmission.

These cases are registered in ordinary packed acceptance.
`--window-scalar-only` selects this cohort for bounded Local/HTTPS verification;
it does not replace the normal registration or bypass pristine package checks.

The first pristine package attempt at `6bb1835715fab4b9be94e21455b438fe1b709351`
passed the JSON control and three parameterized Local cases, then rejected the
multiple-window case before admission. Evidence: `public-query-evidence-UzFvWN`.
A focused preparation diagnostic (`run-zCfnWF`) identified
`PreparedReferencesIssue::Usage(UnusedParameter("increment"))`: the fixture
helper had attached a parameter declaration to cases that did not use it.
Those cases now omit the unused declaration and value; rows, column contracts,
ordering and ceilings are unchanged. The same unused declaration is retained
as an explicit preparation refusal. HTTPS and later cases were not reached by
that first attempt. No checker rule was relaxed for this fixture correction.

## Focused evidence and exact-SHA execution

Working-tree JS: 32/32, `run-6zFnqB` / `focused-test-uPnnpe`:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- --target js \
  src/query_program/window_scalar_projection_test.mbt \
  src/query_syntax/window_scalar_projection_test.mbt \
  src/query_program/analytic_countif_test.mbt \
  src/query_program/select_aggregate_expression_test.mbt \
  src/query_program/named_window_test.mbt \
  src/query_program/qualify_test.mbt \
  src/query_program/quoted_qualify_test.mbt \
  src/query_syntax/select_aggregate_expression_test.mbt
```

Working-tree Node: 4/4, `run-e7axUz` / `focused-test-u37OnR`:

```sh
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  scripts/window-scalar-source-input.test.mjs \
  scripts/analytic-countif-source-input.test.mjs
```

After the parameter fixture correction, the same Node selection passed 4/4
again (`run-9d182a` / `focused-test-oclcnB`). A read-only preparation probe
using the existing built bridge and the unchanged installed analytic profile
accepted all eleven SQL/Pipe normal sources (`run-KOGU32`). This probe is
checker evidence, not public execution or pristine new-SHA package acceptance.

Affected interface generation: `run-P54cs9`,
`moon info --target js,wasm,native src/query_syntax`; no divergent interface was
reported. This is interface generation, not cross-target execution acceptance.

Final clean-SHA five-package identities, Local/HTTPS results and evidence paths
are recorded externally and in the PR body after execution, separately from
the working-tree checks. Local success is not CI success. No full Core, complete
packed corpus, Wasm/Native execution, Cloud or live Google-service differential
test is required or claimed by these focused checks. Window calls directly in
final ORDER, broader signatures/default frames and outstanding common predicate
contracts remain separate coverage gaps. D's CTE/Effect/capture, A's execution
and C's Graph ownership are not changed by this unit.
