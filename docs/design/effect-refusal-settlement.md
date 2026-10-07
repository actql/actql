# Settling Effect evidence after a resume refusal

An Effect Set can have an Applied, Accepted, or Unknown row when a later
current-use check refuses the remaining rows. A refusal cannot rewrite those
earlier rows into a pre-send failure. The existing Effect receipt issuer owns
the complete partition: attempted outcomes retain their evidence, Prepared
rows remain unattempted, and Unknown remains a reconciliation obligation.
The Host neither re-runs Compute nor sends a refused remainder to produce a
receipt. An approval answer deadline is not an expiry field on an Effect
attestation; current binding and current-use checks remain the relevant gates.

For a changed resume authorization or environment binding, the portable
Checkpoint owner can grant a settlement-only claim. This is a new private
continuation mode, not another authority decision. It uses the existing
intent, monotonic generation, claimant and expiring lease. SQLite records
the claim and its refusal marker atomically. Competing claimants remain busy,
old generations remain stale, and restoring the previous configuration does
not turn that intent back into execution authority.

The marker denies ordinary resume admission, physical dispatch and physical
reconciliation entry. It admits completion only as failed or
needs_reconciliation. The common Set issuer determines which historical row
facts exist; the common Run owner preserves the
ACTQL_E_RESUME_REVALIDATION_FAILED diagnostic and the exact unknown members.
Even fully applied historical evidence does not authorize publication under a
refused binding. Evidence-read authorization and exact capture/continuation
bindings still apply. A saved target-read binding can identify that original
capture without reopening a target-read authorization owner.

The ordinary current-use path retains its existing authorization and physical
owners. After an attempted row, its catch path issues the common Set receipt
instead of reporting a pre-send refusal. A genuinely unattempted refusal
continues to stop without creating evidence of a send.

This decision does not change public 0.1 wire bodies, CID preimages, or signed
approval artifacts. It changes the Node Checkpoint journal's private layout
from `actql-checkpoint-journal/0.1;model-call-provenance=1` to
`actql-checkpoint-journal/0.1;model-call-provenance=1;effect-settlement=1`.
New Hosts refuse the old layout before schema writes. Old binaries must not
access an upgraded journal. The explicit, backed-up offline procedure is in
[Development](../development.md#checkpoint-effect-settlement-layout).
Startup never migrates a journal or erases old evidence automatically.
