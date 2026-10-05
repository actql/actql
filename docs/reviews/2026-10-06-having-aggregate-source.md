# HAVING aggregate source connection

Owner: B. Base main: `2072d88cfba407bebdb52168540aca5a6293bbb7`.
Scope: the existing grouped aggregate family inside a SQL HAVING predicate,
including SQL queries followed by an ordinary Pipe tail.

## Contract and pre-fix counterexample

[GoogleSQL HAVING](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#having_clause)
filters aggregated rows and permits aggregates that are absent from SELECT.
Only TRUE retains a group; FALSE and NULL discard it. The fixed GoogleSQL
source `d82db99a923a46571f543a13899dc791a7b6f743`,
`googlesql/analyzer/resolver_query.cc` around lines 5427–5445, also distinguishes
the post-group alias scope from the pre-group alias scope of HAVING aggregate
arguments. Both scopes give SELECT aliases precedence over unqualified input
names; qualified input references retain their range meaning.

On the base source, the complete independent JSON Program in
`src/query_program/having_aggregate_test.mbt` passes the normal checker. Parsing
`SELECT x FROM t GROUP BY x HAVING COUNT(*) > 1 ORDER BY x` then fails (0/1,
`_build/local-checks/attempts/run-7IndRn`). The earlier incorrectly selected
`-f having_aggregate_test.mbt` invocation discovered zero tests and was rejected
by the existing guard (`run-OtHOUa`); it is not counterexample evidence.
This establishes a parser/lowering gap, not a pre-fix public Run failure.

## Connection and ownership

HAVING uses the same admitted tokens, aggregate parser and argument ASTs as
SELECT and Pipe AGGREGATE. Its predicate retains private references to those
calls and their original source ranges. Embedded argument nodes, depth, query
work and collection-order syntax nodes remain within the existing budgets.
The generated frontend AST interface is updated from the pinned toolchain.

The lowerer adds required aggregate outputs to the existing group. The filter
reads evaluated aggregate slots. Repeated calls and matching SELECT aggregates
share a slot only when function, argument resolution, DISTINCT, delimiter and
ordering all match. Pre-group SELECT aliases needed by an aggregate argument
use private derivations in the original input snapshot. An aggregate/analytic
output alias cannot become another aggregate input. Qualified inputs and alias
collisions are distinguished before reuse.

Hidden slots are removed by the ordinary SELECT projection. A global HAVING
aggregate can establish the existing global group even without an aggregate in
SELECT. The prior sole-DISTINCT-ARRAY_AGG row-deduplication optimization is not
used when HAVING needs additional aggregates: it must not alter their input
multiplicity. Collection admission and numeric profile requirements still
belong to the common checker. This does not add an evaluator, numeric policy,
key or order evidence, resource ceiling, storage format or execution owner.

The normative grammar's HAVING expression delegates to the closed query
expression profile; the same aggregate family already exists in that profile.
No common law, normative document body or canonical pin changes in this unit.
The AST shape changes only for frontend HAVING observations, not JSON/YAML
Program input. Broader unsupported aggregate modifiers and aggregate expressions
in SELECT/ORDER are not claimed as completed here.

D's CTE/predicate/assert/Effect and cancellation/Model-wire functions, H's
Effect equality/hooks/Ledger cleanup, A's expression progress and C's Graph
contracts are unchanged. The modified branches are HAVING parsing, GROUP's
hidden aggregate connection and HAVING reference lookup. Integration with those
separate fixes needs their fixed-SHA evidence; this change does not certify them.

## Independent acceptance and reporting

- Complete authored Program controls cover hidden COUNT and reuse of a selected
  qualified SUM. The common checker receives its existing numeric profile;
  omission still produces the specific NumericReductionProfile request.
- The public fixture has twelve normal cases: independent JSON, hidden and
  repeated counts, LIMIT/OFFSET, selected/hidden arguments, SUM reuse, alias
  collision versus qualified input, NULL and DISTINCT, typed parameters with a
  Pipe tail, a scoped CTE JOIN with explicit ceiling 10, and grouped/global
  empty input. Expected rows and full column contracts are independently authored.
- Five static refusals cover non-Boolean COUNTIF, undeclared parameters,
  ungrouped input, a nested aggregate alias and invalid DISTINCT star. Existing
  public assertions require typed input rejection, zero admission and zero I/O.
- A demanded arithmetic failure must publish no readable/describable Result.
  Normal cases retain the existing read/reattach/resend checks: one acquisition
  session and no repeated admission or provider I/O. Column contracts and order
  expose no hidden aggregate or argument slots.
- Cases join the ordinary packed corpus. `--having-aggregate-only` selects this
  unit through the existing external installation for Local and HTTPS.

Working-tree tests, clean-SHA tests, package digests and packed results are
reported separately in the PR body and external evidence. No full Core, full
packed, proof, performance or Cloud campaign is requested for this unit.
Interface generation on supported targets is not Wasm/Native execution proof.
