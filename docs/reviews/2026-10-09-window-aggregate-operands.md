# Ordinary aggregates as window function operands

## Scope and reference

This Frontend unit connects ordinary aggregate expressions inside window
function arguments to existing GROUP outputs and ANALYTIC functions. It follows
the inline OVER-key connection in #1099, which is now merged into main.
The selected [GoogleSQL window-call rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/window-function-calls)
place ordinary aggregation before window evaluation and allow aggregates as
window operands. SELECT-owned arguments cannot read sibling SELECT aliases;
query ORDER-owned arguments retain SELECT-alias precedence. Neither ordinary
aggregate nesting without OVER nor window-inside-window evaluation is added.

The grammar's existing expression positions and common Program contracts are
unchanged. This is not a new executor, aggregate owner, serialization profile,
capacity rule or implicit frame. No schema or contract pin changes are needed.

## Independent counterexamples and implementation

For input `(x,y) = (1,20), (1,21), (2,10)`:

```sql
SELECT t.x, LAG(COUNT(*)) OVER (ORDER BY t.x) AS value
FROM t GROUP BY t.x ORDER BY t.x

SELECT t.x, SUM(SUM(t.y)) OVER (
  ORDER BY t.x ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
) AS value
FROM t GROUP BY t.x ORDER BY t.x
```

The first must return value NULL, 2; the second 41, 51. Complete expected
Programs were authored independently as GROUP -> ANALYTIC -> SELECT -> SORT
in `src/query_program/window_aggregate_operands_test.mbt`. Before the fix, both
controls passed the ordinary checker, but the source forms failed: COUNT(*)
was not parsed as a navigation argument, and nested SUM reached lowering as
an unknown scalar function. The pre-fix gate had 1 passed and 2 failed tests
(`run-eIlaG3`, `focused-test-uyt3I1`); those logs are retained.

`query_syntax/qualify.mbt::window_expression` now invokes the existing bounded
aggregate extractor for window operands. `query_syntax/query.mbt::aggregate`
accepts an optional extraction context for that caller. Calls are attached to
the owning clause only after OVER is confirmed. Existing GROUP slot reuse and
scope-aware lowering perform the remaining work. Nested ordinary aggregates
without OVER retain a typed syntax refusal. Existing ROWS-frame and navigation
offset constraints are preserved, rather than inferred or weakened.

Focused regressions include scalar composition, named OVER references, QUALIFY,
query ORDER, COUNTIF, implicit global SQL grouping, aggregate reuse under an
alias collision, sibling-alias refusal, nested-window refusal, Pipe implicit
grouping refusal, missing-frame refusal and row-dependent offset refusal.

## Public independent controls

The existing normal packed corpus and `--window-scalar-only` consumer now
include two independent JSON Programs and ten new source successes. No test
patches the generated Program. After the source predicate id > 0, groups at
amount 10, 20 and NULL have counts 1, 2, 2 and sums of id 3, 6, 6:

| Case | Independent expected n in ascending amount, NULL last |
|---|---|
| LAG(COUNT(*)) | NULL, 1, 2 |
| SUM(SUM(id)) with explicit cumulative ROWS | 3, 9, 15 |
| COUNTIF(COUNT(*) > 1) with the same ROWS | 0, 1, 2 |
| COALESCE(LAG(COUNT(*)), 0) + 1 | 1, 2, 3 |

Additional sources cover empty typed results, named windows, typed parameter
offsets and reuse of COUNT under an amount alias collision. Two ORDER sources
project `-records.amount AS amount`: SUM(amount) must consume that alias,
whereas SUM(records.amount) consumes input. Their independently expected
original-key orders are respectively `[null,20,10]` and `[20,null,10]`.
This distinguishes correct scope resolution from a superficially matching
sort. Public fields, complete Result.describe contracts/nullability/column
order, ordered rows, hidden-column absence, stream termination, one Source
read, same-Run resend/reattach and unchanged reread acquisition counters remain
checked by the existing public acceptance helpers.

Five added refusal cases cover ordinary aggregate nesting, sibling aliases,
Pipe implicit grouping, missing frames and row-dependent offsets. Each checks
its typed public error with zero Run admission and Source/provider I/O.

## Fixed sources and executed evidence

- Product source: `e5865369f077648a5ef643e0a5e5bcb3151d2da6`.
- Adopted main: `40a7f10de3a4a2d5a652411f09402a9d8d1aabc9`.
- Normal integration and final fresh-pack source:
  `07207b34727cfba6a156507bd1cdf1aaa40beead`. No conflicts were resolved;
  existing history declarations were retained. Main changed Host alias
  generation and client-wire inputs, so integrated packages were produced
  again rather than relabelling the earlier distribution evidence.
- Pre-integration focused JS: 49/49 (`run-UDBaAO`, `focused-test-un6MWy`).
- Fixture Node: 3/3 (`run-5vjcbE`, `focused-test-ovF83m`).
- Integrated focused JS: 49/49 (`run-mgoDtG`, `focused-test-GUbVFW`).
- Original fresh-pack Local/HTTPS: each 24 successes, 12 pre-admission
  refusals and one expected execution failure; `run-jxl0Hd`, receipt
  `public-query-evidence-sKHQlm`, attributed only to e5865369f.
- Integrated fresh-pack Local/HTTPS: the same unchanged cases all passed;
  `run-moxiBq`, receipt `public-query-evidence-gmScxD`, attributed to 07207b347.
  All ten receipt commands exited 0 without signals; receipt status is
  passed/complete with no evidence errors. Its successful external
  installation artifacts were removed after logs and evidence were saved.

Focused evidence is below this worktree's `_build/local-checks/attempts` and
`_build/focused-evidence`. Public receipts and command logs are retained at:

```text
/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-sKHQlm
/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-gmScxD
```

The normal exact-source producer, independent SHA-256 verifier and selected
consumer ran serially through the repository guard, with a 1200-second
budget. The checked-in toolchain pins were used. Commands inside the wrapper:

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-window-aggregate-operands-07207b347-pack
# Independently verify manifest revision and each tarball's SHA-256.
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-window-aggregate-operands-07207b347-pack node scripts/test-packed-public-query.mjs --window-scalar-only
```

The retained wrapper is
`/private/tmp/actql-b-window-aggregate-operands-07207b347-packed.mjs`.
The five integrated tarball SHA-256 values are:

| Package | SHA-256 |
|---|---|
| client-wire | `7b2ad28f42998039cba6b9a1d14dba5b0eff0289fcbfc1bd500199286b54c4f3` |
| sdk | `f05a4f73173750b1f06212a8219070edf46ae2204970ba812c53a92b4026d518` |
| run-host-core | `045139bca9a5eae45a20c93af9751ef9dc434face642b21768b44ab7ebfd1f90` |
| local-node | `8248aec8ad9b82ae83612d7bfede2fa2e99708ebf16c257f028f140b638030f8` |
| node | `fb65f5d346e0c597457ce8705d1d5ac9e68e2f23467d1d9d72518ed615a55fb3` |

## Remaining coverage

The subsequent evidence-only documentation commit is not the packed source.
Submitted-HEAD CI must be reported separately. Full Core, all-target execution,
full packed campaigns, proofs, performance and live Google differential tests
were not run. This does not establish the overall Frontend goal as complete.

Ordinary aggregates in WINDOW declaration keys remain a separate connection:
`window_definitions` currently calls `window_specification` without aggregate
extraction. Named OVER references tested here have ordinary column keys; their
success is not evidence for `WINDOW w AS (ORDER BY COUNT(*))`. No common-owner
dependency blocks this completed operand connection.
