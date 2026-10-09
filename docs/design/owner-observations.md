# Scoped Owner observations

`Execution.observeOwners({cursors, maxEntries, maxWireBytes})` is a read-only
Client–Host operation. It reads the existing Run-state issuer and admitted
Effect Ledger. It never submits, cancels, resumes, reconciles a provider, or
opens a Result delivery. Trace sampling and telemetry are not history sources.

The response is explicitly `non_atomic`, with `owner_local` ordering. Each
disclosed component retains its Owner scope and stream identity. Effect pages
follow the existing append-only Ledger revisions; no order between independent
streams is asserted. A Run snapshot is a freshly authorized current view with
`history.kind: not_provided`. Its control revision remains a Run control fact,
not a composite event number. A snapshot content CID in the revision vector
does not grant authority and is not an action dependency.

## Replay and unavailable history

A Host-signed cursor binds the exact namespace, authority, Run definition,
Owner scope, stream, Ledger generation, revision, and entry CID. Its finite
five-minute lifetime is independent of Ledger retention. Every acquisition
uses current authorization before and after asynchronous reads. A signature
is not a read grant, and a revoked projection is discarded before serialization.

The closed outcomes distinguish:

- `not_provided`: this Owner provides a current snapshot, not transition history.
- `cursor_expired`: the scoped signed token expired; this says nothing about
  whether the Owner retains its history.
- `retention_expired`: an Owner explicitly certifies retention expiry. The
  current Effect Ledger does not issue this fact because it has no expiry
  contract; the collector never infers it from a missing file or row.
- `cursor_mismatch`: a currently disclosable stream cannot admit that cursor.
- `history_unrecoverable`: the existing Owner cannot restore the retained prefix.
- `acquisition_failed`: a current attempt to obtain the component failed.
- `limit_exceeded`: the declared finite acquisition or composite wire budget
  cannot cover the component.

A fresh snapshot can accompany a history problem. It does not repair missing
transitions. A failed component does not conceal an independent Run snapshot.
Undisclosable components have a generic `unavailable` projection without a
private stream identity, head, revision vector entry, or detailed history gap.
Caller cursor positions that cannot be bound to disclosed components appear in
`unmatchedCursors` as `unavailable`. This does not prove a history absent.

Effect snapshot and page states are the admitted Ledger states. For example,
`dispatching` means a saved send claim without a saved terminal Ledger outcome;
it is not a completion claim. The separate common Run/member outcome owner may
project that fact as an unknown Effect outcome and `needs_reconciliation`.
Observation does not rewrite either fact.

## Bounds and responsibility

The wire bounds at most five components/cursors, 1,000 entries per page and
65,536 UTF-8 response bytes; a request can choose smaller limits. The installed
Effect connection inventories up to three item streams in the original
request scope and explicitly reports further coverage as `limit_exceeded`.
Inventory locator order is pagination order, not event order. Whole-envelope
budgeting includes snapshots, vector bindings and signed cursors.

The reader borrows no dispatch or provider hooks. It opens admitted read
connections to the existing Ledger and closes them after acquisition. Failed
physical closes retain the exact cleanup handle in installed Host shutdown;
retry closes that handle without rereading, reopening, or changing the Run.

## Deliberately unconnected scope

This connection exposes current Run snapshots and formal Effect Ledger pages.
It does not expose Site, publication, or Delivery components, certify atomic
cuts, introduce push subscription/reordering state, or create histories for
current-only Owners. Those existing issue-wide #454 requirements remain separate
from this public mixed-history acceptance scope. Native generated wire shapes
are checked on Native; this does not add a Native CLI observation command.
