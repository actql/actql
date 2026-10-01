# O5 R2 exact-dispatch recovery

## Completion unit

The common Coordinator owner permits transport recovery of the original
occurrence after an exact authenticated query. It does not permit executor
restart. R1 observation history and R3 query priority are inherited from main.
O2 cancellation, O6 Site restart/generation switching, Cloud adoption and the
whole §6 history-bound proof are not included.

The implementation starts from merged main
`295af44bd8a92d5adaa6b400b47cb516808ba00d`. All delivery/material bytes are
retained before initial send, without changing dispatch/Run CID inputs or wire
versions. See [the architecture boundary](../design/remote-site-execution.md#exact-dispatch-recovery-after-response-loss).

## Storage and API differences for F

- `@actql/coordinator-core.deliveryEnvelopeJson(request, body): string` checks
  the exact canonical envelope and dispatch/binding association. It does not
  replace the original Run materials issuer or Site Run admission.
- `redeliveryEligible(record, request, notSeenBody, context): boolean` is a
  pure decision from the existing durable Coordinator record. `context` is
  `{coordinatorAuthority, siteKey, siteGeneration, authorizationCurrent,
  cancellationRequested}`. Its authorization/lifetime/cancellation facts must
  come from the Host's current trusted owners, not a received response.
- `exactRetransmissionEligible` now includes historical Accepted as a
  structural candidate only. Use the new current-context/query decision before
  delivery. Neither function grants physical start permission.
- Node `createRemoteSiteCoordinator` adds an opt-in installed
  `currentDispatchContext(dispatch, envelope)` projection and one bounded
  `recoverDispatch({dispatch, ...transport}): Promise<{action:
  'redelivered' | 'reconciled', observation}>` step. The ordinary activation
  authorization gate still runs; new dispatches also check the projection
  before persistence and after commit. No automatic loop is installed.
- Node SQLite `accept(admission, request, control, envelope?)` atomically saves
  the immutable envelope with a new intent. `deliveryEnvelope(request, control)`
  returns/re-admits it. `maxDeliveryBytes` defaults to the existing encoder
  bound 1,442,816; the default resident configuration requires the tighter
  1,048,576 cap used by this integration fixture.
- Additive `dispatch_deliveries` table/capability, not a second Run journal.
  Existing R1-compatible intent/history/output rows remain readable. Missing
  delivery refuses automatic recovery with
  `RemoteDispatchDeliveryMaterialsMissing`; query/evidence/release remain
  usable. A late/different attachment is refused. No snapshot is invented.
- An exact gateway not-seen rejection now retains `notSeenBody` for typed
  owner re-admission. Timeout or a naked error code never becomes not-seen.

Minimal public-package use, after restoring the durable owner and admitting
the authenticated query through the existing observation/commit API:

```js
import {deliveryEnvelopeJson, redeliveryEligible} from '@actql/coordinator-core';

// originalEnvelope was issued from the original retained Run/dispatch owners.
const envelope = deliveryEnvelopeJson(request, originalEnvelope);
// Persist envelope WITH the initial intent before ANY initial transport.
// On restart read those exact saved bytes; do not call an issuer to replace them.
if (redeliveryEligible(record, request, exactNotSeenBodyOrEmpty, {
  coordinatorAuthority: trustedAuthority,
  siteKey: installedSite,
  siteGeneration: currentInstalledGeneration,
  authorizationCurrent: currentRunAndAuthorizationDecision,
  cancellationRequested: currentCancellationFact,
})) {
  await deliverExactSavedEnvelope(envelope);
}
```

Cloud must bind envelope/Run materials through its retained Run owners and
persist them in its existing durable commit boundary. Receiving materials alone
cannot supply that trust. F owns that implementation and package adoption; C
does not provide a second Cloud coordinator or claim real-Cloud verification.
The fixed source SHA and final CI link belong in the PR/conversation, not an
alternative moving dependency pin in this document.

## Direct regression coverage

- Common owner: typed not-seen vs timeout, Accepted vs started history, current
  authority/Site/generation/lifetime/cancellation facts, foreign identity and
  historical Accepted replay without state/revision mutation.
- Real SQLite: atomic intent/envelope commit, abrupt SIGKILL directly after
  commit (no close), failed COMMIT and committed response loss, immutable
  reassociation refusal, configured byte cap, R1 schema without capability,
  existing query/history/cleanup continuation, existing close custody tests.
- Node Coordinator: no send after failed/unknown initial save, exact snapshot
  after reconstruction, current checks after query awaits, timeout refusing
  send, stale observations, legacy query/release and original-Run refusal.
- Real native Site: post-commit acceptance HTTPS ACK loss, concurrent same
  dispatch recovery, Coordinator reconstruction, start between Accepted query
  and recovered arrival, terminal ACK loss, old Accepted replay after terminal.
  Two original attempts have exactly two executor entries and two durable start
  claims, with no additional occurrence. Both Outputs transfer and physically
  release; final reserved payload bytes and pending intents are zero.
- Packed `coordinator-core` checks the new public APIs; packed `run-host-core`
  and `coordinator-core` issue/admit the original materials/envelope and decide
  from actual native Accepted bytes. Installation is outside the checkout; the
  existing evidence helper retains digest/stdout/stderr/exit observation and
  removes only that run's installation artifacts.

Commands (pinned toolchain on PATH; `ACTQL_TEST_SCRATCH_ROOT` outside checkout):

```sh
moon test --target js src/remote_site_protocol
moon test --target wasm src/remote_site_protocol
moon test --target native src/remote_site_protocol
node --test adapters/host-node/sqlite-coordinator-journal.test.mjs adapters/host-node/remote-site-coordinator.test.mjs adapters/host-node/outbound-site-gateway.test.mjs
node scripts/test-packed-coordinator-core.mjs
node scripts/test-packed-resident-materials.mjs --redelivery-only
```

The first packed integration run exposed a test counter mismatch: baseline
counted every acceptance failure while its wait counted only transport ACK
failures. A journal-contention diagnostic therefore prevented that wait from
finishing even after the second real ACK loss. The fix counts the same event
on both sides; executor/claim/cleanup expectations were not relaxed. Evidence
from the failed run is preserved separately from successful runs.

Output plan/result report replay is not dispatch-observation R1. The existing
gateway fixture validates those through their typed plan/result waiters; late
duplicates without a matching Output receipt are not falsely ACKed by the
dispatch receiver. Full durable Output-report recovery remains outside R2.
