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
- The installed Host routes source-free checked Effect Programs through the
  shared Effect Run owner. Unsupported shapes are rejected before a deferred
  Run-acceptance Checkpoint is saved, and acceptance reuses its compilation.
- The existing Checkpoint sweep invokes an installed Effect continuation after
  answer or restart. A simulated Site test covers the same Run, a durable
  claim, send-time admission, one send with an unknown reply, duplicate answer,
  request replay, and another restart. This is not publication acceptance.
- Cancelling a waiting Effect Run now closes its exact open Checkpoint and
  exposes a cancelled Run with no Effect send. After approval, cancellation
  atomically fences an unsent resume against its dispatch admission. An
  admitted send remains a reconciliation duty. The Host also reconciles a
  cancellation recorded just before the Checkpoint became visible.
- A trusted installed Site can report a known pre-Preview refusal with no
  external Effect dispatch. The common dispatch owner records a failed Run
  only after its physical cleanup completes; an exception without that
  observation remains unknown. The public Client test covers deferred target
  read, zero Site reads/writes, no unanswerable Checkpoint, and restart.
- The installed Host now supplies a scoped `recoverCapture` operation to its
  Effect callbacks. It resolves the original request ID from the exact
  accepted RunRef and reuses the common evidence-read admission. It never
  reissues an Invocation or reruns Compute. Evidence recovery may proceed
  under its own signal after execution cancellation, but mutation admission
  remains separate. The current mock Site proves the exact lookup and
  absence result; a retained-capture success through this port is still
  required.
- The installed Host issues the source-free publication Plan and Invocation
  from the accepted checked owner before the physical-start claim and passes
  that exact Plan to the Effect execution callback. No second preparation or
  compilation is performed. Plan issuance failure is recorded before any
  physical start; this wiring does not by itself publish an Effectful Run.

## Remaining product connections

1. Connect captured computation, Preview, row intents and commit authorization
   to the installed Checkpoint service. Keep live cleanup with the existing
   dispatch owner; a suspended computation is not a failed Run.
2. Recover the exact durable capture and Effect ledger after an answer or
   restart, without reclaiming Run-start permission or rerunning Compute.
3. Connect admitted-send reconciliation and retained-capture cleanup to
   public Run observation and cancellation. Do not mark an
   admitted-but-unconfirmed send as cancelled. Complete or reclaim retained
   captures on the appropriate existing terminal transitions.
4. Run public Client / installed Host fault-injection acceptance against a
   complete captured/apply installation. The current deferred-read test uses
   a trusted mock Site observation, not a provider Ledger or captured input.
5. Publish an approved Effect Set and Named Result through the installed Host.
   The current simulated continuation deliberately ends in reconciliation; it
   does not prove typed row receipts, complete apply or publication.

The Connector-owned product installation remains the concrete cross-owner
dependency. `openInstalledRemoteHttpHost({effectInstallation})` now passes the
accepted `publicationPlan`, checked `owner`, and exact-Ref `recoverCapture`
to `effectInstallation.execute`; its restart sweep passes `recoverCapture`,
the retained Checkpoint continuation and its claim journal to
`effectInstallation.resume`. The Connector implementation must compose its
existing capture, Preview, `completeCapturedEffectRun` and
`completeRecoveredEffectRun` through those callbacks, preserving the same
request, Run, Effect ledger, Store holdings and unknown-row responsibilities.
The Connector branch has no production factory for this installed interface
at the verified Connector HEAD `9911151e3`; its comprehensive integration
composition remains in a test. C must not replace it with another compiler,
Effect state machine or provider-specific Host branch.

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
- The installed Host and Checkpoint test files passed 29/29 on the working
  tree, including the new Effect restart cases. The shared Effect Run race
  case passed 1/1 with the pinned MoonBit toolchain. These do not replace the
  remaining complete-apply and publication acceptance tests.
- At code SHA `27601313c10af02f8e9e2f498abb21eb6f71e15e`, the complete
  `check:distribution-client` job passed locally: 195/195 Node tests, packed
  Node/browser smoke, packed Checkpoint acceptance, and native Client mTLS.
  The preparation-failure regression also passed 1/1 with the pinned
  MoonBit toolchain. This is not Linux CI or a complete Effect apply test.
