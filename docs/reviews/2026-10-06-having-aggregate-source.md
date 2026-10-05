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
- The public fixture has thirteen normal cases: independent JSON controls, hidden and
  repeated counts, LIMIT/OFFSET, selected/hidden arguments, SUM reuse, alias
  collision versus qualified input, NULL and DISTINCT, typed parameters with a
  Pipe tail, a scoped CTE JOIN chain with explicit ceilings 10, and grouped/global
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

## Separate existing single-JOIN grouping gap

The first clean-SHA packed campaign used
`b312c319dcf3c9bf366f49b2d2b49016fe8b3c8b`. The first nine Local normal
cases passed. The following valid source was refused before Run acceptance:

```sql
WITH picked AS (SELECT id FROM records WHERE id > 0)
SELECT p.id, COUNT(*) AS n
FROM picked AS p
JOIN (SELECT 1 AS k) AS seed
  ON p.id = seed.k MAX_OUTPUT_ROWS 10
GROUP BY p.id
HAVING COUNT(*) > 1
ORDER BY id
```

The independently intended rows remain `[{"id":1,"n":2}]` with nonnullable
number columns in the order `id,n`. The original source and expectation are
retained in `having-aggregate-source-input.mjs`; its current refusal is recorded
as a known implementation gap, not as invalid SQL or successful execution.
`havingSingleJoinProgram` is an independently authored ordinary Program control
with the same predicate, JOIN ceiling, count, projection and order.

The first rejection is `UnsupportedCte` inside `compile_join_steps`, where the
single-JOIN specialization expects SELECT at the first non-WHERE operation.
This query instead starts with GROUP. `lower_script_join_relation` selects that
specialization for one JOIN, whereas existing multi-JOIN queries reach
`compile_join_chain_steps` and the shared scoped `compile_steps` path. Replacing
`HAVING COUNT(*) > 1` with the already supported `HAVING n > 1` retains exactly
the same rejection, fixed by a typed regression. No common execution failure is
established by this source refusal.

This is the concrete handoff to D's CTE/JOIN connection boundary. B does not
change that routing, either JOIN implementation, the CTE validator, predicate
handling, or authored ceilings in this HAVING unit. The positive scoped fixture
uses the existing two-JOIN route with a second one-row Relation and independently
retains `[{"id":1,"n":2}]`. This is a separate supported input, not evidence
that the original one-JOIN source is repaired.

Failed campaign evidence is retained under
`../worktrees/.codex-scratch/public-query-evidence-sqHjIq` relative to the main
workspace repository, and the local gate under `_build/local-checks/attempts/run-vIfYJI`.
The first campaign did not reach its remaining normal cases, refusals, demanded
arithmetic failure or HTTPS HAVING cases. The harness saved stdout/stderr and
command status before removing only that campaign's temporary installations and
Stores. Later source revisions require their own clean-SHA package manifest;
the failed campaign's package identities are not reused as new-SHA evidence.

## Current-main integration and hidden property-order connection

The normal merge `a98a2a3011a2729945b1ab84137ec1aa87784f0d` incorporates
main `77965b92802dc8c53b1df8c90a28989205644fe4`. It retains main's IFNULL,
aggregate property-order helper, public selectors, identity vectors and immutable
history repairs. The new product fix is separate from that integration commit.

An independently authored ordinary Program admits a hidden ordered STRING_AGG
over `payload.score`; the corresponding source previously failed to lower
(`run-7KnYo5`, one failing test). Hidden HAVING calls were not connected to the
existing property-order helper used by SELECT aggregates. The repair supplies
those order slots to the ordinary aggregate lowerer.

The alias collision control also exposed an invalid dependency within one derive
step: a property expression referenced `aql_having_argument_6` created by that
same step. The common checker correctly rejected it as
`Operation(UnknownField("aql_having_argument_6"))` (`run-EK0fMJ`). Alias
derivations now precede a separate property-order derivation; no common checker
rule is relaxed. SELECT and HAVING order caches are separate because their
receivers can resolve differently. Existing semantic aggregate reuse still
requires equal resolved references.

The source fixture adds an authored JSON control, hidden property ordering,
alias/input collision and a qualified-input control. Input order, duplicate
`b` rows, nullable receivers and nullable members are retained. The alias case
expects `original = 'b|b|a|c'` while its HAVING call sees a constant selected
object and expects `'a|b|b|c'`; the qualified-input control returns no rows.
These different results detect reuse across distinct receivers. Two invalid
member/type cases remain common-checker refusals before admission.

Working-tree verification: focused JS 23/23 and Node 32/32, plus read-only
compilation-manifest and spec-family validation (`run-gY4Jjg`). These are
integration-tree results, not clean-SHA public acceptance. The expanded public
selection has 17 normal cases, seven invalid-input refusals plus the previously
recorded valid single-JOIN gap, and one demanded execution failure per transport.
The separate single-JOIN repair remains in #512; this parent does not claim it
is fixed. Clean-HEAD tarball evidence and Local/HTTPS outcomes will be recorded
separately after execution. Wasm/Native, full Core and required CI remain
unverified for the new revision.
