# ORDER grouped subexpressions: evaluated-key connection

Date: 2026-10-08. Owner: B. Final target: main. Initial fixed parent is `9e95c13d8c1f673e37bd574ad6e99fde6d085305` from Draft #920. The private clause-aware grouped binder is that dependency; this is a separate implementation unit. #910/#915 are merged. No common execution owner, grammar, contract law, pin or legacy wire fallback is introduced.

## Counterexample and independent Program

```sql
SELECT x + 1 AS bucket, COUNT(*) AS n
FROM pair
GROUP BY x + 1
ORDER BY n + (pair.x + 1)
```

The complete hand-authored Program in `order_grouped_subexpression_test.mbt` ordinarily checks: Values -> derive x+1 -> group/count -> derive count+evaluated-key -> sort -> select bucket,n. Equivalent source fails compilation before repair: `run-kRn0NB`, `focused-test-UFDEQk`, 0/1. With x=7 the independent key is 8 and count is 1. The test does not edit compiler output.

The existing query-scope contract in `docs/spec/query-text.md` admits grouping subexpressions and SELECT-alias precedence. ORDER had no subtree connection, and its grouped input snapshot was discarded at SELECT. This implementation preserves that snapshot only for the directly following SQL SELECT-owned ORDER, then clears it. A subsequent Pipe cannot recover that original scope.

## Repair and boundaries

`query_order_grouped_expression.mbt` compares a grouping expression's original receivers against ORDER's own meanings. Explicit and implicit output aliases follow the existing exported-name rules. A computed/aggregate alias cannot prove original-input receiver identity. Qualified ranges retain their input meaning; property members are compared after longest-prefix resolution. Parser-owned hidden aggregate references never constitute input provenance, even when an implicit star exposes the same spelling.

Only complete matching keys with surviving checked slots are bound. A deferred SELECT uses its retained physical keys. After materialized SELECT/DISTINCT, a key is available only through recorded selected-slot correspondence; a coincidentally equal column name does not prove survival. DISTINCT cannot recover an unselected or overwritten input. Unknown-reference refusals retain the existing `UnsupportedOrdering` classification for DISTINCT. Other expressions use the common nullable-property/expression bridge; no alias expansion, independent evaluator or frontend sort is added.

Focused controls include a complete negative-alias Program (`SELECT -x AS x ... ORDER BY x+1`), nullable properties, hidden COUNT, repeated selected grouping expressions, independently resolved object aliases versus qualified inputs, JOIN/CTE, DISTINCT, closed Pipe continuations and original work-limit origins.

An implicit member alias is a separate collision control: input score=2,1 and payload.score=10,20, grouped by `(payload).score` and `score+1`. ORDER's bare score denotes the implicit output alias. Its sort expression must add to the evaluated payload property, not select the other computed grouping key. The first repair fails this assertion in `run-hCIeyA`, `focused-test-L7Ddt8`, 0/1; implicit aliases are then included in provenance checking. An exploratory unparenthesized grouped implicit-name spelling fails earlier source compilation (`run-hjC6BR`, `focused-test-BAazin`) and is not claimed as repaired by this unit; its naming boundary remains a follow-up.

## Focused evidence

- Initial complete repaired Program: `run-0lM2LS`, `focused-test-b60Lvw`, 1/1. A preceding local helper syntax error is not counted as a test pass.
- Initial extended controls: `run-6cHdLW`, `focused-test-6NsOdF`, 7/7.
- `run-inZOEw`: new controls 7/7, existing SQL DISTINCT 5/5 and JOIN DISTINCT 2/2. Existing aggregate ORDER is 6/7: its implicit-star/private-COUNT collision detects the missing aggregate provenance exclusion. The attempt stops before HAVING and is not an overall pass.
- After that repair, `run-pDxa88`: ORDER controls 7/7, aggregate ORDER 7/7, inherited HAVING 8/8.
- After implicit-member alias repair, `run-orn3Yw`: ORDER controls 8/8 (`focused-test-GWnWUP`), aggregate ORDER 7/7 (`focused-test-n1BT1p`).

Formatting is limited to the new helper/tests and changed compile blocks. No unrelated formatter diff is retained. JavaScript syntax and `git diff --check` pass.

## Public acceptance obligations

Twelve normal cases and five preparation refusals are registered in the ordinary group-property corpus. `--order-grouped-subexpression-only` selects those same cases. The independent JSON control and equivalent source use x=1 four times and x=2 once: count+key sorts bucket 3/count 1 before bucket 2/count 4. Sorting the grouping key alone produces the opposite order. NULL keys, empty input, hidden aggregates, surviving DISTINCT keys, object alias/input collisions, JOIN ceiling 10, implicit aliases and scalar alias/input reverse-order pairs retain independent rows and complete checked column contracts.

Existing public checks retain Named Result rows, type/nullability/column order, stream completion, private-field absence, request resend/attach/reread identity and refusal admission/provider-I/O counts. Tests must not patch generated Programs or change expected rows/bounds to pass.

Fresh clean normal five-package Local/HTTPS acceptance passes for the selected twelve normal cases and five refusals at `e6e5f0fabc2404b88f2d119932f8f05630a68e93`; final evidence follows. This does not establish broader Frontend execution completion. Required exact-submission CI, Wasm/native/full Core/full packed/proof/performance and broader grouped composition remain unverified. No manual CI restart or merge.

## Normal dependency/main integration

The corrected #920 parent `8dbe714b81794849dcad0def193cf370b827d74b` is normally merged as `11cd67428cf0db2b1672fa0f3b10affcd672c5e0`. This adopts current main `aeaf13f15addf1687c1cd87b12b4657a8c984e9a`, including Client wire/submission and retained ARM64 proof records. The JOIN normal fixture uses the supported `MAX_OUTPUT_ROWS 10`; no old WITH annotation is reintroduced. No conflict or history rewrite. #920 remains an unmerged dependency, so the first Draft PR targets its branch; final target is main after parent integration.


## Fixed-source public acceptance and main target

Integrated implementation `6f6a18ed498af2cf343e030f5305cc2bb8660633` passes the eight focused new controls (`run-W2h3om`, `focused-test-0U9wyl`) and readonly compilation-manifest freshness. Normal evidence-only parent integration yields clean producer `e6e5f0fabc2404b88f2d119932f8f05630a68e93`; `git diff` confirms no change in src/scripts/packages/adapters/spec from that tested implementation.

`run-hxUMyx` passes normal five-package production and the selected public Local/HTTPS consumer. Each entrance completes twelve normal cases and five preparation refusals, using the unchanged independent expected rows, contracts, column order, NULLs, multiplicities and JOIN ceiling 10. Named Result/stream/private-field/request resend/attach/reread assertions and refusal admission/provider-I/O checks pass. The same installation passes the README control and real missing-current-generated-wire-asset rejection; no legacy wire is used.

Receipt `worktrees/.codex-scratch/public-query-evidence-UT3MFl/summary.json`, `010.stdout.log` and `010.stderr.log` retain clean exact e6e, passed/complete, five tarball digests, artifactsRemoved=true and no evidence errors. Manifest `/private/tmp/actql-b-order-grouped-e6e5f0fab-pack/packed-client-packages.json` digests match the receipt directly. It is not relabeled to a later revision.

#920 is now merged with submitted HEAD `11be481758ed29fe5770af58ff3c6a01354979cf` and main merge `ff4ace1ea0f7bffd2741c9fe3eab54a0f013dd1b`. Its product source matches the accepted parent 8dbe. After the public gate terminates, that main is normally merged as `6135d10ac8ffbc9fc1ffe9341160d32b95813664`. No conflict and no src/scripts/packages/adapters/spec change from the e6e producer. The subsequent record changes documentation only. The PR can target main, with no unmerged dependency. Exact final-HEAD hosted CI remains a separate requirement; no manual restart, broad rerun or merge.
