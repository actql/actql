# Installed Host Effect commit Checkpoints

Original base: `5c2cebdaa7931a8680b43fc0fb4a4324151f77f8`.
Current PR base: `805a29c5f1936cb1ac52ebba2cbb8cce62f5e0b9`.
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

## Current implementation and acceptance

The installed Host now composes the shared checked Effect Run owner, the
source-free Values compiler, the captured computation and Effect-source
holdings, the complete Effect Set Preview, the existing Effect ledger, the
Checkpoint journal, common apply, row/Set receipts, and Named Result
publication. Provider hooks supply current observations and physical
requests; they do not own a second apply or retry state machine.

The public Client and installed HTTP Host tests exercise two members with two
rows each. They prove direct account allow, direct deny with zero sends, a
deferred whole-Set approval answered after a Host restart, the same Run's
publication and Result read, duplicate answer and request replay without
resending, and another restart. A failed row halts only its member; the
independent member continues. A lost reply leaves one exact unknown row and
its capture/source holdings for reconciliation; it is not resent on restart.
Changing the account to deny after an approved answer sends nothing and
reclaims the captured holdings. Known failure, unknown send, and cleanup
responsibility remain distinct.

The installed Site's target-confirmation read deferral remains unsupported in
this profile. The public Client regression confirms zero reads and writes,
no unanswerable Checkpoint, and no permanently running Run. It uses a trusted
Site observation rather than the full captured/apply factory. Read allow and
immediate delegated permit remain subject to current admission.

The installed Host/Checkpoint focused suite passed 33/33 at rebased code SHA
`64174903cb0a439677656ebb89891f1eee1e3eae`. It uses a deterministic
reference Effect dispatcher, real HTTPS Host, SQLite journals, and the product
MoonBit controls; it does not use a live Salesforce org. The full Salesforce
Site suite passed 200/200 after the published-source-holding fix. The Host
checks passed through the packed Run
Host admission; package packing then hit the local home-directory npm-cache
permission error. Packing and packed Local assets passed separately with a
worktree-local cache. The lint and spec jobs passed; common MoonBit JS and
Wasm passed 6,785/6,785 and 6,782/6,782. Native type checks and the changed
Run-publication package's 15 tests passed. The full native suite was stopped
under severe local machine load locally; the Linux CI native and core/native
jobs passed at code SHA `c0b982cada6bf6e579f5b89f196622078893b6a9`.

The Client job passed its 206 tests and packed Node/browser smoke, then the
packed Checkpoint cancellation case reached a still-held capture before its
old resume lease could retire. The test retains the physical-retirement
assertion and now allows 90 seconds for a loaded runner to expire the lease
and sweep. A standalone retry was stopped under the same severe local load
before that case. The Linux CI Client job passed at code SHA
`c0b982cada6bf6e579f5b89f196622078893b6a9`, including the packed
Checkpoint case. This local evidence is from code before the main rebase;
the rebase preserved the branch patch set exactly.

[CI run 36365217542](https://github.com/actql/actql/actions/runs/36365217542)
completed successfully on that code SHA: all 13 required jobs passed and the
optional performance matrix was skipped as configured.

The existing multi-member fixture uses one Host authorization tuple for both
members. Distinct delegated target tuples under one whole-Set Checkpoint have
not been validated in this branch. This is not evidence that one approval
authorizes an unrelated target. The exact target and current account checks
must continue to precede each send; no broadened approval is inferred from
the successful shared-tuple test.

Real Salesforce standard-Host installation is a separate provider connection
and requires its own allowed test org and scope. No live mutation is claimed
here. The remaining handoff is review and user-owned merging of PR #29. This
record does not claim a live Salesforce mutation or a release.

## PR #29 review and main integration

The branch merged `origin/main` at `a01beea7c145bd2cf576cb775e6e5a5b61ef4445`
without reapplying #27. The merge retained both the installed Salesforce
source loader and the Effect installation, and both acquisition and Effect
dispatch-owner tests. This integration does not expand the Effect compiler's
source-free Values scope.

The review repairs three ownership boundaries. A resumed Effect now retains a
cleanup owner before its fallible capture read, distinguishes physical work
from preparation, and permits a later claim after a no-start failure. The
installed Host applies its required dispatch barrier before initial Effect
execution and approved continuation. Terminal unpublished Checkpoints retire
their exact captured payload holdings after cancellation, rejection, or
expiry; the private capture record is retired last so a failed deletion can
be retried. Published results and unknown sends are not retired by this path.

The review-fix code SHA is
`ace1d1b397218ea645d4245a236da29334b83a97`. Focused ownership tests
passed 17/17. The public Host suite passed 39/40 in one local run; its
existing restart-cancellation test timed out under that full-suite load,
passed alone, and passed again inside the Client gate. The Client gate's Node
suite passed 218/218, followed by packed Checkpoint, native Client, and
Salesforce Site tests. Host, lint, and spec gates passed. The first Host-gate
attempt stopped on an inaccessible user npm cache; rerunning with a
worktree-local cache passed. [Linux CI run 36370924733](https://github.com/actql/actql/actions/runs/36370924733)
completed on PR SHA `0ec7361a2098b176edfbe1da68382ec655cee2c3`:
all 13 required jobs passed, including Client and separated-network native;
the optional performance matrix was skipped. No live Salesforce operation was
run. The final documentation-only follow-up must be checked separately before
the user-owned merge.
