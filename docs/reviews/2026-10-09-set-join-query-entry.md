# JOIN set operands: standalone query entry connection

Authoring main: `b40818e09295dba39de6b570b977610e95c75b1e` (#1079 included).
This independent unit has no unmerged parent. Final target is main.

## Fixed counterexample and implementation boundary

```sql
SELECT t.x AS id FROM t JOIN r ON t.x = r.k WHERE t.x = 1
UNION ALL
SELECT t.x AS id FROM t JOIN r ON t.x = r.k
ORDER BY id
```

For t.x=[1,2], r.k=[1,2], the independently intended rows are id=[1,1,2].
The complete hand-authored ordinary Values/filter/join/append/sort Program
passes common checking. The existing single-query script route also passes;
the standalone compile entry refuses exactly UnsupportedJoin. Pre-repair
focused test: 0/1 (`run-VT0oYb`, `focused-test-HL81G9`).

The standalone entry previously chose compile_set_query, whose
compile_set_stages rejects any JOIN operand. DATA already uses
lower_script_set_relation and lower_script_join_relation. Route only query
trees with a JOIN set operand through this existing script path. Inspect nested
set rights and CTE bodies structurally; do not resolve names, move WHERE/ON,
change key mappings or add another execution implementation in that router.

The one call-site adjustment is compile.mbt::compile. D's CTE/predicate/assert/
Effect functions, query_script_program, common Owners, Host, grammar, pins,
physical strategy and capacity rules are unchanged. The new module handles
structural entry selection only. No shared producer is expanded or materialized.

Existing composition requirements in docs/spec/query-text.md apply. The selected
[GoogleSQL query syntax](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#set_operators)
combines query operands; [JOIN](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#join_operation)
retains matching multiplicity, while final ORDER/LIMIT belongs to the combined
output. Existing adopted set-name/CTE profiles remain unchanged. Current official
reference was consulted; this is not a live Google differential run or complete
query conformance claim.

## Independent public obligations

The new set-join-source-input fixture participates in the existing normal
public corpus and --set-corresponding-only cohort. Old twelve normal/eight
refusal CORRESPONDING cases remain unchanged. Add eight normal/four exact
refusal cases, not a second Host or test-side Program repair.

- Independently authored JSON captures the shared source once and applies both
  filters/joins, append and final sort using ordinary operations.
- Complete SQL uses explicit MAX_OUTPUT_ROWS 10 for both JOINs, exactly matching
  the JSON control. It does not depend on the public default of 1,000,000.
- Rows id=2 are duplicated twice; their self-JOIN yields four matching rows.
  UNION ALL retains all four. A NULL amount remains NULL and sorts last.
- Right-only JOIN operand, reversed CORRESPONDING field order and a CTE set body
  retain six intended rows and the public id/amount column order/contracts.
- Empty input retains typed empty results. Explicit typed LIMIT/OFFSET parameters
  select two duplicated id=2 rows. UNION DISTINCT retains one row per value.
- Operand ranges and the right-only output alias do not escape the set. Missing
  limit declaration and unsupported JOIN keys retain exact preparation refusals.
- Existing acceptance checks Named Result, Result.describe, hidden field absence,
  same-submission replay/attach/lookup and one physical source acquisition session.

## Limited validation

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 300 -- --target js src/query_program/set_join_entry_test.mbt src/query_program/data_set_test.mbt src/query_program/data_join_test.mbt src/query_program/set_order_expression_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- scripts/set-join-source-input.test.mjs scripts/set-corresponding-source-input.test.mjs
```

The first post-repair selection passed 12/13: ten existing caller tests and two
new tests passed; the last new assertion used the wrong take field name (limit
rather than the existing count contract). After correcting that authored
assertion, 2/3 passed with the remaining exact refusal expectation located at
Expression(UnknownReference), not UnsupportedSet. The final new selection passed
3/3 (`run-J89iIR`, `focused-test-TeOWUa`). The unchanged ten caller cases were
not needlessly repeated. Node fixture registration/expectations passed 4/4
(`run-LyJWXP`, `focused-test-z6ML8p`); the explicit-bound fixture adjustment also passed 4/4 (`run-usIzS6`,
`focused-test-oLV4dS`).

Public Local/HTTPS execution, normal five-package identity, submitted-HEAD CI
and content review are unverified at this preparation stage. Keep Draft until
public acceptance is complete. Full Core, Wasm/native, proof/performance and the
full packed campaign were not selected locally. This unit does not claim the
entire Frontend complete.
