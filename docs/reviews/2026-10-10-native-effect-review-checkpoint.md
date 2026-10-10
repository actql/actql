# Native Effect review Checkpoint preparation

## Connection

`ResidentSourceCompute.prepare_effect_review_checkpoint` prepares the common
Checkpoint from the original, separately retained computation and Provider
Preview. Both existing custody owners must authenticate their saved evidence.
The complete computation holding, Store authority, original Run, request scope
and recovered row keys must agree before preparation succeeds.

The existing installed Effect continuation envelope carries a Native provider
snapshot: the exact retained-input binding, Captured Run wire, original private
review wire, authoring context and original request identity. Its continuation
CID covers the entire canonical value-preserving wire. The review projection
CID covers the original review bytes, while the required artifact remains the
common Preview semantic CID. These identities are intentionally distinct.

The review window must remain inside the original Run/policy lifetime. Evidence
preparation does not grant current authorization; the waiting, approval and
physical-start owners must independently check it.

No Source acquisition, Compute, Provider request, external write, custody release
or reservation return occurs here. The producer, receiver, borrow, computation,
Preview and Named Result obligations remain separate.

## Refusal boundaries

Preparation refuses a foreign Run or request, an unavailable input owner, failed
authenticated evidence readback, a retired Preview, an invalid lifetime and
encoding beyond the existing byte/node/depth bounds. A Checkpoint is never
issued from an unconfirmed Store acknowledgement alone.

The existing real Native Provider Preview fixture checks the original target
before/after values, zero external writes, separate encrypted custody and
cleanup retry. It now also checks exact Checkpoint byte identities, stable
repeat preparation, closed-Store refusal, foreign request refusal, invalid
lifetime refusal and refusal after the Preview owner finishes cleanup. Store
reopening retains the same live Ledger; it is not Host restart acceptance.

## Remaining connections

This is preparation, not durable Checkpoint custody or a Run waiting commit.
The caller still must store and authenticate these exact continuation and review
bytes through the existing Store owner, then commit waiting through the existing
Run owner. The Native provider snapshot is not a Node provider profile and is
not yet a holder-restoration or Effect execution/recovery API.

The full public SDK waiting/approval path, restart reconstruction, current
reauthorization, Effect write and unknown-outcome reconciliation, Result
publication and formal release remain unfinished. This change does not update
Cloud's formal OSS cohort and does not claim real Preview Effect acceptance.
