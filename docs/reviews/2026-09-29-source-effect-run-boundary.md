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
- `adapters/host-node/embedded-local.mjs` currently routes Effect submissions
  before acquired-read admission and opens a source-free Effect host. It must
  connect read admission, acquired compilation, one physical capture, and the
  existing Effect installation without provider-name branches. Its current
  `unitId: 'values'` continuation coordinate must come from the checked Unit.

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

B's `feat/frontend-public-routing` at `8512d17d818e2d494011dfe6b95ed6242608500d`
shares the same `4e5e5fea3de3902610b385e10f89a4539c4da706` base.
Its current commits own `src/source_frontend`, query syntax/lowering, SDK
wire/types, and the CLI; they do not edit C's compiler or installed Host.
The agreed Host handoff is in B's
`docs/reviews/2026-09-29-public-frontend-host-handoff.md`. C owns the
installed source alias publication, the bounded lower-and-prepare bridge,
`client-program-preparation.mjs`, and `embedded-local.mjs`. B must not add
another Host checker, acquisition owner, or Run scheduler for this route.

B's pure Frontend and SDK change can merge separately. C continues the
Source-to-Effect Host connection without waiting for that Frontend acceptance;
no query-only source input is implicitly accepted by this branch. After B's
API is fixed, C can rebase and connect its Host bridge through the same
checked preparation. Alias generation/admission and query-only parameter
failures are a distinct Host integration acceptance, not a reason to expand
the first Source-to-Effect Program profile. If B needs a Host ABI adjustment
before merging, agree on that exact bridge signature and test rather than
editing the same Host files in parallel.
