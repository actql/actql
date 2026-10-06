# DISTINCT JOIN ordering preserves projected values

Baseline: `8f6133865d37f6ece67284e34172372cf7dcffca`.
This repairs a frontend connection gap within existing query scope and ordinary
Relation contracts. It does not change grammar, schemas, common laws or pins.

## Contract and counterexamples

The adopted query profile allows ORDER expressions that can be resolved from
DISTINCT output values. Output aliases take precedence; qualified input columns
survive only when their values were directly selected. This follows the existing
[query contract](../spec/query-text.md#scope-and-lowering) and the selected
[GoogleSQL query reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#order_by_clause).
Ordinary SELECT already connected this case, while the single JOIN/CTE JOIN
helper rejected every ORDER expression that did not directly reuse a SELECT
expression or name.

The three independently authored baseline tests all failed (`run-9NMYzN`,
0/3), including SQL alias shadowing, a directly selected qualified input,
Pipe JOIN and CTE JOIN:

```sql
SELECT DISTINCT -t.x AS x
FROM t JOIN r ON t.x = r.k
ORDER BY -x;
```

The ORDER negation consumes the evaluated output x. It cannot reuse the SELECT
negation of input t.x, nor recover that dropped input. Baseline evidence is
compiler rejection, not an executed public Run with incorrect output rows.

## Repair and independent expectations

Both Values JOIN assembly and retained/CTE JOIN assembly preserve their existing
JOIN, predicate, ceiling, projection and DISTINCT. Non-reusable ORDER expressions
are checked against projected aliases and direct selected-input correspondence.
They lower through existing property-aware expressions to ordinary derive steps
*after* DISTINCT. Existing sort, LIMIT/OFFSET and final projection then remove
helpers. SELECT expressions are not expanded or evaluated again. Non-DISTINCT
assembly and exact selected-expression reuse retain their existing paths.

A full expected Values Program is hand authored and passes normal checking before
comparison with source lowering. It includes both input Stages, JOIN ceiling 4,
projected score, DISTINCT, a qualified-input-derived sort helper, sorting and
public projection. It is not generated from product output. Exact
`UnsupportedOrdering` tests preserve refusal of dropped input columns and
transformed input recovery; duplicate ORDER expressions share one helper.

Focused repaired-tree JS checks passed 30/30 (`run-EopLn5`):

```sh
node scripts/local-checks.mjs test moon -- --target js src/query_program/distinct_join_order_test.mbt src/query_program/join_order_test.mbt src/query_program/distinct_order_output_test.mbt src/query_program/join_property_paths_test.mbt src/query_program/data_join_test.mbt
node scripts/local-checks.mjs test node -- scripts/distinct-join-order-source-input.test.mjs scripts/public-query-profiles.test.mjs
```

Node fixture/profile/corpus checks passed 9/9 (`run-e3useB`). Selected formatting,
JavaScript syntax and whitespace checks passed. These are focused precommit
implementation-tree results, not hosted CI or other-target results.

## Public acceptance obligations

The authored packed corpus contains an independent JSON control, SQL alias
collision, Pipe LIMIT/OFFSET, one shared acquired CTE producer, selected qualified
input ordering, exact selected-expression reuse and typed empty output. Input
amounts 2,2,1,NULL plus excluded 99 yield DISTINCT output NULL,-1,-2 when ordering
by the negated output alias; ordering a directly selected input yields 1,2,NULL.
Three dropped-input cases must fail preparation with no Run admission or provider
I/O. A demanded divide-by-zero in the ORDER expression must fail execution and
publish no partial Result.

The normal corpus and narrow `--distinct-join-order-only` selector share these
fixtures. Existing public acceptance compares rows, ordered schema and complete
type/nullability, hidden-column absence, acquisition counters and same-request
resend/attach/reread. JOIN ceilings are authored as 25 for the five-row source;
no ceiling or execution budget is raised to obtain success. Public execution
results and exact package/runtime identities are recorded separately after
normal committed-source packing.

No common owner, planner, provider or Host implementation is changed. Full Core,
other targets, all packed/proofs/performance and hosted required coverage remain
unverified by the selected checks. No merge or manual CI retry is performed.
