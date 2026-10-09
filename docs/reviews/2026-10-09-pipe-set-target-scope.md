# Pipe SET: reject ambiguous current targets

Date: 2026-10-09. Status: minimal Frontend correction and focused checks passed;
fresh packed Local completed all 14 positives but stopped on an existing JOIN
refusal. Complete Local refusals, HTTPS and submitted-HEAD CI are not established.

## Existing requirement and counterexample

Adopted main is `ffe46cdae6d064a60da517dec2937eeaee4a1c30` (fetch reconfirmed).
Parent #1125 remains unmerged at `478a3981ec439f7830ce694861197e325de4100c`,
following #1121/#1116/#1115/#1111. Final integration target is main.

The normative query-text SET section already requires each target to exist
exactly once. The selected
[GoogleSQL SET reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/pipe-syntax#set)
also distinguishes current columns from immutable range values. This is an
implementation correction within that contract, not a new restriction.

```aql
FROM t AS l
|> RIGHT JOIN t AS r ON l.x = r.x MAX_OUTPUT_ROWS 10
|> SET x = 99
|> SELECT l.x AS left_x, r.x AS right_x
```

Both operands expose a current x. SET must reject its ambiguous target even
though its value is constant and the final SELECT names qualified inputs.
Baseline `run-KnO4aJ` / `focused-test-JMqDDl` fails 0/1: the compiler accepts the
input and emits an ordinary JOIN plus `derive: {aql_pipe_set_4: {literal: 99}}`.
The test retains the complete accepted Program in its failure log. This proves
incorrect compiler acceptance, not a pre-fix public Run execution failure.

An earlier DATA/CROSS JOIN probe stopped at existing UnsupportedCte before this
target boundary (`run-OcYLOr` / `run-04M2xc`). It is not evidence of this defect
or a reason to change D's CTE handling. The RIGHT JOIN probe reaches the shared
joined-row scope and isolates the actual SET target defect.

## Minimal correction and independent controls

`compile_steps` previously tested only whether any current column matched the
target, then replaced every matching visible binding. SET now counts matches
under existing identifier resolution: zero gives existing UnknownColumn, more
than one gives existing AmbiguousColumn, and one follows the unchanged assignment
path. Duplicate assignment targets retain DuplicateOutput. DROP's deliberately
different multiple-match semantics and the general presence helper are unchanged.

Four bare/backtick case variants are checked with scalar and inline window
assignment values. Refusals assert the exact cause, not Err(_). The independently
authored complete ordinary Program verifies RIGHT JOIN conversion, original
range slots, replacement slot, projection, Result fields and MAX_OUTPUT_ROWS 10.
A separate common checker test accepts USING's single coalesced current target
even though both immutable operand ranges retain their own key slots.

The existing normal/focused JOIN-star public cohort gains four positive controls:
independent JSON, equivalent text, an unmatched nullable original range and
coalesced USING. Independent rows distinguish replacement values from original
values and retain duplicate multiplicity (six self-JOIN rows, including four
id=3 pairs). Describe contracts preserve column order and replacement/original
nullability. Eight exact-code target refusals cover bare/backtick case variants
with scalar/window assignments and require zero Run admission and Source I/O.
No lowered Program is repaired by the test. Existing shared acceptance checks
retain acquisition once, same-Run resend/attach/reread and unchanged counters.

No grammar, Program, expression, identity law, serialization, checker, provider,
capacity, Result order, diagnostic owner or pin changes are required. Source
predicates, JOIN arguments, limits, row/schema expectations and execution owners
remain unchanged. No fallback or separate execution path is introduced.

## Focused evidence and remaining coverage

Pinned JS, through the bounded/nonzero wrapper:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_program/pipe_set_target_scope_test.mbt \
  src/query_program/pipe_set_window_test.mbt \
  src/query_program/pipe_join_ranges_test.mbt \
  src/query_program/full_join_scope_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  scripts/join-star-source-input.test.mjs
```

JS: 16/16 (`run-pgpy4Z`, `focused-test-9AfvMt`). Node: 3/3 (`run-YyeCnR`,
`focused-test-EjyKXA`). Independent controls also passed 3/3 before the expanded
window refusal coverage (`run-orZbpP`). Formatting and diff whitespace checked.

Fresh normal five-package packing and the existing `--join-star-only` Local/HTTPS
consumer were executed as recorded below; their complete acceptance remains
unverified. Submitted-HEAD CI, three-target runtime coverage,
full Core/full packed/performance and live Google differential execution remain
unverified. Draft preparation is not merge CI; the broader Frontend goal remains
active. No other worktree, D's CTE/assert/Effect code or common execution owner
was edited.

## First packed attempt: independent control correction

Normal five-package production and exact revision/digest verification passed at
`7cf526f286794126ca25a0fc3ae16a0066d4b789` (`run-K8Fytl`). The existing ten
Local positives passed before the new independent JSON control was rejected
at preparation with ClientProgramInvalidInput. Receipt
`public-query-evidence-JQCgSD` retains complete command 010 streams and exit 1.
Later positives/refusals and HTTPS are not established by this run.

The independent JSON authoring error was a snapshot derive map writing current
over an already selected current column. The normative derive map is add-only;
ordered derive arrays have their own shadow contract. The control now selects
only original/matched and adds current as a new slot. No expected value, type,
column order, multiplicity, limit or Source acquisition count changed. The
Frontend correction and its independent complete MoonBit Program remain
unchanged. This is a fixture correction, not a product execution fix or an
adjustment of the desired public result.

The next fresh pack at `ecbe671c241e9857ca73361994de2250cb7c9df4` passed
the ten prior Local positives and the independent JSON control, then refused
the equivalent text (`run-KLZuz9`, `public-query-evidence-SWbgOd`). Its new
FROM-headed Pipe controls inherited the old SQL fixtures' format: sql. The
existing common preparation distinguishes that form and returns WrongQueryForm;
bounded exact-cause diagnostic `run-7osehw` confirms sql rejection and aql-text
preparation success for the same authored source. The controls now use aql-text,
matching the existing Pipe routing. No source, expected value/type/order, limit,
product routing or diagnostic rule changed. This attempt does not establish
later Local cases or HTTPS. Its failed receipt remains available.

The source-free RHS script control additionally uses numeric x/k inputs (the
unrelated Values orders fixture has string id and is not an equivalent JOIN
typing control). Final direct JS callers pass 17/17 (`run-sbV1h8`,
`focused-test-iFM45d`), including the script route. The corrected public-format
fixtures pass Node 3/3 (`run-df5M6G`, `focused-test-XRNMal`). Common JOIN type
checks were not relaxed to admit the earlier mismatched diagnostic fixture.

## Final packed attempt and unresolved public refusal

Tested clean product/fixture SHA:
`94bacea700f9f28ddbffecbb770cc74c6302074b`. Normal five-package production and
independent exact revision/digest checks passed (`run-55paeq`). Invocation:
`/private/tmp/actql-b-pipe-set-target-94bacea70-packed.mjs`, using the pinned
environment and shared heavy slot. Its producer and consumer steps were:

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-pipe-set-target-94bacea70-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-pipe-set-target-94bacea70-pack \
ACTQL_TEST_NPM_CACHE=/private/tmp/actql-b-group-key-slot-collision-integrated-pack/npm-cache \
node scripts/test-packed-public-query.mjs --join-star-only
```

The original tarballs, with SHA-256 checked against the manifest and receipt:

| Package | SHA-256 |
|---|---|
| client-wire | `4105321db630741cba8d4573d9800f554af51b1b7eff46cdf17f651128ebcc9f` |
| sdk | `e4d0fff729f53b3cd96f97997c2bd052069d2de4152e083d84d4201852b46be6` |
| run-host-core | `41a71cbf8c1deb5b4b7a136d9596af60f335a8cac4fbde7f0643494af5597dfc` |
| local-node | `562a24a1e77088efa53e0c03c574afa6193d60c1d7780dab4623e7fb58faf9f9` |
| node | `aa96b83e047cf3fc42b560b578fc2a32b9a38fa3f32c62dcf9f5eaff26891f4b` |

Receipt:
`/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-0ioEor`.
All 14 Local positives passed, including all four new controls, unchanged rows,
describe schemas, multiplicity, NULLs, ranges, private-field absence, acquisition
once and same-Run replay/read counters. README Local/HTTPS and intentional missing
asset checks also passed. The main acceptance command then exited 1, with complete
streams and no signal, on old fixture join-star-refuse-1:

```aql
SELECT * FROM records AS l JOIN records AS r
USING (id, `ID`) MAX_OUTPUT_ROWS 10
```

Actual public code: ClientProgramImplementationLimit. The existing refusal
expects an input-error code. The existing shared JOIN lowerer recognizes repeated
case-insensitive USING keys but raises UnsupportedJoin, which the unchanged
diagnostic owner classifies as a coverage refusal. That code path was not changed
by the SET correction. Reclassifying an invalid authored USING list is a separate
Frontend diagnostic correction; do not weaken the fixture to hide it.

This run establishes the 14 Local positives, not complete cohort acceptance.
Later old refusals, the eight new exact-code SET refusals and the main HTTPS
cohort were not reached. The receipt records failed/incomplete campaign status,
complete child-command streams and no evidence errors. Failed logs, command
metadata and original pack artifacts are retained for diagnosis; the helper
removed the external installation and temporary Store after preserving evidence
(`artifactsRemoved: true`). At that SHA the Draft was incomplete for public acceptance.
The submitted commit adds only this evidence record; its CI remains separate
from the tested SHA. No Ready transition, manual CI retry or merge was made.

## JOIN input refusal correction

The follow-up isolates the existing duplicate USING defect instead of weakening
the public input-error expectation. Source inspection confirms MAX_OUTPUT_ROWS 0
already fails the parser's existing positive safe-integer rule; no parser or bound
change is necessary. The shared star exclusion path likewise retains UnknownColumn
for a missing field. D's predicate/limit/CTE/assert/Effect paths remain untouched.

The duplicate USING list also exposed a projection-only bypass:

```aql
SELECT l.x AS original FROM t AS l
INNER JOIN t AS r USING (x, `X`) MAX_OUTPUT_ROWS 10
```

Baseline `run-K5DJQR` / `focused-test-XCkzKa` passes two controls and fails the
third, printing the complete accepted Program with repeated x/x join keys.
This is compiler acceptance evidence; a pre-fix public Run was not executed.
Star/shared scope instead recognized the repetition but reported UnsupportedJoin.

`validate_join_using_names` uses existing case-insensitive same_name and existing
DuplicateOutput. Both ordinary join_keys and shared join_chain_keys call it
before constructing pairs or output fields. The defensive merged-key guard
retains that same cause. Duplicate keys therefore cannot hide behind a projected
subset. No duplicate ON condition is deduplicated or newly forbidden. Genuine
unsupported non-equijoin ON and FULL identity refusals remain unchanged.

Direct JS callers pass 17/17 (`run-JcZeMy`, `focused-test-IikGKl`): INNER/LEFT/
RIGHT/FULL, normal/script entry, star/scalar projection, valid quoted keys with
authored order, repeated ON and SET target scope. Existing exact refusal tests
now distinguish invalid USING from genuinely unsupported ON. No runtime owner,
checker, public diagnostic owner, grammar/schema/pin or canonical vector changes
are required. This correction is kept in its own Conventional Commit within the
same small PR, whose public cohort it closes.

The unchanged existing four refusal sources now require the exact input-error
code, rather than an unspecified input-code set. Four scalar hidden-key refusals
and one repeated-ON positive extend the same normal/focused cohort: 15 positives
and 16 exact-code refusals, including the prior SET fixtures. Fresh Local/HTTPS
execution at the combined clean SHA remains to be established.

The independent Node fixture checks pass 4/4 (`run-6WVZBy`,
`focused-test-0ES3Jk`) through `node scripts/local-checks.mjs test node
--timeout-seconds 120 -- scripts/join-star-source-input.test.mjs`. These checks
establish authored expectations and normal-cohort registration, not Host execution.

### Captured Source entry ordering

The first combined clean SHA `5592356e6d5b55a017eab696fa1b251770057ea5`
produced all five normal packages and passed independent digests (`run-pFwyXy`).
Receipt `public-query-evidence-veIDaD` records all 15 Local positives and the four
existing exact-code refusals, then a failure at the first new projection-only
USING refusal. Later refusals and the main HTTPS cohort were not reached.
The standalone JOIN entry returned UnsupportedJoin for a captured context before
validating the authored USING list. This differs from the Values-only test route.
The new captured-context regression failed 3/4 before correction (`run-UhZ4t7`,
`focused-test-4l8XMs`). The entry now invokes the same validation before its
existing coverage checks. It does not accept additional captured JOIN shapes or
change their execution, predicates, bounds, acquisition or ownership.

Focused JS and direct callers pass 18/18 after that correction (`run-doZFin`,
`focused-test-gWfnWs`), using the same five-file command above plus the new case.
The previous 17/17 and failed packed run remain evidence for their own states;
fresh combined-SHA Local/HTTPS acceptance remains necessary.

## Final combined public acceptance

Tested clean product/fixture SHA:
`989bc136d13594dc3b2b878e423a363c12806a94`.
The normal producer, independent five-digest/revision verification and focused
public cohort completed successfully in `run-tgDfEj`:

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-pipe-set-target-989bc136d-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-pipe-set-target-989bc136d-pack \
ACTQL_TEST_NPM_CACHE=/private/tmp/actql-b-group-key-slot-collision-integrated-pack/npm-cache \
node scripts/test-packed-public-query.mjs --join-star-only
```

The existing shared-lock wrapper limits this campaign to 1,200 seconds.
Receipt:
`/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-86pNnr`.
It records passed/complete status, all ten child commands at exit 0 with complete
streams and no signal/error, and no evidence errors. Both Embedded Local and HTTPS
complete all 15 positives and 16 exact-code input refusals, including the four
projection-only INNER/LEFT/RIGHT/FULL duplicate USING cases, eight ambiguous SET
refusals and the repeated-ON positive control. There are no excluded known failures.

The unchanged public assertions compare independent Named Result rows and describe
contracts (type, nullability and declaration order), multiplicity/NULLs, private
field absence, Source acquisition once, same-Run resend/attach/reread and no extra
admission/acquisition. Every preparation refusal is ClientProgramInvalidInput and
leaves Run admission and Source I/O counters unchanged; lookup agrees with refusal.
README Local/HTTPS and the deliberate missing-generated-asset check also pass.
This is public execution evidence, unlike the earlier incomplete Local attempts.

| Package | Original tarball SHA-256 |
|---|---|
| client-wire | `4105321db630741cba8d4573d9800f554af51b1b7eff46cdf17f651128ebcc9f` |
| sdk | `e4d0fff729f53b3cd96f97997c2bd052069d2de4152e083d84d4201852b46be6` |
| run-host-core | `41a71cbf8c1deb5b4b7a136d9596af60f335a8cac4fbde7f0643494af5597dfc` |
| local-node | `566e956cf39b59e909bb26cf5e06880d022f84206c431f0eefcb92ad85b3b6c2` |
| node | `aa96b83e047cf3fc42b560b578fc2a32b9a38fa3f32c62dcf9f5eaff26891f4b` |

The original five tarballs and receipts remain available; the helper removed its
external installation and temporary Store after retaining evidence
(`artifactsRemoved: true`). The following submission commit changes only this
English evidence record. Its CI is separate from the tested clean SHA. Full Core,
full packed/performance, Wasm/Native runtime execution and live Google differential
validation are not established here. Draft CI is preparation only. No manual CI
retry, Ready transition, merge, runtime-owner duplication or compatibility fallback
was performed. Parent #1125 remains an unmerged dependency; final target is main.
The wider Frontend goal remains active beyond this completed correction unit.
