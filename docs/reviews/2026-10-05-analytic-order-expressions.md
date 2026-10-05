# Analytic ORDER BY expression connection

Status: Original implementation and acceptance history, followed by main
integration below. The failed pre-integration campaign remains historical
failure evidence; it must not be relabeled as current acceptance. This is not
completion of the analytic profile.

## Main integration and fixture profiles

Main `40340e5be89d53f3e862b3580d1fa3fcc9129a12` added the common source-free
Relation DAG selection from #396 and canonical property expression emission.
The existing branch incorporates that source through a normal merge without
changing the 536,870,912-byte execution budget or the independent expectations.

The packed corpus assigns every analytic-order fixture its original three
1,048,576-byte wire ceilings and 10,000 frame memberships. Analytic-property
fixtures retain main's 10,000-byte ceilings and 10,000 frame memberships.
Separate immutable Local and authenticated HTTPS Host installations run each
profile, including in a combined corpus. The default corpus retains main's
profile. No wider envelope overwrites another fixture's declared limits.

`--analytic-profiles-only` selects both complete analytic corpora, including
the nullable-object positive below, its unchanged original generated JSON
reproduction, refusals and the expected division failure. Expectations remain
independently authored; the reproduction is not treated as an expected Program.
The follow-up merge includes main
`036dbd5d24a3448568256c3e33867c215e8eac9d`, preserving the JOIN fixture route
and its property-aware compiler behavior.
Existing analytic-order, analytic-property, aggregate-property and Subgraph
routes remain registered. Current exact-HEAD verification belongs to the PR's
validation record; the original observations below retain their original SHAs.

## Counterexample and adopted boundary

The parser accepts `ROW_NUMBER() OVER (ORDER BY -amount, id)`, and an independently
authored Program using `derive` followed by `analytic` passes the ordinary
checker. The former lowerer nevertheless rejected the source with
`UnsupportedOrdering`, because it required every OVER order term to be a root
column reference. The pre-fix focused run passed the independent Program case
and failed the source case: 1/2.

The input scope comes from [query-text.md](../spec/query-text.md#scope-and-lowering):
OVER sees the immutable SELECT input, including retained Pipe range bindings;
it cannot see aliases introduced by the same SELECT list. This differs from the
query's final ORDER BY. Numeric literals inside OVER are values, not ordinals.

`query_analytic_order.mbt` resolves ordinary columns to existing slots and lowers
other order expressions through the existing structured expression builder.
One private derive step precedes the analytic groups. Syntactically identical
expressions in the same immutable input scope reuse that evaluated slot, even
across different windows. Helpers are absent from the visible scope and are
removed by the ordinary SELECT projection before Result publication.

Common expression typing, nullable property access, ordering, analytic envelopes,
failure and resource owners remain authoritative. No execution engine, wire,
schema, grammar, owned contract identifier or serialization law is added.
Newly admitted source produces ordinary Program identity under the existing CID
rules. Frames, signatures and PARTITION BY expression coverage are unchanged.

## Fixed sources and limited checks

- Base including main recovery #421: `3d21f2c8ccbe055aa792bdffdaab2b85770cf0c4`.
- Main normally merged before public acceptance:
  `8de7148d25bbcc84eaaa6f3037c754c9f77187fb`; merge commit
  `dc603874b5694cadf757fa3b51da4dcbb5f83301`.
- Clean implementation/fixture source used for the final pack and retained
  consumers: `830db5903edc10e7004d6fc35190e207d2bc3790`.
- Focused JS checks after the main merge: new file 9/9; existing `*OVER*` 3/3
  and `*analytic*` 3/3 (one existing test overlaps the two filters).
- Pinned MoonBit `0.10.12+1634b282e` formatting, changed Node file syntax and
  `git diff --check` passed. Full Core, Wasm, Native, performance and the full
  packed corpus were not run locally. No manual CI rerun was requested.

Commands ran through `scripts/local-checks.mjs` or `runLocalCheck` with serial
heavy-check exclusion and explicit duration limits:

```sh
node scripts/local-checks.mjs test moon -- --target js src/query_program/analytic_order_expression_test.mbt
node scripts/local-checks.mjs test moon -- --target js src/query_program/compile_test.mbt -f '*OVER*'
node scripts/local-checks.mjs test moon -- --target js src/query_program/compile_test.mbt -f '*analytic*'
node scripts/test-packed-public-query.mjs --analytic-order-only --keep-artifacts
```

The installed acceptance profile explicitly declares analytic input, output and
partition wire ceilings of 1,048,576 bytes each and 10,000 frame memberships.
These are installed envelope limits, not observed-size evidence or new Host
defaults. The existing 512 MiB execution budget is unchanged. An earlier pack at
`4b0364e6a595d9f05d083d68ac97563f541deb9a` omitted those four ceilings and stopped
at unresolved analytic capacity during preparation. It is not execution evidence.

## External package acceptance

The clean normal pack at `830db5903...` passed prepack/install, package-boundary
checks, README Local/HTTPS and public check. Its corpus passed nine Local
positives, then stopped at `analytic-order-nullable-property-input` before
refusals or HTTPS. The campaign remains failed, not a complete success.

A separate retained-artifact consumer checked producer source cleanliness, all
five successful pack commands and tarball SHA-256 values. It used a fresh private
installation and the same ordinary acceptance app, excluding only that unresolved
positive in an explicitly recorded diagnostic selection. Package bytes were
unmodified. Results were **9 positives, 6 preparation refusals and 1 expected
execution failure on each of Embedded Local and authenticated HTTPS**.

This confirms the independent JSON control, SQL/Pipe expression ordering,
input-versus-SELECT-alias collisions, numeric literals, old Pipe snapshots,
shared expression evaluation, empty typed output and typed parameters. Exact
rows and `Result.describe().columns` exclude private sort helpers. Reading,
attaching and resending return the same Run without another Source acquisition.
Every preparation refusal checks typed input errors, zero new Run acceptance,
zero provider I/O and no request registration. Division failure publishes no
Result and does not recompute on attach/resubmit. Expectations are authored
independently; no test changes the emitted Program before execution.

Package digests (SHA-256):

| Package | Digest |
|---|---|
| client-wire | `6fc7b08e76db77e8f42a9bb3897f94726a9ef8b259dfb5f1646d83c65263edca` |
| sdk | `5d7f3b88eda9d8c5f04d4684b049765a1536992cf2ee22243290b6d8481ef642` |
| run-host-core | `cdacf102e0615594dd7aafeb45612786f59235b900884ae40860eb71f48b9c99` |
| local-node | `daa4eda7341818b36533b5b292301314d3855a4e994f801ed850dbd7f1caa914` |
| node | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

Retained evidence invocation IDs: producer `public-query-evidence-rDaRIb`;
partial Local/HTTPS consumer `public-query-evidence-rSnrAn`; root diagnostic
`public-query-evidence-hS2yGb`. Guard receipts: focused `run-UEaV7r`,
`run-7qHgZR`, `run-JJ1ZgG`; producer `run-AQyZgp`; retained consumer `run-lrSgUW`;
root diagnostic `run-hmKAxv`. Local evidence roots are provided in the working
handoff; no developer installation path is a public dependency.

## Nullable-object case: common capacity boundary

The unchanged positive remains registered in the normal packed corpus. Its DATA
query uses three parameterized source-free UNION ALL terms, nullable input
`payload`, a colliding SELECT alias `other AS payload`, and input-scoped
`ROW_NUMBER() OVER (ORDER BY payload.score + 1 NULLS LAST, id)`.

- Formal installed source preparation succeeds; ordinary checker and compilation
  produce one task. The helper references the original input `payload`, not
  the subsequent SELECT alias.
- Both authored source and its unchanged emitted JSON fail on task 0 before
  provider execution. The generated Program is retained as a **reproduction**,
  not as an independent expected Program:
  [Program](fixtures/analytic-order-property-repro.program.json),
  [parameters](fixtures/analytic-order-property-repro.input.json).
- Independent expected rows/types are in the positive fixture and
  [expected result](fixtures/analytic-order-property-repro.expected.json).
- A logging-only overlay in a private installed package exposed
  `LocalManagedStart(Execution(Physical(ExecutionLimit)))` at
  `connectors/local/driver/managed_dispatch.mbt::start_local_managed_dispatch`,
  calling `physical_strategy/task_execution.mbt::start_captured_managed_execution`.
  Capacity reservation fails before the prepared callback; the public terminal
  symptom is `ACTQL_E_UNPUBLISHED_RUN`. The exception tags were matched to the
  enums of this same source revision, not guessed from the terminal error.
- Task capacity: transfer **0**, retained **14,240,000**, scratch **958,282,752**,
  execution **958,282,752** bytes, versus a **536,870,912** byte execution budget.
  Both source and emitted JSON report the same values. This does not establish
  that the estimate is excessive or that the common owner has a defect.

The diagnostic added only failure/capacity logging to private copies of
`client-dispatch-owner.mjs` and `strategy-bundle.mjs`, then restored and verified
their original bytes. It is not pristine packed success evidence. The pristine
producer already established the public failure; this overlay identifies its
boundary without replacing a provider or changing limits.

Common-capacity follow-up belongs to A: distinguish necessary input retention,
output, expression scratch and sequential lifetimes from double counting using
the preserved Program. B has not lowered coefficients, raised the 512 MiB budget,
removed order terms, changed expected rows, or added a fallback. Reaccept this
same positive through Local/HTTPS after that boundary is resolved. Until then,
Frontend lowering/checking is complete for this case, public execution is not,
and the PR stays Draft. This capacity investigation does not block independent
Frontend work.
