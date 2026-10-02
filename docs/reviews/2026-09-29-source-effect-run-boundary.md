# Source-to-Effect Run ownership boundary

Historical handoff: the intermediate missing connections and failed gates below
are retained as recorded. The later
[Read→Compute→Effect acceptance](2026-09-29-salesforce-read-compute-effect.md#current-status)
records the fixed common dependency and bounded public/packed recovery results.
See the [current implementation map](current-product-status.md); this handoff is
not a current assignment of owners or a list of all remaining gaps.

Baseline: `4e5e5fea3de3902610b385e10f89a4539c4da706` (`origin/main`).
This is the C-to-D integration boundary, not a new execution contract.
The first product profile has one installed Source, one installed Effect,
an immediately allowed or denied read, one bounded acquired Relation, and
an Effect that consumes a checked computed Stage Result. The read and commit
decisions remain separate. Read deferral is unsupported and must be refused
before provider I/O; Salesforce behavior stays in its installation adapter.

## Current owners and missing connection

- `src/run_publication_host/client_effect_program.mbt` and
  `src/physical_strategy/graph.mbt` keep the computation and Effect in one
  checked owner and bind each Effect source to an exact Stage Result/task.
  `src/physical_strategy/captured_dag.mbt` can open an Effect DAG with a
  captured input. The common compiler and installed DuckDB acquisition can
  now prepare one acquired root and a downstream Effect Unit from that same
  owner. The local Invocation and Artifact issuers still assume a Values
  source and an empty observation set. Extend those issuers from the same
  checked owner; do not recheck an Effect-free copy of the Program or create
  another Effect engine.
- `adapters/host-node/client-dispatch-owner.mjs` owns physical Source capture,
  Source Evidence, computation, cancellation, and cleanup for the current
  read-only path. The captured Source and Compute execution must remain owned
  until their exact output has moved into the durable Effect-source Artifact
  inventory. An ordinary read-only dispatch close is not that transfer.
- `adapters/host-common/completed-run-publication.mjs` owns Result holdings,
  independent Effect-source holdings, the Captured Run, and the release or
  suspension of their payloads. `installed-effect-site.mjs` retains physical
  cleanup before Preview preparation and uses `suspendCompletedEffectfulComputation`
  before exposing a deferred commit. The Checkpoint owner holds the sealed
  Preview and continuation; the request journal holds the Run-start claim.
- `adapters/host-node/embedded-local.mjs` now selects acquired Effect admission
  from the same checked preparation. `acquired-effect-computation.mjs` retains
  capture/Compute cleanup responsibility before opening the Source and binds
  the completed observation to the admitted Run. Immediate read denial and
  unsupported read deferral stop before Effect preparation. Success still needs
  the upstream local Invocation/Artifact dependency chain and its durable
  inventory; the continuation's `unitId: 'values'` coordinate must also come
  from the checked Unit.

The approved incompatible 0.1 dependency update is recorded in
[Captured Effect dependency closure](2026-09-29-source-effect-dependency-contract.md).
It must be connected before claiming the acquired approval/restart path works.

## Durable boundary and recovery

1. Before capture completion, the Source adapter and dispatch owner retain
   physical read and Compute cleanup responsibility. A crash or failure with
   missing input/observations cannot be restored as a completed Invocation or
   as an answerable commit Checkpoint. Existing Run and claim evidence still
   requires stop/reconciliation handling; it does not authorize recapture as
   the same completed computation.
2. The no-reacquisition/no-recomputation guarantee begins only after the
   exact observations, computation receipt, computed Result holdings,
   independent Effect-source inventory, Captured Run, Preview, and their
   correspondence are durable. The commit Checkpoint may become publicly
   waiting only after that boundary. A failed write of any prerequisite must
   not leave an answerable waiting Checkpoint.
3. Resume reads the saved captured input, computed Result, Preview, Run
   Definition, and continuation under current evidence-read authority. A
   missing or mismatched item fails closed and retains its physical/Store
   cleanup owner; it is not rebuilt by re-reading Source or rerunning Compute.
   The original source observation remains fixed. Current commit permission,
   Site generation, Mapping, and target state are checked again before send;
   a provider target-confirmation read is not source reacquisition.
4. A denied or cancelled request sends no Effect and retires unpublished
   captured holdings. Failed retirement remains a retryable cleanup duty.
   Once a write may have been sent, its exact ledger claim, stored response,
   row outcome or unknown correlation remains durable. Unknown is not success
   or failure and cannot trigger an automatic resend after restart, answer,
   status read, or cleanup retry. Known successful rows are not repeated.

## Acceptance handoff

The first reference Site acceptance must cover one acquired bounded Relation,
existing Local computation, Preview, commit wait, Host restart, approval,
Effect write, and Named Result. It must also cover immediate read refusal,
changed commit authority/target, incomplete pre-capture failure, lost write
response, terminal restart, and cleanup failure with retained owner. Public
Remote HTTP, Embedded, and repository-external tarball acceptance can follow
as a separate PR. D can use the fixed C boundary SHA to adapt Salesforce
capture/recovery; D does not need to edit C's compiler or Host files.

## Adjacent public Frontend handoff

B's `feat/frontend-public-routing` at `ba34b719516f108f80e78cf7d5024f30c7a86c31`
shares the same `4e5e5fea3de3902610b385e10f89a4539c4da706` base.
Its handoff owns `src/source_frontend`, query syntax/lowering and SDK
wire/types; CLI completion is not a dependency. It does not edit C's compiler
or installed Host. Merge this fixed series, including its Graph integration,
rather than cherry-picking individual commits.
The agreed Host handoff is in B's
`docs/reviews/2026-09-29-public-frontend-host-handoff.md`. C owns the
installed source alias publication, the bounded lower-and-prepare bridge,
`client-program-preparation.mjs`, and `embedded-local.mjs`. B must not add
another Host checker, acquisition owner, or Run scheduler for this route.

C continues the Source-to-Effect Host connection without waiting for Frontend
acceptance; no query-only source input is implicitly accepted by this branch.
After the acquired-input and partial-apply recovery handoff, connect B's Host
bridge through the same checked preparation. Alias generation/admission and query-only parameter
failures are a distinct Host integration acceptance, not a reason to expand
the first Source-to-Effect Program profile. If B needs a Host ABI adjustment
before merging, agree on that exact bridge signature and test rather than
editing the same Host files in parallel.

## Verification checkpoint before dependency inventory implementation

At `b8e4d4e085a839b445477323bb2828aa7098a6c0`,
`node scripts/local-checks.mjs run client` passed all 254 initial Node tests
and the packed Node/browser Client smoke. The following packed Checkpoint
test failed at `test-packed-client-checkpoint.mjs:802`: `recover-transient`
observed one recovery callback, while the assertion after a fixed 2.5-second
wait expected two. This is a failed gate, not evidence of complete Client
acceptance. Later commands in the client job did not run.

The retained event log contained the second automatic recovery observation
after the failed assertion. `91636b5df` replaces the fixed wait with bounded
observation of that event; it does not retry work or relax exact dispatch and
Compute counts. `node scripts/test-packed-client-checkpoint.mjs --recovery-only`
passed both transient and permanent recovery cases. This focused success does
not replace the unfinished full Client job or Linux CI.

The contract delta was shared with D in
[PR #53](https://github.com/actql/actql/pull/53#issuecomment-5882725751).
That handoff is not an executable acquired-Effect acceptance SHA. The new
dependency graph checks cover bounds and topology locally; product issuance,
durable storage and recovery admission still need to use them.

## Acquired root local Invocation

The acquired publication preparation now issues the root Unit's local
Invocation through `issue_acquired_client_effect_local_invocation`. Its
observation is the admitted Source Evidence, not the Run-wide Observation Set.
The issuer checks the exact prepared graph/task, live capture, captured Relation
identity, and Query requirement owner, then matches the logical input and
observation using the existing common admission rules. No new Relation scan,
source acquisition, compile, or grant is performed by this issuer.

The existing real-DuckDB acquired Effect test covers successful issuance,
distinct checked owner rejection, changed logical input and authority evidence,
and rejection after capture release. The admitted altered evidence is constructed
before each negative assertion so a malformed envelope cannot stand in for the
owner/binding check. The common Host package's 15 JS tests also pass, including
the existing independent source-free Invocation preimage expectation.

This closes root identity issuance only. Imported Stage Results still require
their complete local Manifest and typed upstream dependency inventory. Durable
storage, restore admission, and approval-wait acceptance are not established by
this test; the new root owner is retained in the publication context for that
connection. No executable acquired-Effect handoff is claimed yet.

## Terminal preparation settlement after an expired claim

The Client job at `5fafae9584a319c92c94d9a15665547b6a1ed778` failed
253/254 initial Node tests. The public HTTP cancellation-after-definition
test left the preparation in `resuming` after the Run became `cancelled`.
A focused run reproduced this; diagnostic steps showed claims stopping
without a recorded completion failure. No later packed job ran.

The preparation's `end()` swallowed `ResumeClaimStale` and returned as if
settlement had completed. When the lease expired during observation, no
retry responsibility remained in the sweep. The fix propagates that failure
to the existing owned drain, which records it and schedules re-observation.
The next claim observes the same terminal Run and completes the preparation;
it does not execute the Run again or weaken the journal fence.

A real Checkpoint journal/evidence test advances the injected clock during
terminal observation. Without an explicit wake it requires the owned retry
to complete cancellation, with zero execution calls. Restoring the old catch
makes this test fail with `TerminalSettlementRetryMissing`. The corrected
test and three existing service tests pass (4/4); selected public HTTP
cancellation and unsupported-read cases together with these pass (10/10).
The full Client job and pushed-SHA CI remain unverified after this fix.

This is not a diagnosis of B's separate `crash-resume_claimed` failure at
`5ee0dec1747d6465e3829719a0adeca66caf427b`. That failure still requires its
own fixed-SHA reproduction and state-transition evidence.

## Checked dependency Result custody

`pin_captured_effect_sources` now derives the required local Result inventory
from the checked Effect source Units and their transitive Result imports. It
retains all Results needed for those Units' complete local Manifests, not
unrelated Units. Exact checked import owners select the ancestry. The pass is
bounded by 65,536 work units, 64 import edges in a path, and at most 4,096 local
Results (also limited by the caller's pin bound). It uses the existing atomic
Result pin set and its rollback/release path, without another allocation ledger.

The acquired root has no selected Compute target. Its Result borrow therefore
checks the actual captured Source completion against the checked Result
occurrence, retaining original capture liveness. The bounded Result exporter
applies the view without exposing an unrestricted raw Source output. Closing
an ordinary root port prevents new pins while existing pins retain custody.

The real-DuckDB acquired Effect test verifies the independent expected
inventory `[(0, "r"), (1, "r")]`, refusal under a one-Result bound, successful
two-Result retention, and revocation after release. Ten selected MoonBit
consumer/export tests pass, including the import-depth and work-bound checks.
Three-target interface generation succeeds; full affected gates are pending.

This is physical custody, not durable dependency admission. Artifact/Manifest
issuance for these retained Results, complete typed dependency bodies, Store
inventory persistence, and restart admission still need to be connected before
an acquired Effect can publish a resumable approval wait.

## Dependency export custody and last-consumer retention

The common captured Effect owner now establishes the checked dependency-output
obligations before Compute starts. Automatic last-consumer release excludes
only these outputs; ordinary Effect-free release is unchanged. Explicit Run
cleanup still closes them. This prevents a completed intermediate Result from
disappearing before dependency export, without retaining unrelated Units.

`CapturedEffectLocalResultExport` binds the exact pinned inventory, Result
occurrence, preparation and live receipt. The existing bounded exporter and
managed import bridge serve both Effect members and dependency Results. A
dependency is not presented as a fictitious Effect member. Common-package
tests reject another Result, an equal-valued separate export, another pin set
and a released receipt. No CID string can replace this owner proof.

The complete Node bridge file passes 27/27. It includes real DuckDB acquisition,
independent expected rows for root and computed Results, and three-Stage
dependency exports after all Compute consumers finish. Explicit inventory
expectations include every required local Manifest Result. The old split-Stage
tests needed their pin budgets to include these added dependency holdings;
the independent member-release and exact producer assertions remain intact.
The physical strategy package and direct export-owner test pass 25/25 on JS.

This is not yet a durable dependency closure. Temporary-output release after
successful inventory/body persistence, persistence-failure cleanup, imported
Invocation/Artifact issuance, and restart without acquisition or Compute must
still be connected and tested before the executable D handoff. Approval wait
must remain behind that complete persistence boundary.

B's subsequent Result transformation input is
`1677d15d4c904517f2d590c0b6591dda2b4b44e7` on
`feat/frontend-sga-operators`. It is not integrated here. Frontend and Result
transformation integration follow the acquired-Effect and D recovery handoff;
B's component checks are not evidence of connected packed Local/HTTP success.
