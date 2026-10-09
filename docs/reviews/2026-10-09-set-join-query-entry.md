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

The initial preparation record left public Local/HTTPS execution, normal five-package identity, submitted-HEAD CI
and content review are unverified at this preparation stage. Keep Draft until
public acceptance is complete. Full Core, Wasm/native, proof/performance and the
full packed campaign were not selected locally. This unit does not claim the
entire Frontend complete.


## First normal packed execution and the alignment counterexample

Normal producer source: `2f98fb9a41a77679429924972d39a261abc9d766`.
The five tarballs were produced by the existing producer with ordinary prepack
and independently checked against its revision/digest manifest. The consumer
receipt is `worktrees/.codex-scratch/public-query-evidence-4E6bC1`; bounded
producer/consumer attempt: `run-Miz3YR`. Retain that receipt and the producer
manifest/tarballs separately from later source revisions.

Packed Local passed twelve unchanged CORRESPONDING controls plus the new
independent JSON, both-JOIN-operands SQL and right-only-JOIN SQL. It then failed
at set-join-sql-corresponding, before Named Result publication. The four later
positive cases, all refusals and HTTPS were not reached. These fifteen passes
are partial Local evidence, not complete acceptance or CI success. The six
expected rows, JOIN ceilings of 10, nullable amount, column order and one-source
acquisition obligation remain unchanged.

The terminal ACTQL_E_UNPUBLISHED_RUN is not the first cause. A focused private
diagnostic reinstalled the same digest-verified tarballs, added an existing
Host diagnostic callback with an explicit temporary account/key/reviewer, and
used an inspector breakpoint without editing a package. Source acquisition
completed. The captured execution had host-tasks-failed, no completed tasks,
and Physical(ExecutionLimit); publication subsequently reported
StrategyNotComplete/CapturedRunPublicationFailed. Source Run failure is verified;
the diagnostic authorization/observation setup is not the pristine acceptance
installation. Evidence: `run-WBFhzZ`, `run-aIw4OS`, and the protected private
`actql-b-set-join-2f98fb9a4-diagnostic/publication-cause.json` and Store. Earlier
diagnostic setup failures (wrong working directory, missing helper fixtures and
installation callback mismatch) are not product failures or test passes.

The same packaged preparation API checked and compiled the ordinary JSON and
both SQL cases, and saved their complete semantic Programs and Executable Plans
(`run-AeZHFD`, `focused-test-NJm6vK`). The reversed-order SQL's only additional
operation is a second immediate select after the JOIN's terminal column
projection: select amount/id, then align id/amount.

## Narrow projection composition

Compose those adjacent pure column projections inside the existing set lowerer.
The new helper accepts only an operand-local terminal step with exactly
from/select/as and column strings or column aliases. It preserves the evaluated
column sources, the producer name and the required set output spelling/order.
It does not move across another operation, modify predicates/ceilings, evaluate
an expression twice, or add identity/order evidence. Previously declared
producers, expression-valued projections and retained Result taps are excluded.
The query entry keeps the existing NEAREST/Graph placement refusals before
selecting the JOIN/set script route.

Changed shared call site: query_script_set.mbt::lower_script_set_relation, only
the immediate right-operand alignment. CTE source-sharing/predicate/assert/Effect
functions and query_script_program are unchanged. This is one Frontend
implementation; common capacity/strategy/Host Owners are not duplicated or
relaxed. D's composition paths consume this same set lowerer after integration.

Limited JS tests passed 6/6 (`run-MPYYLF`, `focused-test-RIo9qa`): the five JOIN
entry tests plus independently authored projection/strict-boundary cases. Eight
existing set caller cases passed with the same product change in the preceding
13-case selection (`run-0AFh7a`); only the new test initially chose a JOIN that
had no terminal select to compose. Its source was corrected to exercise the
actual qualified/filtered JOIN path. Test setup/compiler errors are not passes.

A new clean source and normal pack must establish whether this removal closes
the public ExecutionLimit. Keep all twenty positive/twelve refusal cases and
Local/HTTPS obligations; do not change the budget or exclude the failing case.
