# ORDER reuses equivalent static property receivers

Base: main `397142fb176da04f31fc2801d366f4749aa3e6ec`.
This is a Frontend slot-reuse repair, not new syntax, a different executor,
type inference from rows or a change to the common Result ordering contract.

## Counterexample and existing contract

```sql
SELECT DISTINCT payload.score AS score
FROM objects
ORDER BY (payload).score NULLS LAST
```

Without a colliding range or output alias, both property references read the
same input slot and member. The existing common Program can derive the property
once, select `score`, deduplicate only `score` and sort the evaluated output.
The existing Frontend refused this query: its SELECT-expression cache compared
the Reference and explicit Property AST forms rather than their resolved value.
The ORDER fallback cannot recover an object removed by DISTINCT.

The adopted [query-text contract](../spec/query-text.md) requires ordering to
resolve from selected expressions or aliases after DISTINCT and forbids
re-evaluating SELECT. Google's [query syntax](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax)
and [field-access operator](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/operators#field_access_operator)
are the selected external references. No live Google service comparison was run.

Syntax equivalence alone is insufficient. With range alias `payload` and a
separate range column `score`, `(payload).score` reads the input object while
`payload.score` reads the range column. These must not share a selected slot.
An output alias replacing the receiver likewise retains ORDER's alias-first
meaning. Existing collision and qualified-input controls remain unchanged.

## Repair

Reuse the existing scoped expression comparison established for GROUP:
resolve the original receiver before appending explicit property members, then
compare slot identity and the ordered member suffix at each static subtree.
Keep the preceding ORDER-versus-SELECT alias-resolution guard. Keep exact
operators, parameters, conditional demand and unresolved-reference refusal.
Remove only the now-unused single-scope reference wrapper.

SELECT/GROUP/JOIN/ORDER still use the existing lowerer and common checker.
There is no hoisted evaluation, new uniqueness/order evidence, input recovery,
weakened ceiling, new acquisition or compatibility path.

## Independent obligations

The MoonBit control contains a complete independently authored Program, with
typed nullable object input, duplicate values and both object NULL/member NULL.
Direct, qualified, quoted and computed receiver variants compare against that
Program, including a Pipe control. Cache reuse is checked by the single
property expression and absence of a private sort helper. Three range/object
contrasts require the exact existing `UnsupportedOrdering` refusal.

Nine new positive public cases and four typed refusals extend the existing
`distinct-order-source-input.mjs` corpus. They are registered through both the
normal public campaign and its existing `--distinct-order-only` selection;
no new acceptance infrastructure is introduced. The JSON control is authored
directly, not generated from Frontend output. Source filtering, schema/column
order, one acquisition, private-slot exclusion and resend/reread checks remain
owned by the existing packed fixture. Refusals require zero admission/I/O.

Independent ordered results:

```json
[{"score":10},{"score":20},{"score":null}]
```

Computed `+1` yields 11, 21, NULL; LIMIT 2 OFFSET 1 retains 20, NULL. Ordinary
SELECT retains both 20s and both NULLs. Empty input retains the declared nullable
number column. Source range scores deliberately differ from object scores.

## Executed focused checks

- Pre-repair `run-v3AKkA` / `focused-test-sHpvB4`: **two positive tests failed**,
  the receiver-scope refusal control passed. This is compiler evidence, not a
  claim of an incorrectly published public Run.
- A subsequent selection used a nonexistent test filename (`run-Qr6203` /
  `focused-test-3i8qpR`); it executed no tests and is not a product failure/pass.
- Corrected intermediate selection: **34/34 JS**, `run-OzIcMv` /
  `focused-test-LBI2eL`.
- Final formatted repair and Pipe control: **35/35 JS**, `run-F1UeAX` /
  `focused-test-mUBk1M`, covering DISTINCT output/JOIN ordering, nested-property
  alias collisions, GROUP receiver contrasts and ordinary Pipe/JOIN scope.
- Final Node: **12/12**, `run-GvVuTW` / `focused-test-adVzey`, covering the
  independent public Program, authored results, registration and profiles.

Commands (pinned toolchain):

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 900 -- --target js \
  src/query_program/order_property_receiver_reuse_test.mbt \
  src/query_program/distinct_order_output_test.mbt \
  src/query_program/join_distinct_order_test.mbt \
  src/query_program/order_property_paths_test.mbt \
  src/query_program/group_property_receiver_scope_test.mbt \
  src/query_program/pipe_order_scope_test.mbt \
  src/query_program/join_order_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 300 -- \
  scripts/order-property-receiver-source-input.test.mjs \
  scripts/public-query-profiles.test.mjs
```

At this committed snapshot, exact-HEAD normal five-package Local/HTTPS acceptance
is pending. Record its actual SHA, manifest/digests and terminal result in the PR
body, without assigning earlier evidence to that run. CI, other targets, full
Core and other public cohorts remain unverified. Broader STRUCT star and other
Frontend coverage gaps remain separate; this repair does not close the overall
Frontend objective.

## Public attempt and refusal-code correction

The clean `48ef9e99dce686562ecacca0b9ee0640cab355e3` normal five-package run
`run-0nYfZT` reached all **20 Local positive cases** (11 existing and nine new).
It then failed the new refusal-code assertion; HTTPS and completed refusal
acceptance were not reached. Preserve the original failed evidence at
`worktrees/.codex-scratch/public-query-evidence-iid0zb`, including
`010.stdout.log`, `010.stderr.log` and the failed summary. The successful
positive lines do not establish a completed campaign.

The fixture incorrectly expected `ClientProgramInvalidInput`. The exact
MoonBit lowerer diagnostic is `UnsupportedOrdering`. The existing Check owner
projects it as `Limit("implementation_limit")` in `client_check.mbt`, and the
preparation adapter projects that check failure to
`ClientProgramImplementationLimit`. Correct all four expectations to that
existing public contract. This correction is based on the owner mapping, not a
weakened refusal or changed row expectation. Product code, ceilings, Source
inputs and independent expected results remain unchanged. The next clean-SHA
normal-pack campaign must verify all refusals and both transports.
