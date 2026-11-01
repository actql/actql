# Failed partial runtime cleanup

The existing `RemoteRuntimeCustody` owns historical resource duties separately
from execution evidence and current permission. A failed partial occurrence can
have a durably settled operation and sealed physical output while no completed
output subject or execution evidence exists. It cannot use completed restoration
or reconstruct fresh, unbound custody by replaying acquisition flags.

Checked partial restoration selects only `NativeSettled`, unavailable material,
and non-quarantined capacity at the exact
observed Common record revision. It binds that request/revision to the existing
admitted Source metadata wire, material generation, measurement, and physical
process owner/generation. The supplied Source and process observations must name
the same request, material and owner generation. No Source is reread and no new
output subject, evidence, operation, holding, Ledger or execution is produced.

Accepted cleanup phases are the initial `NoEvidence`/`CleanupUnknown` pair, or
the same durable `EvidenceRejected` with `CleanupUnknown` or `CleanupReleasing`.
Losing a cursor after rejection or beginning release does not reset either
durable fact. Released, force-lost, available or completed-evidence records cannot
enter this restoration.

The physical adapter admits the original metadata and measurement in the same
runtime namespace. It must establish the independently observed exit of the
original process generation, current policy and the exact physical target before
restoration. A Reader stop, Host return, legacy record, client Boolean or copied
observation cannot supply those physical facts. The Core constructor compares
the supplied original bindings; it does not authenticate a supervisor or turn
metadata into authority. `expectedRevision` is `remoteSiteControl.revision(record)`,
not an independently numbered storage revision. Physical observers and durable
CAS/COMMIT remain the responsibility of their existing owners.

Restoration retains all three unresolved output, holding and bundle duties.
Historical operation settlement is recorded without acquiring another operation.
Stop remains pending until the existing physical Owner reports its confirmed
original stop. That report alone releases none of the three resources. Each
original release must independently acknowledge, with current policy and target
checked at its actual physical boundary. Failed release and uncertain COMMIT
retain the same obligations; absence of a lost process-local handle is not ACK.

Every restored cursor starts with stop and all three release duties pending,
including during `CleanupReleasing`. Durable rejection, a lost cursor or missing
process-local resource handles acknowledge none of those duties. The owned
cleanup entry waits for the existing original stop report before returning a
reclaim action, including on re-entry into the releasing phase.

Only the existing owned cleanup progression can advance this restored custody.
Its permanent cleanup-only marker rejects success and completed evidence issuance,
including after resources have been returned. Cleanup remains bound to the
original request and monotonic revision; another occurrence, force loss,
quarantine, restored availability or evidence substitution refuses. No public
Result, Run terminal state, permission, new start or refund is inferred.

After original stop is confirmed, partial owned cleanup first emits the existing
durable evidence-rejection transition. That failed-outcome fact must commit
before beginning physical release, and remains rejected after release. The
enclosing Coordinator therefore observes the original failure; cleanup does not
leave an unfinished `NativeSettled`/`NoEvidence` success path or manufacture a Run
terminal state. An unconfirmed rejection COMMIT remains pending without resource
release, success or a replacement transition law.

Historical holding accounting uses the existing Site Owner's
`prepare_site_holding_restoration` and the same `SiteHoldingRestoration.acquire`
token. The physical owner must first verify the original request, Site, budget,
material, measurement and exclusive cleanup. The amount is the verified original
holding's byte count. The token must be retained before fallible acquisition;
capacity refusal preserves it and successful acquisition consumes it once.
This reattaches existing debt, not a fresh holding or execution/read grant.
Revocation blocks new use without cancelling that cleanup responsibility.
The shared bridge forwards those existing methods without a new accounting law.
An actual Site holding release still cannot acknowledge output or bundle release,
durable capacity return or a lost CAS/COMMIT response.

The selected controller checks exercise original binding, pending stop,
independent release, terminal cleanup, foreign state and unconfirmed COMMIT with
explicit physical ports. They do not establish actual Cloud exit, R2 or bundle
release, durable capacity return, or ordinary runtime acceptance.
