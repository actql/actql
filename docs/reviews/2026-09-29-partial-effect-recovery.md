# Partial Effect recovery

## Scope

This correction is independent of acquired-input Effect compilation. The
Salesforce acceptance fixtures were imported from
`25df0205d9517598c41b6ed4cf04f07de09388a8` as `9e44915cf` without changing
their expectations.

Initial apply continues to inspect all Preview target guards before mutation.
Recovery derives an opaque guard selection from admitted durable Ledger heads
bound to the exact Preview, request, member, row, dispatch key, and basis.
Missing heads and mismatched evidence are rejected, not treated as exclusions.
Prepared rows retain their original guard requirements. Already dispatched rows
do not compare their changed targets against the original pre-write guard.
This selection is not a send permit: existing frontier, claim, current authority,
Site, Mapping, capability, and reconciliation checks remain in force. Unknown
and dispatching rows do not become ready, and applied rows are not resent.

There is no wire, canonical preimage, or contract version change. The common
MoonBit recovery entry now requires the opaque Ledger-derived evidence; the
Node bridge and generated interfaces are updated together.

## Local evidence

The following passed on the working correction after `9e44915cf`:

- D's unchanged partial-apply acceptance cases plus unknown no-resend: 4/4.
  These use simulated HTTPS Salesforce, not a live org.
- `effect_application` JavaScript tests: 39/39, including direct missing-head,
  foreign-basis, foreign-request, and distinct-Preview-owner rejection.
- `physical_strategy` JavaScript tests: 24/24.
- Node Effect Ledger, physical dispatch, and installed Effect Site tests: 46/46.

Release runtimes were rebuilt before the provider tests. Cross-target tests,
full affected CI jobs, and pushed-SHA CI are not established by these results.
The acquired dependency inventory remains separate work in progress.

## Separate Frontend recovery report

B reported `crash-resume_claimed` returning `preparing` instead of `succeeded`
at `5ee0dec1747d6465e3829719a0adeca66caf427b`, in
`node scripts/test-packed-client-checkpoint.mjs`, reached from the Client gate.
The supplied saved log confirms that assertion with Node 22.23.2. Its cause is
not established and is not identified with this partial-apply defect.
Investigation must use that revision's packaged artifacts and inspect the
post-claim transition and completion-wait condition. Increasing a delay alone
does not establish a correction.

Frontend integration remains after the acquired-input and partial-apply work.
Its fixed series is `ba34b719516f108f80e78cf7d5024f30c7a86c31`; merge the series
rather than cherry-picking its Graph-dependent commits. Raw Local/HTTP acceptance
is distinct from B's already-tested lowered-Program packed path.
