# Three frontend checkpoint regressions

Base: `49466a9d1365900be76a0f41a7986231dc237ea7`.
Scope: the three frontend/standard Host cases reported from G's fixed `7d49`
checkpoint. G's original full run and four failure receipts remain immutable;
this change does not establish a subsequent full-Core pass.

## JOIN bounds

The first two failures are not caused by canonical JSON spelling. Their source
queries do not author `MAX_OUTPUT_ROWS`; they set the frontend admission ceiling
to seven. `values_join_output_bound` in `compile.mbt` computes four pairs for the
independent two-row Values inputs, before those producers become step references.
A later JOIN or the ordinary shared WITH set route retains the context ceiling
when that Values specialization is unavailable. The independently expected typed
guards are `[4,4]` for the two standalone set operands and `[7,7]`, `[4,7]`, `[7]`
for the three positional cases. This changes no lowering or bound policy.

Read every JOIN's `relation_join_shape.output_guard` from the common checked
pipeline instead of counting a serialized substring. Require a typed Literal
guard, its exact value, and the exact number of JOINs. Additional versions author
`MAX_OUTPUT_ROWS 7` on every JOIN and require every guard to remain seven.
The pre-existing independently authored JSON Program is unchanged and also has
its literal seven checked. Final output scope, ORDER, LIMIT/OFFSET and the original
invalid-reference checks remain in place.

## Standard Host funding

The original Local-only case returns `Estimate(NoStrategy)` before dispatch.
Installed exclusions are empty. The common strategy assessment is specifically
`RetentionLimit`: 32,198,400 required bytes exceed the unchanged 32,000,000-byte
ledger allowance. It is not an unsupported-operation or bundle/content refusal.

Independent allocation arithmetic from the existing literal configuration is:

- Generated retained allocation per task: `256 * (10000 + 10000 + 10000) +
  8 * 10000 = 7,760,000` bytes (`execution_relation/execution_capacity.mbt`).
- Imported retained allocation per task: `64 * (100 + 10000 + 10000 + 100 +
  10000 + 10000) + 8 * (10000 + 10000 + 10000 + 10000 + 10000) = 2,972,800`
  bytes (`connectors/local/materializing.mbt`).
- The published compute_b and compute_c outputs coexist with compute_a until
  compute_c completes. The peak is `3 * (7,760,000 + 2,972,800) = 32,198,400`.

Keep the original Program, generated sequences, configuration, all capacities
and budgets. Reclassify the Local-only case as this explicit resource refusal;
check that no task completed or output appeared, no attempt/transfer was consumed,
and the same owner releases all holdings/reservations. The reference-only and
both-installed execution/cancellation controls retain the original output
Number(3), row count and zero outstanding resources. **Local-only success for
this original three-task fixture is not established or claimed.** No capacity
law, matcher, strategy policy, source or execution implementation changes.

## Evidence and limits

Raw receipts are retained outside Git in the owner-local
`2026-10-13-b-core-checkpoint-three-evidence` cohort.

- `run-QvqkBT`: unmodified base, 11 JS cases, 8 pass / 3 fail.
- `run-ShG6IL`: diagnostic compile failure; tests not executed.
- `run-HAhul6`, `run-458Je3`, `run-ePEwfN`: diagnostic failures retained, including
  the first typed Host refusal and the actual capacity assessment.
- `run-V1g2VQ`: 12 cases, 9 pass / 3 fail. New fixture bugs included a first-only
  String.replace and an arithmetic error; neither was a product failure.
- `run-ToO8Z8`: working-source focused JS 12/12. This is not clean-commit evidence.

The original independent SQL/JSON controls and budget are preserved. Expected
arithmetic is authored from the allocation contracts, not from product values.
Only the three selected JS files are executed with the existing 60-second,
TERM-grace-five, nonHeavy guard. No full Core, Native, Wasm, producer, packed,
Provider or Hosted CI is started. Newly completed external installed E2E: **0**.
Calendar/F05 work remains a separate private branch and is not included here.

Commands (pinned Node/MoonBit from AGENTS):

```sh
node reviews/2026-10-13-frontend-core-checkpoint-three/prepared-checks.mjs --format
node reviews/2026-10-13-frontend-core-checkpoint-three/prepared-checks.mjs
```
