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

At code SHA `c4335405ddb0d19c18b25ef2728903f90f8a3699`, the installed
Host/Checkpoint focused suite passed 37/37 locally. It uses a deterministic
reference Effect dispatcher, real HTTPS Host, SQLite journals, and the product
MoonBit controls; it does not use a live Salesforce org. This SHA has not yet
passed the complete Client gate or Linux CI. The branch has not been pushed
or merged.

The existing multi-member fixture uses one Host authorization tuple for both
members. Distinct delegated target tuples under one whole-Set Checkpoint have
not been validated in this branch. This is not evidence that one approval
authorizes an unrelated target. The exact target and current account checks
must continue to precede each send; no broadened approval is inferred from
the successful shared-tuple test.

Real Salesforce standard-Host installation is a separate provider connection
and requires its own allowed test org and scope. No live mutation is claimed
here. The remaining handoff for this Host unit is to run the affected Client,
packed, Host and documentation gates on a fixed SHA, reconcile the branch with
current main, and obtain Linux CI for the pushed PR SHA. The PR is not a
release or merge claim.
