# Star replacement aggregate snapshot during ORDER

Owner: B. Main baseline: `0a4a53f7fe28646f703ac60dd65bbdf2b9c8635e`.
This is independent of #680 capacity and #698 JOIN star routing. Destination:
main; no unmerged feature dependency and no merge operation.

## Counterexample and independent expectation

```sql
SELECT * REPLACE (SUM(y) AS x, y + 1 AS y)
FROM t GROUP BY y ORDER BY `x`
```

For `(x,y)=(1,20),(2,10)`, output is `(10,11),(20,21)` in x,y order.
SUM reads original y, while GROUP BY the selected y alias groups y+1. Quoting
x must not change which input SUM sees. The pre-fix Program instead passes
`aql_group_key_0` (y+1) to SUM; the unquoted control retains original y.
Focused red evidence: `focused-test-06tKiU`, at the baseline with only the
new regression. `focused-test-v1M0CY` is an earlier test-authoring error
(field-form versus expr-form oracle), not product failure evidence.

The [adopted SELECT REPLACE contract](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#select_replace)
retains column names/order while replacing values. All replacement expressions
use the SELECT input snapshot; ORDER references evaluated output aliases.
The independently authored complete Program in `star_aggregate_order_test.mbt`
checks through the ordinary checker and matches bare/quoted aliases,
quoted replacement names and qualified input references.

## Minimal correction and collision boundary

`order_aggregate_calls` was comparing expanded GROUP projections to the authored
SELECT star. Its alias classification therefore mistook a replacement aggregate
for an ORDER-only call and applied the wrong argument scope. Pass the existing
expanded SELECT projections and compare names with existing `same_name`.
Only selected aggregate declarations qualify: an ordinary input with the same
spelling as a parser-private call must remain a separate slot. The intermediate
name-only fix fails that collision regression (`focused-test-JuXMZe`); the final
fix keeps both values. No aggregate, scalar, checker, order, capacity or Host
owner is implemented or relaxed here. No new syntax or normative identity is
introduced.

## Focused verification and public fixture

- JS 22/22: new full Program/collision regressions and existing star replacement,
  ORDER aggregate and filter-scope callers (`focused-test-W83DQ8`).
- Node 14/14: independent fixture and existing public/analytic profile selectors
  (`focused-test-5KGrsy`). Changed MoonBit formatting and `git diff --check` pass.
- All evidence directories are under `_build/focused-evidence` in the B worktree.

Five new public successes join the ordinary star replacement corpus: independent
JSON control, bare ORDER, quoted ORDER, quoted replacement and qualified star.
Independent inputs `(id,amount)=(1,10),(1,10),(2,30),(3,NULL)` require rows
`[{amount:11,id:20},{amount:31,id:30},{amount:null,id:null}]`, with amount,id column
order and both nullable number contracts. Wrong snapshot sums are 22 and 31,
so quoting cannot silently change values. The JSON control groups original
amount, then projects its increment: on these numeric/NULL inputs it gives
the same groups as the source's incremented group key. No product output
generates rows, types or Programs.

Normal five-package Local/HTTPS acceptance is still pending at this checkpoint.
Use the existing `--star-replace-only` runner: 18 successes and 8 pre-admission
refusals per transport, including the original unchanged cases. Preserve Named
Result/describe, stream completion, hidden-column absence, source once and
same-request/read/attach replay checks. No full Core, all-target, proof,
performance, Cloud or manual CI campaign is claimed. Keep Draft pending review
and actual submitted-HEAD CI; earlier SHA successes are not current CI evidence.
