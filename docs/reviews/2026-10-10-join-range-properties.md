# JOIN parenthesized range-property connection

Base: `040eed2b1a11a3d1f7bae81b68d956d1017fac05` (main).
Status: focused compiler/checker and fixture checks pass; fresh packed
Local/HTTPS execution and submitted-HEAD CI are not established at this commit.

## Counterexample and existing contract

```sql
SELECT l.id, l.payload.score AS original_score, r.other AS payload
FROM objects AS l JOIN others AS r ON l.id = r.id MAX_OUTPUT_ROWS 12
ORDER BY ((l)).payload.score NULLS LAST, ((r)).other.score
```

Parenthesized range qualification already has an ordinary expression binder.
`((l)).payload` selects l's existing payload column; the subsequent score is
the common nullable-object property operation. An explicit value receiver that
shares a range name still selects its value, rather than being converted into
qualification. The same rules apply in SELECT, WHERE and ORDER. This introduces
no new syntax, scalar expression, execution Owner or Graph compatibility path.

At main the new selection passes its ordinary dotted-property/control test,
but three parenthesized-range SELECT/WHERE/ORDER tests fail at query lowering:
1/4, `_build/local-checks/attempts/run-woBTX1` and
`_build/focused-evidence/focused-test-O7B7rg`. These are compiler failures, not
publicly executed failed Runs.

## Repair boundaries

1. `query_join_chain.mbt::join_requires_group_scope` routes explicit property
   receivers naming a JOIN range to the existing shared row compiler. This
   applicability check does not infer value precedence or property typing. The
   shared binder/checker decides those using the actual row and range scopes.
2. `pipe_range_property.mbt` exposes that existing binder through a private
   resolver-based helper. Ordinary Pipe callers retain their current resolver.
3. The non-DISTINCT, non-grouped scoped ORDER branch in `compile_steps` calls
   the same helper with its existing alias-first, available-slot resolver.
   Removed ranges/fields remain unavailable; hidden sort columns are removed
   by the unchanged Result/projection path. DISTINCT/grouped order retains its
   own existing member/evidence handling.

The first routing repair passed 17/18 caller tests; ORDER still failed because
its scoped branch bypassed the binder (`run-YmOdZq`, `focused-test-kxkKKJ`).
The final implementation changes no common checker, planner, provider, capacity
ceiling, contract pin, generated API or public error projection. D's CTE,
Source-predicate, assert and Effect implementation is not edited.

## Independent obligations

- A complete handwritten JOIN/derive/select Program checks independently.
  SQL, Pipe and quoted parenthesized SELECTs compare its entire semantic body.
  The source explicitly specifies its independently selected ceiling of 9.
- The initial complete expectation assumed the specialized Values JOIN's
  derived bound of 9 for an omitted guard. The shared path uses the existing
  context default of 1000. Two diagnostic attempts failed that sole guard
  comparison (7/8: `run-R4lur5` / `focused-test-Ck2YUK`, and
  `run-bIyg05` / `focused-test-nEBF5g`). Explicitly author 9 in these three new
  sources instead of copying an observed default into the expected Program.
  Fields, rows and expected computation are unchanged. All public sources and
  their independent JSON order control retain their authored guard of 12.
- Independent public input ordering is id 2,2,1,3; output-alias ordering is
  id 1,3,2,2. The duplicated id has distinct peer scores 30 and 40, retaining
  both join matches and establishing a deterministic tie condition.
- A same-named range/value control distinguishes object scores 20,10,10,NULL
  from range scores 90,90,90,90. Their nullability differs accordingly.
- NULL receivers, typed empty output, LEFT nullable extension, quoted ranges,
  current AS range ordering and ordinary non-JOIN scoped ORDER are covered.
- Unknown members/scalar property receivers remain common type refusals;
  displaced ranges remain reference refusals. Four new public refusals require
  ClientProgramInvalidInput, zero admission and zero Source I/O.
- The existing public JOIN-property corpus is preserved. It now has 27
  positives and 13 refusals per Local/HTTPS, including twelve new positives
  (one independent JSON order Program). Eight older refusals use the established
  input-error category checks; do not describe those as exact-code coverage.

## Executed focused checks

Pinned Node and MoonBit tools, through existing bounded/nonzero wrappers:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_program/join_range_property_test.mbt \
  src/query_program/join_property_paths_test.mbt \
  src/query_program/source_range_property_test.mbt \
  src/query_program/pipe_range_property_test.mbt \
  src/query_program/order_property_receiver_reuse_test.mbt \
  src/query_program/join_order_test.mbt
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_program/join_range_property_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  scripts/join-range-property-source-input.test.mjs \
  scripts/public-query-profiles.test.mjs \
  scripts/analytic-offset-profiles.test.mjs
```

- JS callers 35/35: `run-kc1KFv`, `focused-test-Kgk0Kn`.
- After adding the complete expectation and explicit guard, changed tests 8/8:
  `run-k27uxA`, `focused-test-SMuNMR`. Product code is unchanged from 35/35.
- Node 18/18: `run-4MzY4W`, `focused-test-XEpRXh`.
- An initial Option API spelling failed compilation, executing no tests
  (`run-7NbQC9`, `focused-test-94PpTb`); it is not counted as a pass.

## Remaining verification

The first normal five-package attempt used clean source
`80b4fe5900928e5ddd8a773d194fb87abd71d045` and original receipt
`worktrees/.codex-scratch/public-query-evidence-H5GgP8` (guard `run-HyB2iF`).
Local passed the existing fifteen and ten new positives, then preparation of
`join-property-range-ordinary-scoped-order` returned
`ClientProgramImplementationLimit`. The remainder and HTTPS did not execute;
this attempt is failed, not partial completion of the whole cohort.

A focused compiler reproduction identifies `UnsupportedCte`: the non-JOIN
control unnecessarily declared the unused `others` CTE. The existing
`query_cte_scope.mbt::validate_cte_scope` explicitly refuses unused declarations
until they can be checked without scheduling acquisition. This is a separate
profile gap, not evidence that JOIN or range ORDER execution failed. No CTE
implementation or refusal is changed here. The complete failed query remains
in a precise compiler-refusal assertion; a second assertion checks the same
ORDER/projection with only the used `seed` and `objects` declarations. The
public ordinary control now declares those producers and their three object
parameters only. Its input rows, expected rows, ordering and column contracts
are unchanged. All JOIN cases and their authored guards remain unchanged.

The diagnostic failure is `run-4Hpumq` / `focused-test-p3Siir` (8/9).
After separating the unused-declaration refusal from the valid control,
changed JS tests pass 9/9: `run-ymy827` / `focused-test-0bcPxM`.
The adjusted public control's four Node fixture assertions pass:
`run-NDa2Rv` / `focused-test-r6M7fc`.
The first diagnostic attempted to display the private Issue type and failed
compilation, executing no tests (`run-9wu6TK`, `focused-test-86ml4p`).

The next clean source `d6118162aff9f46c66280978c87aeb606eead07d`
passed all 27 Local positives, then stopped at the existing
`join-property-invalid-4` refusal. Receipt:
`worktrees/.codex-scratch/public-query-evidence-SvB4Pm`; guard `run-k4u2A0`.
The generic input-code set omitted the existing implementation-limit code.
No product failure or diagnostic change is established here: the exact
lowerer refusal remains `UnsupportedOrdering`, pinned now for query and script
lowering. `client_source_preparation.mbt` maps it to `source_unsupported`;
the existing public Check Owner supplies an implementation-limit fact, and
`client-program-preparation.mjs` discloses that admitted fact as
`ClientProgramImplementationLimit`. This is the same classification documented
in `2026-10-09-order-property-receiver-reuse.md`; do not broaden the generic
code set or change the diagnostic Owner to pass this fixture. This one old
refusal now requires that exact code, while preserving admission and I/O zero.
The remaining refusals and HTTPS were not reached in this failed attempt.

The precise diagnostic assertions pass JS 9/9 (`run-rOqRhu`,
`focused-test-PmnADf`) and Node 4/4 (`run-1hxqcP`,
`focused-test-MRJLcC`). Product sources remain unchanged from the 35/35 caller
selection. The final public repeat must still complete both transports.

Use the normal five-package producer and existing `--join-property-only`
consumer at a clean source SHA. Compare Named Result rows and describe
contracts/column order, hidden-slot absence, and same-request resend/reattach
without another evaluation. Source-free fixtures expect zero Source reads;
they do not prove external Source acquisition/share semantics.

Full Core, full packed campaigns, other execution targets and required CI
are unverified for this unit. This repair does not claim the whole frontend
goal complete or broaden unsupported JOIN ON forms.
