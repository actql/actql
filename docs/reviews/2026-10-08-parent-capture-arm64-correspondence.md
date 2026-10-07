# Darwin ARM64 ordered parent capture correspondence

## Boundary and dependency

Adopted main: `db4f80870345c48744f44023df5fe8c9617b30ed`.
Dependency: #916 at `6b46e468e2af555c8bc5b4c24e3da012d2973ca1`.
Normal merge of that published source and adopted main:
`f4b31dfa2cbafed3fd2fbcf1e9f58b56eefa388c`.
Implementation: `976e45bba920e83cf09eef58b2d9f147684c80e2`.
Final merge target is main. #909/#912 are already in adopted main; no duplicate
implementation or declarations were added. #916 was a separate dependency at execution and is now integrated as recorded below.

The existing primitive Ref correspondence did not establish ordered callback
fields on Darwin ARM64. The existing live observer/source check compared sorted
capture identities, which cannot distinguish equal-width role swaps. This unit
connects the actual generated constructor stores to every observed offset/role,
using the existing final consumer and original binary/object archives.

The environment and five callback requests remain 80, 104, 40, 24, 48 and 24
bytes. Every pointer/scalar field, its width and source role, unique indexed header
and callback code pointer must be present. The decoder binds private frame and
callee-saved sources through the actual observer argument preparation, including
Darwin's compact four-byte scalar stack slots. Same-identity-set swaps of
terminal/cancelled or family/measurement, and same-width count/limit substitutions
cannot become valid correspondence.

Mach-O PAGE21/PAGEOFF12 relocation pairs must name the same local callback. Linked
page/offset addresses must resolve uniquely. The actual object and executable
must agree on all six allocations and ordered field/code identities. Both are
independently read and their observations regenerated at final admission using
bound inspection tools. Callee-saved registers follow the pinned ABI and calls
invalidate volatile aliases. This is finite code correspondence, not a general
machine-code or compiler proof.

The five callback arguments must reach the existing retaining Owner in role order.
Its returned parent must reach the observer. Caller callback retirement follows
handoff in the same order; substitution, premature/missing retirement or an extra
instruction hiding a parent change rejects. Partial/duplicate/missing stores,
unbound slots, allocation escape, unknown calls/instructions, entering branches
and incomplete observer arguments reject. Source owner/handoff semantics remain
explicit trust assumptions; no second owner is added.

Product code, layouts/offsets, capacity constants, Lean models, runtime pin,
workflow, action selection and evidence reuse policy are unchanged. The restricted
ARM64 instruction/call parser is shared with the existing Ref decoder; x64 retains
its independent existing capture decoder. No old-layout/receipt compatibility
path is introduced.

## Independent controlled checks

Working-diff consumer selection passed 43/43 with no skips:

```sh
node scripts/local-checks.mjs test node --timeout-seconds 180 -- \
  proofs/relation-pipeline/capacity/parent-control/parent-capture-arm64.test.mjs \
  proofs/relation-pipeline/capacity/parent-control/parent-capture-sites.test.mjs \
  proofs/relation-pipeline/capacity/parent-control/parent-reference-arm64.test.mjs \
  proofs/relation-pipeline/capacity/parent-control/parent-reference-sites.test.mjs \
  proofs/relation-pipeline/capacity/backing/parent-overlay.test.mjs
```

Ten ARM64 capture controls, ten existing x64 capture controls, ten existing ARM64
Ref controls, ten existing x64 Ref controls and three actual overlay-boundary
controls execute. Independent authored fixture fields are not imported from the
verifier. Their synthetic disassembly is controlled decoder evidence, not a
physical mutation campaign or an authenticated receipt.

The first selection passed 42/43. An intended positive inserted an incref between
loading a volatile field alias and storing it; the ABI model correctly discarded
that alias. Moving only that fixture to the inter-allocation boundary produced
43/43 while the explicit stale-volatile negative remains. Both attempts are
preserved. This is not a reproduced product fault.

## Historical actual-code reinspection

The previous unit's original Native execution
`873bd8e79df2afe2855da451d4b213ed53f19497` was read without recompilation.
Object `6eebd2d72c3e3cab9295ca5323a62ef79744be60725ab0168567dd01817a54d1`
and executed binary
`78fa45573c27f5aec36503b6bb535499b240b10b3b275a7d72be3fd609364fa6`
retain their original identities. The original report/log digests were checked,
actual executed callback symbols read and all six ordered captures admitted.
Guard `run-IqSi75` completed with exit 0 under a 90-second budget.
This is an old-original reinspection, not an execution of the new implementation
SHA. It cannot substitute for the new actual clean-source diagnostic below.

## Actual clean-source consumer

The clean implementation source `976e45bba920e83cf09eef58b2d9f147684c80e2`
executed the existing `current-diagnostic.mjs` local entry under shared-heavy guard
`run-AY1V0R`, with a 900-second combined Native/history budget and five-second TERM
grace. The Native step completed with exit 0 in **103.987 seconds**. This is local
diagnostic elapsed time including preparation, model and final inspection, not a
performance comparison or scientific-execution-only duration.

The actual selected Native fixture passed 1/1. Seven actual custody phases retain
callbacks/state/completed outputs across child progression, cancellation and
cleanup false/error/retry. The seven conditional propositions were checked at the
expected Lean types, with the existing axiom audit. The final consumer regenerated
observations from the retained object and executable and admitted all six ordered
captures; all 30 existing receipt substitutions were rejected without extra
scientific execution. Exact source restoration passed.

Restored source snapshot:
`298fc3c487a790c53ebf435dab2f4240690f007e0589158a5c14a65aa2374716`.
Executed diagnostic overlay snapshot:
`bdf704dcb8a68d6fac2e3e6ad8e58d5500044dacfaefb8aea87c9b3071ab8e0b`.
Build identity:
`8dd19d41f393cd47399433406d7bee14cff7fbd8965e80d3dfa2c763c8fb99ec`.
Actual object:
`3009cee1ca93db687e4f5858da14c6cec003badfd37a3e29d1ed20513f419105`.
Executed whitebox binary:
`d8a7346db409948f258315c8dac5c8d324c6049a10201181501a737dd0726852`.

The corresponding immutable diagnostic/accepted originals are
`c5ea3e4a2ba92c87431d692a5e0b1d0600db428acf43eba10b198174e1881149.json`
and `f7a5f17a764221b2c0cbebc18bfa2ec7fb20877d47f08bb181ba0fd8de479011.json`.
These preserve the actual source/overlay and do not call an instrumented build a
pristine product build. Six callback/environment allocation requests total 320
bytes; the five primitive Ref requests total 64 bytes. The separate eleven-provider
construction point remains 1,504 requested bytes. They are distinct subjects and
must not be added as a claimed whole-parent peak upper bound.

The same clean source passed the actual read-only `node
proofs/relation-pipeline/history.mjs` entry in **306.317 seconds**: 247 declarations,
201 integrations, 25 supplements, one change completion and 89 protected files.
It checked the adopted main merge against real Git parents/blobs/modes; no generated
manifest or declaration was rewritten. The combined guard completed, its output
streams drained and both locks released. These costs are reported separately and
are not treated as evidence of CI savings.

## Remaining obligations

The new decoder closes finite ordered construction-point correspondence for
Darwin ARM64. It does not prove callback body semantics, arbitrary aliasing,
retaining handoff, all transients/shared referents or lifetime unions, allocator
rounding/fragmentation/RSS, last-owner/GC reclamation or Ledger generation and
retirement. Existing conditional capacities and unresolved whole-parent physical
upper bounds remain. Generated allocation requests, physical point observations
and a proved physical lifetime upper remain separate categories.

No full Core, Wasm, Linux physical campaign, public/packed acceptance or hosted CI
was executed in this unit. Local tests and reinspection do not grant Actions
originals or reuse authority. The outstanding successful full-main original,
compatible subsequent-main qualification, normal-PR `mutations-js` reuse,
related-input fresh execution and acquisition/authentication/transfer-inclusive
net savings stay deferred, without polling or dispatch. This unit closes a real
common Native connection gap; the project-wide objective remains active.

## Original archive

The original text records are preserved at
[`2026-10-08-parent-capture-arm64-976e45bba.json.gz`](evidence/2026-10-08-parent-capture-arm64-976e45bba.json.gz):
50 original UTF-8 members, 9,561,551 decoded bytes, raw SHA-256
`60e1ac9b3fd77bc005cb47b8139f7ea982aaceb5bc3c2bb06ddceb222e8ff6fa`;
2,317,748 compressed bytes, archive SHA-256
`65e1152078721b9807e896024b806d2408497dd734e69e5d327b868910ec4d42`. Decompression, member byte lengths and member digests were
verified. Both focused attempts, historical reinspection, actual Native/model/code
observations, accepted originals and actual history/guard records are retained.

The real object and six linked binary/debug files remain separately in this
worktree's `.artifacts/relation-pipeline/current-chain-native/` content-addressed
archives. Their exact byte sizes, digests and paths are in `retainedNativeFiles`.
The executed whitebox binary is 9,843,272 bytes and the object is 16,398,384 bytes.
The published text archive supports inspection of the original observations; it
is not a standalone copy of all binary originals and does not imply reexecution.

Publication `47f4f73752ec88ae273f5a635934161d3707148c` added only this review
and its original archive to the implementation SHA. The diagnostic source snapshot is rechecked against the
unchanged implementation after adding these report-only files; no success is
relabeled as execution of that final documentation commit.

## Subsequent main adoption

After the evidence publication, the PR's base advanced. Normal merge
`bee9f1e943d8195dd6b621cb3c9375ec490e75d9` adopted main
`6d4f9a967fd1c5e3fc4d645f9939a9a60f68f7f3` without conflict. #916 is
integrated through `434fc731e` and no longer blocks this PR; only the seven files
of this unit remain in the main-base diff. No old layout or alias was restored.

The merged tree's `proofs/relation-pipeline`, `proofs/relation-chain`,
`proofs/bounded-session`, `src/connectors/local` and `src/bounded_execution` are
byte-identical to the evidence publication. All 89 protected files in the actual
history manifest were independently reread and their bytes/modes match. The
[static integration record](evidence/2026-10-08-parent-capture-arm64-main-adoption.json)
records the exact parents and adopted changes. It establishes these static facts,
not a new Native execution or a full post-merge history execution.

Adopted main also changes public completed-output export, frontend and SDK
boundaries outside this unit. Consequently the broad source snapshot changes.
The successful Native/Lean/history original remains evidence of executed source
`976e45bba920e83cf09eef58b2d9f147684c80e2`, not of the merge or following
report commit. No report/receipt identity was rewritten and no input-reuse
permission was inferred. Unchanged selected decoder checks were not repeated;
post-merge Native/full history, public/packed acceptance and hosted CI remain
unexecuted. Reviewers can distinguish the preserved original from the subsequent
static integration confirmation.
