# Value-table ORDER ordinals

Adopted main: `1b0ae88c87683b94cfd96e73f96f969cb4ecf355`.
Parent: #1152 at `e47e0e5f9b6ff0fda0e9d2c2f7be19734e5e6c82`, retaining
#1149 / #1148 / #1146. Final destination is main after the parents integrate;
no merge into a dependency branch.

## Existing contract and counterexamples

```sql
FROM UNNEST(@items) element WITH OFFSET position
|> ORDER BY 2
|> SELECT element.*, position
```

items is [{id:2,label:"z"},NULL,{id:1,label:"a"}]. The input has two actual
columns: the whole object value and the offset. Position 2 must sort by the
offset, giving positions 0,1,2. Sorting by the second exposed object field
(label) instead gives positions 1,2,0. ORDER BY 3 must be rejected; implicit
object fields do not increase the actual column count. Without OFFSET,
ORDER BY 2 is also outside the single actual column.

The pinned [GoogleSQL Pipe ORDER tests](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/testdata/pipe_order_by.test)
separate the single value-table column from its exposed members and require
that positional ordering address that value, if orderable. This is primary
source inspection, not a live Google differential execution. Existing common
type/order checking remains responsible for whether a selected value is
orderable.

Pre-repair run-VfuPLb / focused-test-YKlyLb: **0/2**. The first exact expected
Program comparison sorts the wrong field, and the first outside-column-count
case is incorrectly accepted. Other loop variants are not claimed as separately
executed before repair. No pre-repair public Run was executed.

## Connection repair

The private scope retains actual ordered columns and their evaluated slots
separately from implicit fields used by expressions/star. UNNEST contributes
one value column and its optional offset, including an empty object. SELECT
replaces that list with its authored projection bindings, including deferred
projection. EXTEND appends, SET replaces its slot in place, and DROP/RENAME
retain the remaining column positions. GROUP/INFER/NEAREST use their existing
output scope. JOIN remaps the actual slots with the existing projection and
retains the current USING column-order rules.

An ordinal goes directly to its selected evaluated slot. It is not resolved
again as a possibly colliding range, implicit property, or output name.
Non-ordinal expressions retain the existing alias/name-resolution machinery.
No checker/evaluator/Owner, public type/wire, fallback, resource exception,
schema/law/registry pin, or grammar change is added. D's CTE/assert/Effect and
predicate functions are unchanged.

Complete independently authored expected Programs fix the array/property
ports, ORDER, projection, and Named Result. They distinguish pre-SELECT
actual columns from post-SELECT expanded/reordered columns, same-named
offset/property receivers, and whole-column SET/DROP. The normal checker
accepts the original independent control. Refusals require the specific
UnsupportedOrdering issue, not an arbitrary error.

## Limited verification

- Initial repaired selection: **37/37**, run-dqwUVw / focused-test-XtKvzI.
- Expanded affected selection: **40/40**, run-yEkIs1 / focused-test-X5289x.
  These selections overlap and are not summed.
- Node fixture/corpus/import checks: **15/15**, run-o17epL /
  focused-test-iJsY5C. After the exact-code correction below, the changed
  fixture selection is **10/10**, run-HfVISY / focused-test-GyJhNs.
- Pinned MoonBit formatting and git diff --check pass.
- Read-only document metadata validation: changes=[], writes=false.
- One sandboxed guard invocation could not inspect its owned process group;
  no test ran. The authorized bounded invocation above is the actual result.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_program/unnest_order_ordinal_test.mbt \
  src/query_program/order_ordinal_test.mbt \
  src/query_program/unnest_scalar_receiver_precedence_test.mbt \
  src/query_program/unnest_pipe_edit_scope_test.mbt \
  src/query_program/joined_unnest_star_test.mbt \
  src/query_program/join_chain_test.mbt src/query_program/full_join_scope_test.mbt \
  src/query_program/pipe_scope_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  scripts/unnest-source-input.test.mjs scripts/unnest-checked-array-source-input.test.mjs \
  scripts/spec-family-imports.test.mjs
```

## Public execution obligations

The ordinary corpus and its existing --unnest-source-only consumer register
twelve new positives and three precise refusals. Intended cohort: **111
positives / 49 refusal loops** per Embedded Local/HTTPS, with 36 exact-code
refusals and 13 older broad refusal checks recorded
separately. Independent JSON control, signed/quoted position, post-SELECT
member ordering, reordered projection, colliding offset/member name, DROP,
EXTEND, SET, JOIN remapping, empty objects and NULL arrays fix expected values,
full types/nullability and column order independently of product output.

The existing consumer also checks Result.describe, stream completion,
private-column absence and same-Run resend/attach/reread without extra
acquisition/execution. Exact refusals require durable Run admission zero and
Source I/O zero. No fixture patches the lowered Program.

Initial clean f59ea4df04759553c6ce10461322360b182e0286 packed attempt
run-AgBnWb / public-query-evidence-cltoAj completed all **111 Local positives**,
including all twelve new cases, but failed at the first new exact refusal.
HTTPS was not reached. The expected public error code in the new fixture was
incorrect: the existing source preparation projection maps UnsupportedOrdering
to source_unsupported (`client_source_preparation.mbt` and its owner test).
The public bound-input checker reports an implementation-limit fact, which
the existing admitted disclosure path in client-program-preparation.mjs and
its disclosure tests maps to ClientProgramImplementationLimit. Without that
admitted fact the same projection remains non-disclosing. The corrected fixture checks that exact
existing code; it does not weaken the assertion to an arbitrary refusal or
change the diagnostic Owner. Internal tests still require UnsupportedOrdering.
This is a precise record of current classification, not a claim that it
distinguishes all invalid ordinal reasons from unsupported order expressions.
Existing broad ordinal refusal fixtures are unchanged.

This failed attempt preserved stdout/stderr, statuses and the clean revision;
artifactsRemoved=true, evidenceErrors=[]. A fresh normal clean-SHA attempt is
required after the fixture correction. Full Core, all targets, complete packed suites,
performance, hosted artifact transport and final required CI are not claimed.
General value-table AS receiver preservation remains a separate unverified
boundary; this repair does not claim to complete that feature or the full
GoogleSQL value-table profile.
