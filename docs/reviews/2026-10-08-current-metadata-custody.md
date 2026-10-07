# Native preparation storage and chain custody correspondence

## Identity and scope

Adopted main: `4256490e50dec0eb261c35c156210a62539aabc6`.
Normal merge: `5abbadb2b30236c3e0e8de639037992f809de643`.
Implementation and actual clean execution: `81e2da476713caee77f55d74ec15937d667a7f9b`.
Dependency: #917 at `8b5be5f0a51516478ba4e3e5cc9b7dadffd03916`.
#916 is integrated. Final merge target is main; keep this unit Draft.

The previous final consumer separately accepted retained chain metadata and
preparation storage. An identical byte envelope cannot establish that those
observations describe the same pending cursor or receiving edge. The existing
storage inspector accepted a transfer with changed bound identity or preparation
sequence, provided extents and columns ownership remained the same.

This unit joins those existing synchronous borrowed observations in
`current-audit.mjs`; no new observer, harness, product owner or scientific workload
is introduced. Independent controls preserve the same summaries under such
substitutions and show the new joined consumer refusing them. This is a metadata
acceptance gap, not evidence of a public Run or product malfunction.

## Preserved observations and joined obligations

The first storage point must match the exact pending preparation/read recorded by
the actual chain. Every preparation retains the startup sequence and the same
explicitly retained completed-output container; the receiving owner/node roles
remain those of the selected pending cursor. The pending cursor additionally
retains the original chain inputs and producer-bound root through cancellation.
The successful second preparation is for the same receiving edge; its input
Array and bound identity may be freshly constructed. It must retain the same
receiving schema and transfer its own exact bound/schema alongside the existing
same-owner columns check. A new binding for a new preparation is not rejected
merely because it differs from the first binding.

ProducerRead's reference offsets and extent are checked in full, along with the
existing metadata/preparation layouts. Duplicated or extra pointer fields, changed
extent, missing/unordered points and absent mandatory roots reject. The actual
source transfer must still contain `bound: cursor.bound`, `schema: cursor.schema`
and `columns: cursor.columns`. These are explicit reviewed source/ABI premises,
not a general free-variable, compiler or alias proof.

Cancellation clears the pending read; completed transfer leaves no preparation
read or matched-input root. Separately, every actual chain phase's current child
must match its retained responsibility, and successful cleanup must leave that
state field null. The children/completed storage and cleanup false/error/retry
checks remain. Clearing visible length does not imply reclaiming Array backing
or published columns; the existing capacity inspector continues charging them.

The correspondence applies to the fixed pending/transfer fixture. It does not
inspect the complete BoundProducerInput/output/receiver referent graph or prove
that an arbitrary receiving edge/schema has these identities. The stable
owner/node roles are matched to the observed base preparation; the product's
existing sequence/port binding is an explicit premise, not inferred from equal
schemas or data values. Borrowed identities are compared while the fixture holds
those roots, with no union across reclaimed-address reuse.

## Local controlled checks

The final implementation working-source selection passed 23/23 with no skips:

```sh
node scripts/local-checks.mjs test node --timeout-seconds 180 -- \
  proofs/relation-pipeline/capacity/parent-control/preparation-custody.test.mjs \
  proofs/relation-pipeline/capacity/parent-control/preparation-arrays.test.mjs \
  proofs/relation-pipeline/capacity/parent-control/chain-source.test.mjs \
  proofs/relation-pipeline/capacity/backing/parent-bounds.test.mjs \
  proofs/relation-pipeline/capacity/backing/parent-overlay.test.mjs
```

Nine independent joined-custody controls, four existing preparation-storage
controls, three source/overlay controls, four parent-layout/custody controls and
three consumer/compiled-input controls executed. Guard `run-M8VL9o` completed
under a 180-second budget. These fixed metadata/source substitutions are not a
physical product mutation campaign, universal implementation proof or Actions
original.

The initial wrapper attempt was rejected before tests because sandbox permissions
prevented inspecting its owned process group. An approved execution then passed
21/22: one invalid pending-read case was correctly rejected at the earlier
whole-record match, whereas the test expected a later cursor error label.
Correcting that error-label expectation, adding the same-envelope differential
control and then complete transferred-layout/source checks produced 23/23. The
failed and intermediate attempts are retained as their own originals.

## Actual clean-source Native acceptance

The unchanged existing local `current-diagnostic.mjs` entry executed once under
shared-heavy guard `run-Yl77qr`, 900-second budget and five-second TERM grace:

```sh
node proofs/relation-pipeline/capacity/parent-control/current-diagnostic.mjs
```

The step passed in 80.866 seconds, including preparation, model and final
inspection. This is diagnostic elapsed time, not a performance comparison or
execution-only duration. The actual selected Native fixture passed 1/1, seven
custody phases and four preparation-storage points were inspected, and the new
joined consumer accepted the actual pending/transfer binding and schema roles.
Seven conditional propositions were checked at their expected Lean types with
the existing axiom audit. All 30 receipt substitutions were rejected without
extra scientific execution. Source restoration was byte-for-byte; final
admission independently regenerated bound object/executable observations and
preserved the original receipt identities. Output streams completed and the
owned worktree/heavy locks were released.

Restored source snapshot: `7d023b8b9e3c29d599e44858acb78206d6a392b4975aa2a7ef4b88254de54228`.
Executed diagnostic overlay snapshot: `3c919d9123e1ebdb29ab89e96c9d36653b75b25e2436e90f709b503184ce823b`.
Build identity: `f73f6c1c1cb9531a6db913e6b57399b127caea92f34344d9275c45832a0ed7f5`.
Actual object: `6e24619d429f41b3a8b419b35796b7592d15509f3cd163dfd22cc0bf2e57b6dd`.
Executed whitebox binary: `24928570755b5bd7fe9ac8f93841d09785a4cf8cde52e71a8bbab4f03ccb6cf4`.
Diagnostic original: `3474a864bb8b72f769d29828c9b1eaee35739fed11dd4ef6d27980b468a173e5.json`.
Accepted original: `deacbb8da012a2ed7aa486ddd9b03e5b1b9739d98f5b7d3ea29e6f9257f40501.json`.

The actual observer is a diagnostic overlay bound to its build marker; it is
not called a pristine product binary. The original success is for the clean
implementation SHA above. Publication adds only this report/archive; its source
snapshot is checked unchanged. No result is relabeled as execution of the later
report commit. Historical source `976e45bba...` was inspected while designing the
connection; it is not the evidence for this fresh acceptance.

## Original archive and residual obligations

[2026-10-08-current-metadata-custody-81e2da476.json.gz](evidence/2026-10-08-current-metadata-custody-81e2da476.json.gz) preserves 54
original UTF-8 members, 4,778,784 decoded bytes, raw SHA-256
`fd8c3ba858d652a1d11910b21c06d991abd01fe0e130a0aa6d9d2c05c62889df`;
1,470,566 compressed bytes, gzip SHA-256
`9cf54ff6380b316a308566fd8b8da388f897d9d0e0b7b3f9a405be407a89bac5`. Decompression and every member's byte length/digest were checked.
The real object and six linked binary/debug artifacts remain separately in the
owned worktree's content-addressed `.artifacts/relation-pipeline/current-chain-native/`
archives. Their byte sizes/digests/paths are in `retainedNativeFiles`; the published
text archive is not a standalone binary distribution.

Structural count ceilings, conditional old/new backing overlap, observed
requested bytes and a whole physical lifetime upper are different claims. This
unit leaves every existing capacity constant and whole-parent/allocator/GC/Ledger
residual unchanged. The same two Array owners remain charged at pending and
transfer points. No unconditional physical upper, arbitrary heap traversal,
Linux/Wasm/full Core/public/packed acceptance or hosted CI is claimed. No actual
post-parent-merge history campaign is added solely for reporting; no protected
source or history declaration is edited in this unit.

Local originals do not grant Actions origin/reuse authority. Successful full-main
origin authentication, policy-compatible subsequent-main qualification, ordinary-PR
`mutations-js` reuse, related-input fresh execution and acquisition/authentication/
transfer-inclusive net savings remain deferred without repeated polling or
Actions dispatch. The project-wide goal stays active; this unit makes the existing
shared capacity/ownership evidence compose at the real Native consumer.
