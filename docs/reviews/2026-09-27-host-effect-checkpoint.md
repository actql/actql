# Installed Host Effect commit Checkpoints

Base: `5c2cebdaa7931a8680b43fc0fb4a4324151f77f8` (main after PR #21).
Branch: `feat/host-effect-commit-checkpoint`.

## Agreed completion scope

- Source-free Values, one Unit, Result-referencing Effects, multiple members
  and rows. Acquisition compiler extensions are not part of this change.
- Public Client and installed Host: review the Preview, approve the complete
  Effect Set, restart the Host, answer and resume the same Run, execute, and
  observe Run state and Named Results.
- Whole-set approval does not imply atomic mutation. Existing independent
  member and within-member failure semantics remain authoritative.
- Answers do not replace current authorization, target freshness, resume
  claims, generations, leases or admission immediately before sending.
- Duplicate answers, status queries and restarts do not resend mutations.
  Unknown outcomes retain their existing reconciliation responsibility.
- Deferred target-confirmation reads are not resumable in this profile.
  Reads require current allow or a valid immediate delegated permit. Defer
  is unsupported, not policy denial or cancellation; it must create neither
  an unanswerable Checkpoint nor a permanently running Run. No read or write
  precedes admission, and captured-resource cleanup remains owned.
- Use existing checked owners, compiler, Effect ledger, Checkpoint journal
  and dispatch cleanup owner. No new scheduler or approval state machine.
- Submit one PR; do not merge it. Real Salesforce installed-Host support is
  distinct from the simulated Site acceptance of this Host boundary.

## Implemented building blocks, not end-to-end completion

- The Client signs the existing Effect approval-attestation profile and
  Run-bound Resolution. An approving signer supplies the Run authority scope;
  the installed Host verifies that scope and the trusted reviewer signature.
  Only Host-requested partial-application claims are included.
- The installed Checkpoint service retains encrypted review and continuation
  evidence, lists Run continuations, and can admit the same approval after a
  service restart. Read deferral has no continuation port and returns the
  existing unsupported decision before provider I/O.
- Captured computation suspension releases process-local prepared payloads
  without retiring the exact durable capture. It cannot be used with a foreign
  owner or changed into terminal retirement on the same released owner.

## Remaining product connections

1. Install the existing `installNodeClientEffectRun` in `embedded-local.mjs`
   and route supported checked Effect Programs to it without rechecking or
   recompiling through the Effect-free path.
2. Connect captured computation, Preview, row intents and commit authorization
   to the installed Checkpoint service. Keep live cleanup with the existing
   dispatch owner; a suspended computation is not a failed Run.
3. Recover the exact durable capture and Effect ledger after an answer or
   restart, without reclaiming Run-start permission or rerunning Compute.
4. Connect authoritative Checkpoint and reconciliation states to public Run
   observation and cancellation. Complete or reclaim retained captures on the
   appropriate existing terminal transitions.
5. Run public Client / installed Host fault-injection acceptance, including
   unsupported read deferral's public state, zero sends and cleanup. Service
   admission tests alone are not evidence that the installed Program path works.

## Verification so far

Working-tree verification, not a fixed-SHA or Linux CI completion claim:

- Built the Node Host, Checkpoint and Salesforce test runtimes with the pinned
  MoonBit toolchain. No generated runtime bundle is tracked.
- 79 targeted tests passed across Effect Run integration, Client Checkpoint
  signatures, installed Checkpoint service, prepared-result cleanup and the
  SQLite Checkpoint journal.
- The pre-apply restart integration uses the new capture suspension operation,
  restores the saved capture in another process and reaches publication.
- These are local tests and simulated provider tests. No real Salesforce
  authentication or mutation was performed. Full Host/Client/packed jobs and
  Linux CI remain unverified for this branch.
- The prepared-result cleanup test had an obsolete synthetic retention object;
  its successful-export case now uses an admitted retention contract so that
  it reaches the intended physical release/retry assertions.
