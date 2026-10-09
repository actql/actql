# Ordinary aggregate inputs in named WINDOW declarations

## Existing contract and fixed counterexample

The selected [GoogleSQL window-call rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/window-function-calls)
allow ordinary aggregates as window inputs after GROUP evaluation. Named WINDOW
specifications preserve the same key meaning, with query-local declaration
scope and existing inheritance restrictions. SELECT window keys cannot read
sibling SELECT aliases. This connects those existing rules; it introduces no
new aggregate, window law, execution owner or capacity allowance.

```sql
SELECT t.x, ROW_NUMBER() OVER w AS rn
FROM t
GROUP BY t.x
WINDOW w AS (ORDER BY COUNT(*) DESC, t.x)
ORDER BY rn
```

For `(x,y) = (1,20), (1,21), (2,10)`, independent expected rows are
`[{"x":1,"rn":1},{"x":2,"rn":2}]`. The complete expected GROUP -> ANALYTIC
-> SELECT -> SORT Program was authored directly in
`src/query_program/named_window_aggregate_inputs_test.mbt`. Before the fix,
that control passed the ordinary checker but both this source and the implicit
global-group source failed the Frontend path: 1 passed, 2 failed
(`run-TCznhq`, `focused-test-MWOVdB`). Those logs remain preserved.

## Implementation boundaries

`query_syntax/query_window.mbt::window_definitions` now supplies the existing
bounded aggregate extractor to declaration keys. The private
`used_named_window_aggregates` collects only parser-owned references actually
present in resolved SELECT/QUALIFY window specifications, including inherited
specifications and replacements. It uses the existing work budget; unused
declarations do not introduce a GROUP or evaluate their aggregate arguments.

`query_syntax/query.mbt::sql_term` attaches those calls to its SQL GROUP
projections or creates the existing implicit global GROUP before HAVING and
ANALYTIC. The existing lowerer performs input-scope resolution and aggregate
slot reuse. The declaration is not re-expanded per window consumer.

A secondary regression fixed the timing of HAVING validation. In
`SELECT ROW_NUMBER() OVER w AS rn FROM t HAVING TRUE WINDOW w AS (ORDER BY COUNT(*))`,
the used declaration establishes implicit aggregation even though it appears
later in source. The added regression initially failed with 27/28 selected
tests passing (`run-w6iUJb`, `focused-test-7vTjMG`). HAVING's grouping requirement
is now checked after window resolution. HAVING without GROUP remains a typed
syntax refusal, including when the only aggregate declaration is unused.

No public AST/API, grammar body, machine Program, schema, contract pin, wire,
publication rule or common owner is changed. There is no compatibility adapter,
alternative executor, lowered-Program patching, key evidence invention or
budget adjustment. D-owned CTE/assert/Effect code is not edited.

## Independent public controls

The existing named-window fixture is registered in both normal packed
acceptance and its `--named-window-only` selection. Fifteen new successes
include two independently authored JSON Programs and thirteen authored sources.
After id > 0, fixture groups have counts 1,1,2 for id 1,2,3:

| Source meaning | Independent expected result |
|---|---|
| Descending COUNT(*), then id | id 3,1,2 with row numbers 1,2,3 |
| Partition by COUNT(*), then id | id 1,2,3 with row numbers 1,2,1 |
| COUNT(amount), nullable amount | id 3,2,1 with row numbers 1,2,3 |
| COUNT(*) AS id, qualified grouped input | original 3,1,2; count 2,1,1; rn 1,2,3 |
| Hidden QUALIFY window ordered by SUM(amount) | id 3 only |
| Explicit grouping on empty input | Empty typed Result |
| Implicit global aggregation on empty input | One row, rn 1 |
| Unused SUM(1 / 0) declaration | Original ungrouped rows, no demanded error |
| LAG(COUNT(*)), named COUNT order | id 1,2,3 with values 2,1,NULL |
| SUM(SUM(amount)), named COUNT order and cumulative ROWS | id 1,2,3 with values 60,80,60 |

Additional cases cover declaration inheritance, quoted names, HAVING before
window evaluation and multiple consumers of one evaluated aggregate. Four
new refusals assert `ClientProgramInvalidInput`: sibling-alias aggregate input,
nested window in a declaration, ungrouped HAVING with an unused aggregate,
and a dropped nongrouped ordering column. Each has zero Run admission and
Source/provider I/O. Existing declaration/scope/frame refusals remain present.

Public checks compare independent rows and complete Result.describe type,
nullability and column order, hidden-column absence, stream termination,
one Source acquisition and unchanged counters on same-Run resend/reattach
and Result rereading. No expected Program or result comes from compiler output.

## Fixed revisions and evidence

- Initial main: `8c791b0f12d97e0ae5deb1a1b8fc51a9903be4f7`.
- Initial implementation: `6752ce1bce7b667a17cff20939dd7937f84aac0f`.
- Adopted main including #1104:
  `42790dcce4caa13bf1755999258f8541d430f748`.
- Normal merge: `9f5508358bde8bdb3ef1f439414b385f00e6fc08`; no conflicts,
  existing history declarations retained.
- Final product/fresh-pack source:
  `b088013ffa72f73450cc4b02296fd9521df203de`.

The first packed wrapper was waiting for another worktree's verified live
heavy gate when #1104 entered main. Only B's waiting wrapper (PID 56699) was
stopped, terminal exit 143, before any producer or consumer started. No shared
lock or other worktree process was stopped. That invocation is not test evidence.
Main was then normally merged and the combined operand/declaration fixtures
were added before producing one final fresh package cohort.

Executed limited checks:

- Initial fixed counterexamples 3/3 (`run-691Tth`); an earlier helper signature
  compile failure (`run-XWXfrH`) did not execute tests and is not a pass.
- Named/grouped/window callers 28/28 (`run-2LGU7d`).
- Existing HAVING/GROUP BY ALL callers 28/28 (`run-xvv5sj`).
- Integrated callers including #1104 operands 64/64 (`run-N5mMhP`,
  `focused-test-oDOCkU`).
- Final fixture Node tests 3/3 (`run-5tVqBq`, `focused-test-B9xMya`).
- Fresh normal five-package Local/HTTPS at b088013ff: each **28 successes and
  14 pre-admission refusals**, `run-Glcxpm`, receipt `public-query-evidence-1MbitU`.

The receipt is passed/complete; all ten commands exited 0 without signals or
evidence errors. External installation artifacts were removed after evidence
persistence. Logs and receipt remain at:

```text
/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-1MbitU
```

Focused evidence is under this worktree's `_build/local-checks/attempts` and
`_build/focused-evidence`. The selected commands used the pinned Node/MoonBit
toolchain and existing bounded/nonzero-test guard, with no competing gates:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_program/named_window_aggregate_inputs_test.mbt \
  src/query_program/named_window_test.mbt \
  src/query_program/window_group_aggregate_inputs_test.mbt \
  src/query_program/window_scalar_projection_test.mbt \
  src/query_program/qualify_group_aggregate_slots_test.mbt \
  src/query_program/window_aggregate_operands_test.mbt \
  src/query_program/having_aggregate_test.mbt \
  src/query_program/group_having_implicit_alias_test.mbt \
  src/query_program/having_projection_slots_test.mbt \
  src/query_program/sql_group_by_all_test.mbt
node scripts/local-checks.mjs test node -- scripts/named-window-source-input.test.mjs
```

The serial normal producer, independent manifest/digest verifier and selected
consumer ran within the repository guard, budget 1200 seconds, from
`/private/tmp/actql-b-named-window-aggregate-b088013ff-packed.mjs`:

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-named-window-aggregate-b088013ff-pack
# Verify the exact revision and independently recompute all five SHA-256 values.
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-named-window-aggregate-b088013ff-pack node scripts/test-packed-public-query.mjs --named-window-only
```

| Package | SHA-256 |
|---|---|
| client-wire | `7b2ad28f42998039cba6b9a1d14dba5b0eff0289fcbfc1bd500199286b54c4f3` |
| sdk | `f05a4f73173750b1f06212a8219070edf46ae2204970ba812c53a92b4026d518` |
| run-host-core | `045139bca9a5eae45a20c93af9751ef9dc434face642b21768b44ab7ebfd1f90` |
| local-node | `fed3d4df9bb0b99c71a2964552dcb833a46fce9dcebecb675101fa22681657b4` |
| node | `fb65f5d346e0c597457ce8705d1d5ac9e68e2f23467d1d9d72518ed615a55fb3` |

## Unverified coverage

The subsequent evidence-only documentation commit is not the packed source.
Its CI is separate evidence. Full Core, all-target execution, full packed
campaigns, proof/performance and live Google differential validation were not
run. No manual CI rerun or PR merge was performed. The broader text-to-Program
goal remains active; this establishes only the selected named-window connection.
