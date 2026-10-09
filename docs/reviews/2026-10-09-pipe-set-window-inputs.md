# Pipe SET: inline window assignment inputs

Date: 2026-10-09. Status: implemented Frontend connection; focused checks and
fresh packed Local/HTTPS acceptance passed at the product SHA below.
Submitted-HEAD CI remains unverified. The submission adds only this evidence record.

## Counterexample and selected meaning

Adopted main: `ffe46cdae6d064a60da517dec2937eeaee4a1c30` (fetch reconfirmed).
Parent #1121 remains unmerged at `1da668809bb5ba9b65b442e259de2f682d5cfabe`,
following #1116/#1115/#1111. Final target is main; this unit does not change a
shared execution owner, D's CTE/Effect processing or another worktree.

The [GoogleSQL Pipe SET](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/pipe-syntax#set)
replaces existing current columns while range variables retain original values.
The same reference's order-preservation section explicitly distinguishes SET
using window functions. The selected inline window profile belongs in ordinary
SET expressions, without a new inference, analytic or assignment executor.

```aql
FROM t
|> SET x = ROW_NUMBER() OVER (ORDER BY y)
|> ORDER BY x
```

For input `(x,y) = (1,20),(2,10)`, expected public rows are
`{x:1,y:10},{x:2,y:20}`. Both columns remain in order and non-NULL. The independent
ordinary Analytic/Derive/Sort/Select control passes the checker; baseline
`run-uRpD4n` / `focused-test-t1oIVY` records 1 passed, 2 source parsing failures.

The complete expected Program is independently authored. Its private assignment
slot follows the existing allocator rule: start at the number of retained
physical fields, not at zero. Two input fields plus one private analytic field
mean `aql_pipe_set_3`. Initial connection `run-0vxKzE` (19/20) exposed that
internal-name mistake in the new test; correcting it preserved every operation,
reference, row, type, order and limit. No expected public result was changed.

## Connection and retained boundaries

The parser extracts direct or embedded window calls through the existing
bounded window-expression callback, collecting sibling calls before SET. The
existing window resolver supplies ordinary AnalyticExpressions; ordinary GROUP
calls cannot be introduced in assignments. Prior SELECT/EXTEND WINDOW names do
not leak. This unit connects inline specifications, not a SET WINDOW declaration.

`compile_steps` passes the evaluated private analytic bindings alongside the
pre-SET current-row snapshot and immutable ranges to the existing expression
lowerer. All sibling assignments read that snapshot, then normal replacement
slots change only current columns. Target existence/duplication checks remain.
Private bindings are cleared afterward; normal final projection exports only
current columns. The common checker determines new types and nullability.
Authored placeholder-like names cannot be captured.

Parameters, predicates, analytic signatures/frames, expression demand, capacity,
Result order and capture ownership are unchanged. No Source predicate or limit
is rewritten. Explicit final ORDER BY is used in public controls. JOIN after a
nontrivial Pipe prefix remains a separate existing coverage limit.

## Independent fixtures

The normal/focused window-scalar corpus gains nine positives and eight exact-code
preparation refusals. Independent JSON and text controls use the same rows/types:

- Direct replacement and a scalar operand preserve visible column order.
- Typed parameter values use the existing declaration/value path.
- Empty input retains the replacement's complete describe schema.
- LAG preserves nullable replacement values without restoring the old type.
- Sibling replacement of id reads old nullable amount, not its new row number.
- An original range still reads the displaced amount after window assignment.
- An authored placeholder-like name is a real input and retains NULL propagation.
- Missing/duplicate targets, missing/projected-away input, replaced range,
  private-slot reference and leaked WINDOW name are invalid input; missing
  aggregate frame remains the existing implementation-limit refusal.

The shared acceptance app compares independent Named Result rows, stream
completion, describe type/nullability/column order, no internal fields,
acquisition once, same-request Run identity and unchanged counters after
attach/resend/reread. Refusals require zero Run admission and Source I/O.
No generated Program is repaired by the test before submission.

## Identity and generation

Grammar changes
`sha256:e0ad6a5fa648e290e490096887361d02e7a9b223c1d6a267646c6974a874d832`
→ `sha256:c4364e9947c8d6c7538d9245fca2da3fc0cd44bd70caceff58862ba9629c90d6`.
Independent fixed Values Run changes
`sha256:f0fc9b3b44633c03def0118d8d40e4d34068720763fa744e1d161f57541839a5`
→ `sha256:71a90eff92faeb07d1efe6c8bbe56bdcaac3d87a04b6a6c2f3e314a52503e069`.
Program, expression, Unit, proof and ResultPlan contracts are unchanged. The
complete previous grammar and independently reconstructed Run preimages are
retained in `scripts/fixtures/pre-pipe-set-window-grammar.json`. Existing canonical
Values oracles determine consumer expectations; no runtime-issued CID is copied.
Historical saved Runs are not rebound to new grammar or current dependencies.

The four existing compilation-manifest, document-metadata, spec-family and
canonical-identity generators update their owned outputs, separate from
independent fixture authorship.

## Focused evidence and remaining coverage

- Baseline common control: 1/3; both source examples rejected (`run-uRpD4n`).
- Expanded SET/scope/WHERE/EXTEND callers: 24/24 (`run-nMX69w`,
  `focused-test-9zxdld`).
- Final pinned JS plus consuming Values identity: 25/25 (`run-fTN5os`,
  `focused-test-eVxIRL`). Exact refusal reasons are asserted.
- Fixture, independent grammar/Run vectors and manifest tests: 23/23
  (`run-5N2K7c`, `focused-test-nuHCnP`).

- Public fixture/document/import checks: 22/22 (`run-MbZ2dU`,
  `focused-test-gjKYIE`). All four read-only generator checks pass;
  382 canonical identities match and metadata needs no writes.

Fresh normal five-package production and focused packed Local/HTTPS acceptance
passed as recorded below. Submitted-HEAD required CI, three-target runtime coverage,
full Core/full packed/performance and live Google differential validation are
unverified. Draft preparation is not merge CI. The broader Frontend goal remains
active; this connection is not complete standard analytic coverage.


## First packed attempt and target-diagnostic correction

Normal five-package production and digest verification at
`99f112fc9a91758eea32d31c644b046d77b0b49a` succeeded. The packed Local cohort
completed all 58 positive fixtures, including all nine new SET fixtures, and
one expected execution failure. It stopped on the first SET target refusal:
expected ClientProgramInvalidInput, actual ClientProgramImplementationLimit.
The existing SET missing/duplicate-target branch returned UnsupportedProjection,
which the public diagnostic owner correctly classifies as unsupported coverage.
A missing current column or repeated assignment is an invalid authored target,
not unimplemented SET semantics.

Failed receipt `public-query-evidence-149k9k` and outer `run-pzjljR` are retained;
command 010 exited 1 with complete stdout/stderr. Later refusals and HTTPS are
not established by that attempt. Independent exact-reason regression
`run-aXvpqy` / `focused-test-N2ld2w` failed 1/7 before the diagnostic correction.
It covers both plain scalar and window assignments. The lowerer now returns
existing UnknownColumn for a missing target and DuplicateOutput for a repeated
target; the shared public diagnostic owner remains unchanged. No expected row,
type, order, target validity rule or public refusal code was weakened.


The target-diagnostic correction and its direct scalar/SET/JOIN-range callers
passed 16/16 (`run-oP6Ofj`, `focused-test-ZWhwt0`). This is focused local evidence,
not completion of the previously interrupted Local/HTTPS packed campaign.

## Successful fresh packed acceptance

Tested clean product/fixture SHA:
`6b0dad1b725a9316c63180699daea728b7c3bf3a`. The later submission commit changes
only this English evidence record; its CI is not established by this local run.
The earlier `99f112fc...` failure remains separate evidence, not relabeled success.

Outer bounded heavy execution `run-IcHhXl` completed successfully. With the pinned
Node/MoonBit environment and the shared heavy slot, it ran these steps in order:

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-pipe-set-window-6b0dad1b7-pack
# Independently compare manifest.revision with the clean checkout HEAD and
# SHA-256 of each original tarball with the manifest's five digest entries.
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-pipe-set-window-6b0dad1b7-pack \
ACTQL_TEST_NPM_CACHE=/private/tmp/actql-b-group-key-slot-collision-integrated-pack/npm-cache \
node scripts/test-packed-public-query.mjs --window-scalar-only
```

Exact bounded invocation: `/private/tmp/actql-b-pipe-set-window-6b0dad1b7-packed.mjs`.
Normal prepack was used; no compiled overlay, producer bypass, repaired Program or
manifest relabeling was involved. The five original tarball digests are:

| Package | SHA-256 |
|---|---|
| client-wire | `4105321db630741cba8d4573d9800f554af51b1b7eff46cdf17f651128ebcc9f` |
| sdk | `e4d0fff729f53b3cd96f97997c2bd052069d2de4152e083d84d4201852b46be6` |
| run-host-core | `41a71cbf8c1deb5b4b7a136d9596af60f335a8cac4fbde7f0643494af5597dfc` |
| local-node | `48b8b35b24045f0976a46bccff87d8376b0216dbc85b70d4293a682a3819446b` |
| node | `aa96b83e047cf3fc42b560b578fc2a32b9a38fa3f32c62dcf9f5eaff26891f4b` |

Receipt:
`/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-llsVbm`.
Its summary is passed/complete at the exact product SHA: all ten child commands
exit 0 with complete streams, null signals/errors and no evidence errors.
Successful external installations were removed after evidence preservation
(`artifactsRemoved: true`); logs and the original pack remain available.

Each Embedded Local/HTTPS entrance completed 58 positives, 36 preparation
refusals and one expected execution failure, including all nine new SET positives
and eight exact-code refusals. Of the complete refusal cohort, 31 cases emit
per-case exact-code log lines; five older cases run their existing input-code-set,
zero-admission/I/O and submission-lookup assertions without per-case log lines.
The successful complete acceptance process covers those five as well. README
Local/HTTPS quickstarts and deliberate missing-generated-asset refusal also pass.

Named Result rows, stream completion, type/nullability/column order, private-field
absence, one acquisition and same-Run resend/attach/reread counters agree with
independent expectations. This is the focused window-scalar cohort, not the full
packed campaign, all-target verification or a live Google differential test.
Parent #1121 remains unmerged, so the Draft base retains that dependency; final
integration target is main. No manual CI rerun, Ready transition or merge was made.
