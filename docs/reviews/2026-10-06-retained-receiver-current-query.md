# Current retained receiver query

## Problem and connection

A saved retained Transfer result is historical evidence. After Coordinator
reconstruction, it cannot stand in for the current Native receiver journal.
The existing real-process diagnostic previously read the Site SQLite database
from the Coordinator process to obtain that record.

The current query uses the existing authenticated poll/observation transport and
the original producer holder. The common issuer carries the exact original plan
and a caller-supplied fresh query ID. The Native holder reads its existing
`ResidentRetainedTransfer`, actual durable receiver record and exact receipt.
It rechecks current producer, Site generation, authority, delegation and lifetime
before answering. Incomplete handoff, missing live owner, cleanup begun, revoked
movement or foreign plan cannot produce a successful current reply.

The common response includes the full durable record, original dispatch/plan
and exact query ID. Admission rejects another challenge, substituted identities,
uncommitted destination, incorrect receipt/CID and noncanonical bytes. The Node
API exposes opaque query/reply handles and immutable facts. The gateway waits
for common admission and confirmed Host custody before retiring delivery or
acknowledging the report. An old response or custody failure leaves it pending.

Queries do not advance Transfer, reserve or return capacity, pin borrows, create
attempts or enter executors. Snapshot facts are historical after capture: the
caller must issue a new challenge and authenticate its response for a new live
query. Persisted replies are not current authority after reconstruction. Native
still validates actual receiver custody and claims execution exclusively before
physical consumer start. This unit introduces no scheduler, ledger, fallback or
state-based permission to restart execution.

## Compatibility and dependencies

This is an additive initial-0.1 protocol/control/API change. Older non-resident
poll consumers explicitly reject this operation as non-executable work. The
existing original plan, transfer result, checked input binding, dispatch,
Output ACK and release contracts remain unchanged.

The branch depends on OSS #560 and its retained-input API/Native dependency
chain. The final merge target is OSS main, after the parents merge. A reviews
the common-owner boundary; F owns Native and Cloud callers. Formal Cloud
adoption remains a separate change from merged OSS main, with all five packages
and the matching Native binary. The current Cloud manifest is not changed here.

## Verification scope

- Common JS protocol: strict current envelope/reply admission, exact query and
  immutable durable revision; independent expected state `[3,2,0,1,0,1,1,1,1]`.
- Node Run Host: real common Transfer transitions, stale challenge rejection,
  current generation/grant/expiry refusal, limits and opaque-handle rejection.
- Authenticated localhost gateway: deliberately isolated admission port tests
  old-query rejection, Host custody failure and exact report retry. These mocks
  are transport fault evidence, not physical receiver evidence.
- Native selected caller: actual producer/receiver/consumer Owners, unchanged
  capacity/revision on query, current authorization refusal, foreign plan refusal
  and no current success after cleanup begins or completes.
- Native real-process acceptance: Coordinator reconstruction, actual poll to
  original holder, actual current receiver response, retained input binding and
  real consumer execution. Source/producer/consumer counts remain 1/1/1;
  independent result is `[{"id":3}]`, number schema; Output receives a typed ACK;
  both tasks formally release, all temporary resources/reservations/pending
  intents become zero, and the retained published result is reread.

The real-process gateway stands in for Cloud. It is not public Cloud acceptance,
a Cloud Run start CAS, or producer-holder recreation. Those boundaries remain
unverified. Historical #88 recovery obligations are unchanged. No deployment,
merge, whole Core or whole packed campaign is performed by this unit.

## Known preparation limitation

Package-level `moon fmt --check` also visits two unchanged parent files,
`remote_resident_host/retained_execution.mbt` and
`remote_resident_source_compute_tests/retained_runtime_wbtest.mbt`, whose existing
formatting differs from the pinned formatter. That failed run is retained.
The 12 changed MoonBit source files pass direct byte comparison against the
same pinned `moonfmt`. This is changed-source formatting evidence, not a claim
that the whole package formatting gate passes. The parent-only formatting
issue must be resolved before final required verification.
