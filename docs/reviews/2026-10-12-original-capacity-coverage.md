# Read-only coverage of original byte custody

`capacity_reservation_covers` compares both required retention and execution
workspace against the same original `CapacityReservation`, on its exact Ledger.
Negative requirements, a closed/pending token, foreign Ledger, transfer allowance
or quantity-bearing token refuse. Comparison performs no reservation, serial
allocation, claim, handoff, settlement or mutation. The existing exact-match
predicate remains exact and unchanged.

This is a consuming Owner's preparation check, not authorization, original
identity admission, an inventory proof or a one-shot execution claim. The caller
must separately establish the genuine original custody and its complete
simultaneous retained/workspace requirement. Repeated true observations do not
authorize another consumer or another physical operation. Unknown send outcomes
and cleanup pending are not converted into free capacity or permission.

The intended Resident Catalog caller must include its original seven-field
initial-use record, current/claim/save callbacks, scope/grant, retained operator
configuration snapshot, original Journal/control and overlapping workspace.
It must select the nominal token through the existing producer/consumer/Journal
Owners, maintain current authorization fences, and retire it through the same
existing cleanup Owner. This primitive does not install that caller or select
numeric Host widths, and does not settle Catalog or capture responsibility.

Independent cases check exact/subset and both one-short dimensions, negative and
maximal requests, repeated observation without mutation, foreign/pending/closed
and non-byte custody, and unchanged exact matching. Existing read-capacity
cleanup/identity/quantity cases remain part of the focused selection.

Hosted CI, new runtime/package producers, Native execution, Provider operations,
physical DO/TLS, deployed/public Effect/Result/release and numeric Host profile
adoption remain unperformed. No new limit, Ledger, permission or wire/CID is
introduced. This independent primitive targets main; it does not depend on the
private Resident Catalog stack or demand its whole acceptance as a merge gate.
