# Source-to-Effect Run ownership boundary

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
