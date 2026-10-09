# Ordinary aggregate inputs in inline OVER keys

## Scope and reference

This Frontend unit connects ordinary aggregates in inline window partition and
ordering expressions to the existing GROUP -> ANALYTIC Program. It introduces
no execution owner, aggregate implementation, capacity adjustment or Result
publication exception. The adopted main baseline is
`ef37a30df1bf63379be93dffdf9e2cfcad78ffd1`.

The selected [GoogleSQL window call rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/window-function-calls)
place ordinary aggregation before window evaluation and permit aggregates as
window inputs. SELECT-owned arguments and OVER keys cannot use sibling SELECT
aliases, and a window cannot consume another window. This is an existing
semantic connection, not a new scoring, grouping or window law. The structural
grammar already admits expressions in partition and ordering keys; common
Program bodies, schema pins and their existing identities are unchanged.

## Pre-fix counterexample

```sql
SELECT t.x,
       ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC, t.x) AS rn
FROM t
GROUP BY t.x
ORDER BY rn
```

With rows `(x,y) = (1,20), (1,21), (2,10)`, independently expected rows are
`[{"x":1,"rn":1},{"x":2,"rn":2}]`. GROUP has count 2 for key 1 and count 1
for key 2; ANALYTIC ranks descending count with the grouped key as a tie key.
Only x and rn are public, in that order. The complete expected Program was
authored directly in `window_group_aggregate_inputs_test.mbt`.

Before the fix, the independent Program checked but source parsing failed:
focused JS run `run-XVYJnM` / `focused-test-wFJH9S`, 1 passed and 1 failed.
The first attempted filename filter discovered zero tests and is not evidence
of a passing check. After the parser connection, an exact comparison exposed a
projection/sort layout difference; the oracle layout was corrected to the
existing selected-output ORDER placement without changing any value, ordering
term, count or public field.

## Change and ownership

- Inline OVER uses the existing bounded aggregate-expression extractor, and
  appends ordinary calls to its owning SELECT, QUALIFY or query ORDER call list.
- A whole SELECT window keeps its ordinary analytic output rather than creating
  an unnecessary scalar projection. Extracted aggregate slots remain private.
- The grouped window resolver uses retained input bindings and parser-owned
  aggregate references. When GROUP reuses a SELECT aggregate's evaluated slot,
  the window reads that slot without reevaluation or exposing sibling aliases.
- Ordinary Pipe SELECT still does not insert an implicit aggregate stage.
  Existing nested-window rejection, argument checking and all capacity limits
  remain in their original owners.

No D-owned CTE/assert/Effect, A-owned evaluator, or C-owned Graph code changes.
No shared Owner dependency is required for this inline-key unit.

## Independent checks and public boundary

Focused JS selection: the new complete Program comparison, COUNT/SUM keys,
computed keys, aggregate partitioning, SELECT/QUALIFY/query ORDER ownership,
global grouping, aggregate-slot reuse, sibling-alias rejection and nested-window
rejection, plus existing named-window, scalar-window, grouped-clause and ORDER
window callers: **38/38**, `run-gyhDHp` / `focused-test-rYKvGx`.

Fixture checks: **4/4**, `run-4kcCjh` / `focused-test-d97z7w`.
Commands use the pinned Node/MoonBit environment and existing bounded wrappers:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_program/window_group_aggregate_inputs_test.mbt \
  src/query_program/qualify_group_aggregate_slots_test.mbt \
  src/query_program/window_scalar_projection_test.mbt \
  src/query_program/analytic_order_expression_test.mbt \
  src/query_program/named_window_test.mbt \
  src/query_program/order_window_expression_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  scripts/qualify-source-input.test.mjs
```

The existing ordinary and narrow packed QUALIFY consumers both include the new
fixtures. One independent JSON control and eight source cases compare ordered
rows and Result.describe column contracts. COUNT(nullable amount) deliberately
changes the expected ranking; duplicate source rows affect COUNT, while empty
input retains typed columns. Existing source acquisition, reread/attach/resend
checks and pre-admission refusal counters remain unchanged.

Fresh exact-source five-package Local/HTTPS acceptance is pending. Target CI,
Wasm/Native execution, full Core, full packed suites, proof and performance
campaigns have not been run for this change. No live Google service comparison
is claimed.

## Remaining Frontend work

This unit does not establish aggregate extraction in WINDOW declarations or
window function arguments such as `LAG(SUM(x))` / `SUM(SUM(x)) OVER (...)`.
These remain separate Frontend connections to investigate and close, using the
same existing GROUP/ANALYTIC contracts. The ordinary named-window regression
selection above is preservation evidence, not execution evidence for aggregates
in those declarations. This PR is not a claim of complete window coverage or
completion of the overall text-to-Program goal.
