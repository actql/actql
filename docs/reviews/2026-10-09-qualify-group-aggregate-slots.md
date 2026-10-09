# Grouped aggregate aliases in QUALIFY and ORDER windows

## Boundary and counterexample

Initial main baseline: `c3e71b879989f82aab45508ff70112a91da165a9`.
This repairs the existing query-text alias rules, not a new language contract.
QUALIFY and query ORDER windows prefer evaluated SELECT aliases; qualified
input references keep their input meaning. SELECT-owned window specifications
continue to use the SELECT input snapshot.

```sql
SELECT t.x AS original, COUNT(*) AS x,
       ROW_NUMBER() OVER (ORDER BY t.x) AS rn
FROM t GROUP BY t.x
QUALIFY x > 1
ORDER BY original
```

For independently authored input `[{x:1,y:20},{x:1,y:21},{x:2,y:10}]`, the
expected row is `{original:1,x:2,rn:1}`. The two groups have counts 2 and 1.
Reading the retained input key instead of COUNT would retain the other group.
The independent complete Program passes the ordinary checker. Before repair,
the compiler emitted a filter on `x` instead of its evaluated aggregate slot.
This is a confirmed lowering counterexample; a wrong published Run was not
executed before repair.

The same alias materializer is used by inline windows in query ORDER BY:

```sql
SELECT t.x AS original, COUNT(*) AS x
FROM t GROUP BY t.x
ORDER BY ROW_NUMBER() OVER (ORDER BY x DESC), original
```

Descending COUNT orders original keys 1 then 2. The qualified-input control
`ORDER BY ROW_NUMBER() OVER (ORDER BY t.x DESC), original` orders 2 then 1.
Both complete expected Programs are handwritten; product output does not
generate them.

## Repair and independent controls

GROUP already records authored aggregate names and their evaluated output
slots. Pass that mapping to `materialize_clause_aliases` from QUALIFY and
ORDER-window callers. The materializer reuses those slots instead of assuming
an authored alias is its physical field. No COUNT reevaluation, new executor,
capacity adjustment, parser change or common contract/pin change is required.

Focused controls cover case-insensitive and backtick aliases, qualified input,
noncolliding aliases, ordinary checker admission, and discarded input columns.
Discarded QUALIFY expressions retain `Expression(UnknownReference)`; direct
discarded window keys retain `UnknownColumn` through the existing analytic key
resolver. No input is restored after grouping.

The public fixture adds three independently authored JSON Programs and nine
text counterparts/contrasts to the existing QUALIFY corpus. Expectations cover
duplicate COUNT contributions, nullable grouping keys versus nonnullable
COUNT, empty typed Results, alias versus qualified-input ordering, declared
column order, and hidden slot exclusion. Two new refusals require the existing
`ClientProgramInvalidInput` classification. The existing public consumer checks
Result descriptions, rows, admission/I/O and request reuse. Both ordinary and
`--qualify-only` corpora use the same fixtures; no new acceptance driver exists.

## Evidence

- Pre-repair: `run-KEuyh5` / `focused-test-AN770H` failed the complete Program
  comparison. The initial control placed SELECT before sort; it was corrected
  to the existing scoped sort-before-final-projection layout without changing
  values, predicate or ordering.
- Pre-repair: `run-BbCE18` / `focused-test-Nv73cd` then failed the explicit
  assertion that QUALIFY must read COUNT rather than the retained input key.
- Repaired focused JS: `run-ByoPhC` / `focused-test-df9T39`, 30/30 passed.
  Selection: `qualify_group_aggregate_slots_test.mbt`, `qualify_test.mbt`,
  `quoted_qualify_test.mbt`, `group_select_input_scope_test.mbt`, and
  `order_window_expression_test.mbt` under `src/query_program`.
- Fixture and ordinary/narrow corpus registration: `run-j1A315` /
  `focused-test-JdMZsv`, `scripts/qualify-source-input.test.mjs`, 3/3 passed.
- While adding the ORDER control, a string assertion incorrectly assumed
  noncanonical JSON member order. It was replaced by a complete independent
  Program comparison, not a change to the expected public order.

All commands use `scripts/local-checks.mjs`, the pinned Node/MoonBit toolchain,
finite time budgets and the nonzero-test guard. Formatting and `git diff
--check` are checked before publication.

## Delivery state

Public normal-pack Local/HTTPS execution, exact producer revision/digests,
submitted HEAD and exact-HEAD CI observation will be recorded after execution.
Focused lowering success alone does not establish public execution completion.
Full Core, Wasm/native, proof, performance and full packed corpora have not been
run locally for this change. No merge or manual CI rerun is performed.
