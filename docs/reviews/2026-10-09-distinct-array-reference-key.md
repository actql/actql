# DISTINCT ARRAY aggregate: resolved references and real key evidence

This is a Frontend connection repair, not a new aggregate, order owner or
uniqueness assertion. The broader Frontend completion work remains open.

## Counterexample and boundary

Inspection and focused JS execution started from main
`8d5fca248b97b113fb800aab48a0f885bd343204`:

```sql
SELECT ARRAY_AGG(DISTINCT x IGNORE NULLS ORDER BY p.x DESC) AS items
FROM pair AS p
```

The independent Values input has `(x,y)` rows `(2,100)`, `(1,200)`, `(2,300)`.
The authored complete expected Program projects only `x`, applies ordinary
row DISTINCT to `x`, then groups an ARRAY ordered by `x DESC NULLS LAST`.
The common checker accepts that Program. Baseline lowering instead misses its
sole-global-ARRAY key derivation because the argument and order reference are
not textually identical. Parenthesized `((x))` also loses the ordinary field
aggregate representation and becomes a generic expression.

The baseline two-test selection failed the complete Program comparison for
`x` versus `p.x`: `run-DK3Aod`, `focused-test-aX5JeT` (1 passed, 1 failed).
An intermediate repair resolved the order reference but still failed the
parenthesized argument: `run-3jYLbc`, `focused-test-4rinMj` (15 passed, 1 failed).
These are lowering/checker reproductions, not executions of a public Run.

## Repair

`lower_aggregate_resolved` peels grouping parentheses when finding a complete
input reference, preserving the existing checked field argument. It does not
erase signs, function calls or explicit property receivers.

The sole global DISTINCT ARRAY path reuses the existing resolved aggregate
order comparison. Equivalent qualified, quoted and parenthesized references
to the same input column get the existing `select x` then `distinct x` steps.
It retains the single projection/order, no FILTER, no hidden aggregate,
unscoped and global grouping guards. It does not assert that the original
input is unique or use unrelated columns to select a representative.

Unresolved member paths continue to the existing property expression and
common order checker. The regression checks the precise `UnresolvedOrder`
refusal for nullable property inputs and the absence of fabricated DISTINCT
steps. A different input, a sign change or a second order key still receives
Frontend `UnsupportedAggregate` in the selected DISTINCT profile.

No schema, grammar, contract pin, capacity ceiling or execution owner changes.

## Independent public obligations

`scripts/fixtures/distinct-array-reference-key-source-input.mjs` supplies a
complete independent JSON Program and seven positives plus two preparation
refusals. Submitted text explicitly selects `id > 0`, asserts only the ID key,
orders IDs and limits to four rows before deriving `x = COALESCE(amount, 0)`.
Two distinct IDs have `x=20`; x uniqueness must come from ordinary DISTINCT.
The bound and assertion are part of the authored input, not test-side Program
corrections or an execution fallback. The installed collection bound remains
1,000,000.

Descending output is `[20,10,0]`, ascending is `[0,10,20]`, and the explicitly
filtered `x >= 10` case is `[20,10]`. Expected columns contain only `items`,
a non-NULL array of non-NULL numbers. The existing public acceptance checks
Named Result rows, schema/column order, one Source read, request replay and
preparation refusal with zero Run admission and provider I/O.

The new fixture is included in the existing normal packed corpus and its
`--distinct-aggregate-order-only` selection. That selection contains 27
positive cases and 14 preparation refusals per transport, including retained
STRING and signed-order regressions. No new acceptance harness is introduced.

Nullable/computed DISTINCT ARRAY ordering and the common empty-array profile
remain separate coverage limits. This repair is not full GoogleSQL aggregate
conformance and does not change an empty result to a different contract.

## Focused evidence before packaging

Use the pinned Node/MoonBit PATH and existing bounded/nonzero-test wrapper:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 900 -- --target js \
  src/query_program/distinct_array_reference_key_test.mbt \
  src/query_program/distinct_aggregate_order_test.mbt \
  src/query_program/aggregate_property_order_test.mbt \
  src/query_program/countif_distinct_test.mbt \
  src/query_program/aggregate_filter_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  scripts/distinct-array-reference-key-source-input.test.mjs \
  scripts/distinct-aggregate-order-source-input.test.mjs \
  scripts/public-query-profiles.test.mjs
```

The product repair passed 24/24 JS (`run-18Sx3g`, `focused-test-pYeYiB`).
After tightening the property refusal assertion and formatting, its four
tests passed 4/4 (`run-WVBRbb`, `focused-test-Qx3R5w`). The Node selection
passed 14/14 (`run-JRtPn3`, `focused-test-46i5RN`). Evidence is retained under
this worktree's `_build/local-checks/attempts` and `_build/focused-evidence`.
Temporary cause-inspection failures are retained separately and are not
counted as successful checks.

Public execution is not established by these tests. Produce the five packages
normally from the committed, clean integration HEAD, independently verify
their manifest revision and SHA-256 values, and run the existing external
consumer once for the selected Local/HTTPS cohort. Record its exact source
SHA, package manifest/digests, receipts and actual outcome in the PR body.
Cross-target/full Core and required Ready CI remain separate verification.
