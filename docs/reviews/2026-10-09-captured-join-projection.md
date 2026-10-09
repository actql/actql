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

## Completed integrated public acceptance

The first normal five-package campaign at clean SHA
`7de6647c4a2add0a80d506c1a5e8afb13d7e4dd9` completed Local/HTTPS 19 positives
and 16 exact-code refusals each (`run-bevAn7`, receipt
`public-query-evidence-dsxfCB`). That is evidence for its original main baseline,
not for subsequent Host integration.

While that campaign ran, origin/main advanced to
`9cb1712ed8db4ae56f70e4e51b16fb154ec62778` with the #1112/#1113 retained Effect connections. After the gate was
terminal, this branch normally merged that main without conflicts. No incoming
Host code, owner or identity was manually rewritten. The new source-entry tests
pass 3/3 after integration (`run-vqOdnO`, `focused-test-YSoPWL`).

Final tested clean product/fixture SHA:
`5d2686057f2d6676768b8e50c5b3e5eb1252ba49`.
Normal producer and independent revision/five-digest verification followed by the
same focused public campaign pass in `run-90WlKq`:

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-captured-join-5d2686057-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-captured-join-5d2686057-pack \
ACTQL_TEST_NPM_CACHE=/private/tmp/actql-b-group-key-slot-collision-integrated-pack/npm-cache \
node scripts/test-packed-public-query.mjs --join-star-only
```

Receipt:
`/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-wKhkGl`.
All ten commands exit 0 with complete streams, no signal/error, passed/complete
campaign status and no evidence errors. Embedded Local and HTTPS each complete
19 positives and 16 exact-code refusals, including every new authored SQL/JSON
control and all prior JOIN/SET cases. No known failure is excluded.
Independent Named Result rows, describe type/nullability/column order, NULLs,
multiplicity, private-field absence, one Source acquisition, same-Run resubmission
and attach/reread counters pass. Refusals preserve zero Run admission/Source I/O.
README Local/HTTPS and the deliberate missing-generated-asset control also pass.

| Package | Original tarball SHA-256 |
|---|---|
| client-wire | `4105321db630741cba8d4573d9800f554af51b1b7eff46cdf17f651128ebcc9f` |
| sdk | `e4d0fff729f53b3cd96f97997c2bd052069d2de4152e083d84d4201852b46be6` |
| run-host-core | `013f20a6e6c63f57781b6c9c931aec19bfad8a9958670ad2b2a45f16d9917b9e` |
| local-node | `ccd5390b45ffe855386a1ca55e88e7babec2880b2848ad9288aceb5bc5115fa5` |
| node | `aa96b83e047cf3fc42b560b578fc2a32b9a38fa3f32c62dcf9f5eaff26891f4b` |

Original packs and receipts are retained. The successful external installation and
temporary Store were removed after preserving evidence (`artifactsRemoved: true`).
The submission commit adds only this evidence text; its CI remains separate from
the clean tested SHA. Parent #1128 is still an unmerged dependency. Final target
is main. No Ready transition, manual CI retry or merge was performed. Full Core,
other runtime targets, full packed/performance and broader Frontend completion
are not asserted by this focused execution unit.
