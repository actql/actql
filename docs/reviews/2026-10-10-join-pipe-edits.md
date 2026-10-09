# Post-JOIN current-column edits

Status: localized Frontend repair and focused checks complete; clean-source
packed execution is pending. Main base: `040eed2b1a11a3d1f7bae81b68d956d1017fac05`.

## Adopted meaning and confirmed connection gap

The existing [query text contract](../spec/query-text.md) defines SET against
the pre-assignment current row, DROP against current names and EXTEND as adding
new current columns. A surviving range retains its original evaluated slots;
EXTEND does not retroactively add a column to an old range. Explicit AS instead
creates a fresh binding. None of these meanings depends on whether the current
Relation came from one JOIN or several JOINs.

All three independently authored ordinary Program controls pass the common
checker, but these accepted queries fail compilation on the main base:

```sql
FROM t AS l
|> JOIN r AS rr ON l.x = rr.k MAX_OUTPUT_ROWS 10
|> SET y = y + 10
|> SELECT y AS current, l.y AS original, rr.k AS matched
|> ORDER BY original

FROM t AS l
|> JOIN r AS rr ON l.x = rr.k MAX_OUTPUT_ROWS 10
|> DROP y
|> SELECT l.y AS original, rr.k AS matched
|> ORDER BY original

FROM t AS l
|> JOIN r AS rr ON l.x = rr.k MAX_OUTPUT_ROWS 10
|> EXTEND y + 10 AS current
|> SELECT current, l.y AS original, rr.k AS matched
|> ORDER BY original
```

The gap is the routing predicate `join_requires_group_scope()`: these operators
were not recognized as requiring the shared current-row scope. Single JOINs
therefore used the projection-only specialization. Add the three existing
operation variants to that predicate and reuse the common JOIN compiler and
`compile_steps()` column-edit logic. Keys, predicates, explicit output ceilings,
value types, expression evaluation and Result publication remain with their
existing owners. No new execution path, fallback, law/schema pin, grammar or
resource-limit change is introduced. CTE/assert/Effect and other owners are not
edited. The independent Pipe DISTINCT fix in #1160 is not a dependency.

## Independent regressions and public expectations

`join_pipe_edits_test.mbt` contains complete independently authored ordinary
Programs for each edit and compares them with query-only lowering; it also sends
the sources through script lowering and the normal checker. Additional failures
require UnknownReference for a dropped current name or nonexistent old-range
member, UnknownColumn for a missing SET target and AmbiguousColumn for a
duplicate current SET target.

Ten positive fixtures and four exact-code refusal fixtures are added to the
existing Pipe range corpus and its ordinary packed registration. The two public
JSON controls are authored separately from compiler output. Text is never patched
after lowering. Both inputs retain their original JOIN key and ceiling 10.

The provider rows are `(id,amount) = (2,20), (1,NULL), (2,20)`; the right input
is the one-row Relation `k = 2`. Expected public fields are declared in order
`current, original, amount, matched`:

| Case | Independent expected rows |
|---|---|
| INNER JOIN then SET id = id + 10 | Two `{current:12, original:2, amount:20, matched:2}` rows |
| INNER JOIN then DROP id, expose original via l.id | Two `{current:2, original:2, amount:20, matched:2}` rows |
| INNER JOIN then EXTEND id + 10 AS current | Same two rows as SET; old range does not contain current |
| LEFT JOIN then SET | `{current:11, original:1, amount:NULL, matched:NULL}`, then the two INNER rows |
| Typed empty source | Empty Result retaining declared column order and nullability |

Quoted ranges, parameterized replacement and explicit fresh AS are positive
cases. The public refusals require `ClientProgramInvalidInput` for dropped
current access, nonexistent extended old-range access, missing SET target and
EXTEND name collision. Existing acceptance checks compare Result.describe and
exact rows, require one Source acquisition, resend/attach to the same Run with
no additional I/O, and zero admission/provider I/O for preparation refusal.

## Executed focused evidence

Worktree: `/Users/t14i/workspace/20260822/worktrees/actql-frontend-qualify-group-aggregate-slots`.
Pinned Node 22.22.0 and MoonBit `0.10.12+1634b282e`; bounded/nonzero-test wrappers.

- Pre-repair query-only boundary: 0/3, exit 2; independent Programs checked.
  `run-mcJ5T5` / `focused-test-YzNPlL`.
- Pre-repair script boundary, checked before query-only compilation: 0/3,
  exit 2. `run-o1iWWc` / `focused-test-tmmSfm`. This distinguishes the public
  script connection failure from an internal query-only limitation; it is not
  an executed public Run failure.
- Initial routing repair: 3/3, exit 0. `run-0wMX8P` / `focused-test-HH1YAS`.
- Final edited-boundary and affected caller checks: 52/52 JS, exit 0.
  `run-zqaNpg` / `focused-test-WeJoa1`.
- Fixture and ordinary-corpus registration: 6/6 Node, exit 0.
  `run-RaoOQ2` / `focused-test-FLknpj`.

Evidence paths above are relative to `_build/local-checks/attempts` and
`_build/focused-evidence`, respectively. Commands:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_program/join_pipe_edits_test.mbt \
  src/query_program/pipe_join_ranges_test.mbt \
  src/query_program/join_order_test.mbt src/query_program/join_chain_test.mbt \
  src/query_program/pipe_set_target_scope_test.mbt \
  src/query_program/pipe_set_window_test.mbt \
  src/query_program/pipe_extend_window_test.mbt \
  src/query_program/extend_range_snapshot_test.mbt \
  src/query_program/pipe_rename_target_scope_test.mbt \
  src/query_program/join_pipe_limit_tail_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  scripts/pipe-join-ranges.test.mjs
```

Unverified: fresh exact-source five-package Local/HTTPS execution, submitted HEAD
CI, Wasm/native execution and broader SQL/Pipe conformance. No full Core, manual
CI retry or merge has been run for this unit.
