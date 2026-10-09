# Captured single JOIN projection entry

Date: 2026-10-09. Scope: Frontend routing to existing shared input binding.

## Existing contract and counterexample

The common Program already supports one captured Relation feeding both JOIN ports,
explicit ON keys and MAX_OUTPUT_ROWS, projected output names and ordinary order.
An independently authored complete Program in captured_join_projection_test.mbt
checks those obligations with a single typed, keyed capture and no new owner.

```aql
SELECT l.id AS original, r.id AS matched
FROM records AS l JOIN records AS r ON l.id = r.id
MAX_OUTPUT_ROWS 3 ORDER BY original
```

At adopted main `7c866a39e60dc43fdec5d0dd1fd99e74e57277ae`, compile routes
captured JOINs to the script path only for multiple JOINs or projections requiring
the shared group scope. A single explicit scalar projection instead reaches
compile_join_query, whose captured-context guard rejects it before lowerers.
Baseline `run-GPQpwJ` / `focused-test-oZ1PC8` executes both new source controls:
0/2 pass, with unwrap failures at the compile calls. The baseline runtime stack
itself does not print the Issue; source inspection identifies UnsupportedJoin.
This is compiler-entry evidence, not a pre-repair published Run reproduction.

## Minimal connection

compile now sends every query with a JOIN and a declared capture boundary to
compile_query_script, which already invokes the existing shared JOIN lowerer and
bind_script_input. It does not implement JOIN, Source acquisition, predicate
handling, capacity, identity, ordering or cancellation itself. Normal uncaptured
Values inputs retain their existing route. FULL/group/CTE routes and placement
restrictions are not loosened. D's CTE/assert/Effect processing is untouched.

Before integration, the selected four-file JS caller check passed 14/14
(`run-TfAHKN`, `focused-test-1BHMCB`). Parent #1128 supplies independently
committed SET-target and duplicate-USING input validation. Its fixed SHA
`c9877e23ae57906aae1e1f17080e20763c64dc39` is normally merged here. The only
conflict was adjacent independent JOIN fixture/control additions; both are retained.
This dependency remains unmerged, so the PR base stays its branch and final target
is main. Main's actual merge of #1111 and all existing source/identity pins remain.

Integrated JS callers pass 22/22 (`run-3yRk3i`, `focused-test-CJQ5od`):

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_program/captured_join_projection_test.mbt \
  src/query_program/join_order_test.mbt \
  src/query_program/cte_capture_predicate_test.mbt \
  src/query_program/full_select_scope_test.mbt \
  src/query_program/join_using_refusal_test.mbt \
  src/query_program/pipe_set_target_scope_test.mbt
```

The captured tests assert the authored key/ceiling, one capture and declared field
order, normal common checker admission, INNER/LEFT/RIGHT/CROSS entrance equivalence
and the separately authored JSON control. Equality with the script path verifies
routing only; independent Program and public rows/schema provide semantic controls.

Independent public fixture/normal-registration Node checks pass 5/5
(`run-Gb232H`, `focused-test-8xL3BW`) via
`node scripts/local-checks.mjs test node --timeout-seconds 120 -- scripts/join-star-source-input.test.mjs`.

## Public obligations

The ordinary JOIN cohort adds an independently authored JSON Program and three
complete SQL sources: projected shared-source JOIN, its post-JOIN amount > 20
predicate, and ORDER BY id LIMIT 2 OFFSET 1. Input includes NULL and duplicate
id=3 rows. Expected six base rows, four filtered rows and the independently fixed
two sliced rows preserve multiplicity, NULLs, types and declaration order.
All inputs require exactly one Source read session and unchanged same-Run replay.
These cases are registered in the existing normal and focused packed acceptance;
no new harness or post-lowering Program correction is introduced.

Fresh exact-SHA normal five-package Local/HTTPS execution remains pending at
this commit. Final receipt, package digests and completed counts must be recorded
separately; JS/Node checks alone do not establish public execution. Full Core,
all targets, full packed/performance and live Google differential verification are
not part of this focused evidence. No manual CI retries or merge are requested.

## Separate follow-up

Source inspection also finds the standalone uncaptured Values JOIN specialization
computing a cartesian bound rather than consuming part.max_output_rows. This path
is distinct from the captured route repaired here. Its exact effect must be fixed
with an independently authored small-ceiling counterexample, not by changing this
unit's public expectations or the common Host ceiling. This record does not claim
that a public Run has reproduced that separate issue. The broader goal remains active.
