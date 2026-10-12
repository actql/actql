# Frontend checkpoint repair: WITH JOIN dispatch

This finite unit starts at main `afd58cbe3abc06686473702e734a271dd8bb4378`.
The original G checkpoint remains `ee7cae5a7494305775ec9cb7dacf2b5531eb089e`:
13,763 executed cases, 13,629 passes and 134 failures, exit 2. This repair does
not replace that checkpoint with a successful full-Core claim.

## Confirmed product defect

`compile` called `join_requires_input_binding` before routing a query with WITH
bindings to `compile_query_script`. That standalone probe resolved the JOIN's
right producer in the installed Context, where authored WITH names do not yet
exist. A valid query therefore failed with `UnresolvedRelation` before the
existing lexical binder, checker and demand owners could process it.

Minimal reproducer using the existing independent object inputs:

```sql
WITH lefts AS (SELECT id, payload FROM objects),
     rights AS (SELECT id, other FROM others)
FROM lefts AS l
|> WHERE l.payload.score > 15
|> JOIN rights AS r ON l.id = r.id MAX_OUTPUT_ROWS 12
|> SELECT l.id, r.other.score
|> ORDER BY id
```

Route the existing script-classification cases first. Inspect standalone JOIN
input kind only after those cases have been excluded. The existing binder still
resolves each producer, checks all WITH bodies and retains shared seeds. No
expression, ceiling, Catalog rule, publication order, evaluator or contract pin
changes. Truly unresolved right producers still fail.

## Independent expectations and evidence

The original complete FULL USING and FULL SELECT Program controls remain
unchanged. New dispatch regressions preserve the property predicate, ceiling 12,
public field order, one Values seed per original input, shared keyed input and
the exact unresolved-producer refusal class. Comparison with the script entry
is a routing control; it is not the independent semantic oracle.

Raw evidence is retained outside Git in
`/Users/t14i/workspace/20260822/reviews/2026-10-13-b-core-checkpoint-evidence/`:

- `run-sn1cmV`: diagnostic test compilation failure, zero executed cases.
- `run-v4Xb8l`: original representative selection, 8/15 passes, seven failures.
- `run-I2nUJb`: isolated original CTE JOIN, 0/1, exact `UnresolvedRelation`.
- `run-mOXdb4`: first repair selection, 27/28; captured expansion still fails.
- `run-nHL3H0`: focused CTE/JOIN/FULL/PIVOT/UNPIVOT/public-lowering callers,
  46/46. These are JS/checker/lowering checks, not installed Host execution.

`failure-scope.json` retains all 98 assigned cases and the original inventory
hash. Exactly 24 original failures have passed in this unit. The remaining 74
are not closed: standalone JOIN golden structure, other compile assertions,
Graph refusal classification, captured Result, formal-plan/Host identity and
additional integration evidence require separate diagnosis. None is presumed
to be a stale fixture merely because another case was stale.

No full Core, Native/Wasm execution, provider, fresh package campaign, Local or
HTTPS public acceptance, Hosted CI or merge was performed. New installed E2E
scenarios: **0**. Those boundaries remain separate from this repair.

## Reproduce

Use the checked-in toolchain pins and the existing nonzero wrapper:

```sh
node reviews/2026-10-13-frontend-core-checkpoint/prepared-checks.mjs \
  src/query_program/with_join_dispatch_scope_test.mbt \
  src/query_program/full_using_scope_test.mbt \
  src/query_program/full_select_scope_test.mbt \
  src/query_program/join_prefilter_range_property_test.mbt \
  src/query_program/unnest_join_continuation_test.mbt \
  src/query_program/inner_correlated_unnest_test.mbt \
  src/query_program/join_distinct_order_test.mbt \
  src/query_program/from_pivot_test.mbt \
  src/query_program/from_unpivot_test.mbt \
  src/query_program/from_unpivot_public_source_test.mbt \
  src/source_frontend/single_join_group_test.mbt \
  src/source_frontend/registered_source_context_test.mbt \
  src/source_frontend/cte_value_table_scope_test.mbt
```

The guard is non-Heavy, 60 seconds, TERM grace 5. Do not broaden this recipe into
a full campaign or reinterpret a compile-only target check as target execution.
