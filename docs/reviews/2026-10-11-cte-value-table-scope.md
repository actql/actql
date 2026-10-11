# CTE value-table output scope

## Scope and adopted baseline

This independent Frontend unit starts from OSS main
`70b6b67f38e52b9235626efc97c50bf02780dd22`. PR #1370 is merged and complete;
its five-package and Local/HTTPS receipts are not evidence for this change.
Untyped NULL set-context remains a separate follow-up.

The selected GoogleSQL rule states that WITH introduces a value table when
its body produces a value table. See
[Value tables](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#value_tables).
This fix preserves that output kind using existing UNNEST, expression, JOIN
and Result owners. It changes neither the parser grammar nor common contracts.

## Counterexample before the fix

```sql
WITH a AS (FROM UNNEST([1,2]) old_l)
SELECT l AS value FROM a AS l ORDER BY value
```

The intended `l` is the scalar array element, not a closed row object with an
`old_l` field. At the adopted baseline, the authored CTE exports the former
receiver as an ordinary column and its consumer treats `l` as a row object.
The removed name is also incorrectly accepted by:

```sql
WITH a AS (FROM UNNEST([1,2]) old_l)
SELECT old_l FROM a AS l
```

The positive scalar-kind assertion and exact UnknownReference refusal both
fail in the fixed baseline receipt `run-elzOEG` (0/2). This is a compiler
counterexample, not a claim of observed incorrect public Run output.

## Change

- Capture a CTE's final value-table kind separately from private parenthesized
  continuation ranges. Ordinary SELECT and WITH OFFSET still produce rows.
- Bind only the retained scalar/object value to the consumer's authored range.
  Discard the CTE body's former receiver; preserve evaluated slots and nullable
  object values rather than rebuilding a non-NULL object from their fields.
- Keep existing derived-table AS scopes unchanged. Capture metadata only for
  retained CTE producers; public output still projects authored field names.
- Keep JOIN key mappings, the explicit ten-row ceiling and existing schema
  checking. No acquisition, physical task request or execution Owner is added.

An initial overly broad consumer rebinding caused three existing derived-table
regressions (`run-cNL2ou`, 10/13). The fix was narrowed to authored-producer
metadata; this failed attempt is retained rather than reported as success.
`run-senoXJ` (19/20) contains a test-development assertion that matched the word
`object` in a parameter type declaration as well as an object expression. Its
correction checks the expression key, not a changed result expectation.

## Independent acceptance

The new fixture contains three authored JSON controls and six source cases:
scalar, quoted Pipe, empty ARRAY, NULL ARRAY, shared CTE JOIN and nullable object.
Rows, column order, complete contracts, NULL and duplicate expectations are
specified independently of compiler output. The self-JOIN expects four rows
with value 2 from `[2, null, 2]`; NULL keys do not match. The old receiver and a
scalar receiver star have exact InvalidInput refusal expectations.

The same nine normal and two refusal cases are registered in the normal public
corpus and its narrow `--cte-value-table-only` selection. Fixture registration
is not public execution evidence.

## Verification before package production

Pinned Node 22.22.0 and MoonBit 0.10.12+1634b282e were used.

- Focused JS: `node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_program/cte_value_table_scope_test.mbt src/query_program/join_value_table_receiver_test.mbt src/query_program/join_on_row_range_test.mbt src/query_program/join_parenthesized_key_test.mbt src/query_program/unnest_as_value_scope_test.mbt src/query_program/unnest_offset_range_scope_test.mbt`: **36/36**, `run-b8r8E8`.
- Focused Node: `node scripts/local-checks.mjs test node --timeout-seconds 120 -- scripts/cte-value-table-source-input.test.mjs scripts/public-query-profiles.test.mjs`: **38/38**, `run-isZyGz`.
- Changed MoonBit files were formatted with the pinned stdin formatter.

These runs verify the working source committed in the following change, not
Hosted CI or packed execution. Receipts are under the worktree's
`_build/local-checks/attempts/<run>/summary.json`; focused logs are retained.
Full Core, Wasm/Native execution, Hosted CI and vendor differential tests were
not run. No merge operation was performed.


## First exact-revision packed attempt and public-entry correction

Source `38869c519bd17c7085ecb1e61ca90b302bdfc02f` produced the ordinary five
packages successfully (`run-HgpWqx`, 300-second bound). The manifest and SHA256
checks are retained at
`/private/tmp/actql-b-cte-value-table-38869c519-pack/packed-client-packages.json`.
The same-SHA nine-normal/two-refusal acceptance (`run-YnOL0q`, 300-second bound)
passed the first independent JSON control in both Local and HTTPS, then rejected
`cte-value-table-scalar` with `ClientProgramInvalidInput`. Later normal cases
and both refusal cases were not reached. This is not completed public acceptance.
Evidence is retained in
`worktrees/.codex-scratch/public-query-evidence-OajfVU` (relative to the workspace
root), including worker termination receipts. Both children terminated,
`liveChildren` was zero, the guard reported complete output and released locks,
and the actual Heavy and worktree lock paths were absent. The shared slot was
handed to E after that verification, without deleting a lock.

The first compiler tests called `compile_query_script` directly. The public
SQL/Text entry instead called `compile`, whose ordinary CTE route had not been
connected to the retained value-table metadata. Two public-entry scalar/object
regressions failed **0/2** in `run-6Usq9v`, before the routing correction. A prior
attempt `run-cYDQ8F` failed test compilation because enum values lacked explicit
type qualification; it is not a product counterexample.

The correction dispatches CTEs containing UNNEST to the existing Script
producer-binding route. It does not decide their output kind in the dispatcher:
`compile_steps` still applies SELECT, OFFSET and subsequent operators. Existing
CTEs without UNNEST retain their route. A focused selection covering the public
entry, existing CTE forms, capture predicates and parenthesized JOIN passed
**18/18** (`run-AXtjf4`). Public ordinary-row and exact hidden-name assertions
were then added as consuming-route coverage and passed **3/3** (`run-dR0stQ`).
The intermediate `run-jWGAqz` was a test-import qualification error before
execution, not a product failure. New-SHA packages and public execution must be
verified separately; the old tarballs are not relabeled.
