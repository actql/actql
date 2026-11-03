# Original captured inputs and keyed census

- Responsibility: The existing physical Resource owner checks its original
  ledger census across captured inputs, a checked prefix, keyed assembly,
  physical keyed children and downstream consumers. These predicates issue no
  census, reservation, read permission, completion or cleanup acknowledgement.
- Inputs and outputs: Plural predicates receive the same Ledger and/or
  OriginalLedgerIdentity plus exact ordered (Reservation, Holding) originals,
  the original prefix/assembly tokens and the private accepted-child count.
  They return eligibility or downstream-retirement facts. Single-input APIs
  retain their existing behavior and token layout.
- Identity: Each supplied pair must occupy its exact original census position,
  belong to the same ledger, have matching reservation serials and strictly
  ordered issuance serials. Missing, swapped, duplicate, foreign or substituted
  originals fail. The prefix follows all originals; assembly and keyed child
  tokens follow it in their original order. Counts cannot replace token identity.
- Ownership: Source receivers retain their capture tokens, the existing prefix
  retains its reservation and keyed receivers retain their own physical children.
  Census predicates borrow those identities without taking their cleanup duties
  or exposing a replacement ledger. Original holdings must remain in the census
  while any dependent is borrowed.
- Synchronization: These checks invoke no user callback. Their caller must use
  them after currentness/liveness callbacks and before the associated reservation
  or borrow. Original ledger preparation availability, immutable binding state,
  delegation inventory and spent attempt history remain enforced.
- Failure: Wrong token position or owner, changed inventory, dead holding,
  pending cleanup, unavailable phase, invalid count or overflow refuse. Captured
  prefix preparation permits nonpending live Source backing; keyed-child and
  serialization eligibility require every original Source reservation settled.
  Failure does not reset consumed history or release allocations.
- Cancellation: Closing a scope is not physical retirement. Cleanup predicates
  authenticate the exact original pairs still present and then inspect actual
  dependent reservations/holdings without requiring new-use eligibility. A
  closed token may retain its historical pending flag after trusted ACK.
  “Dependents retired” never acknowledges the prefix itself or permits early
  retirement of its upstream captures.
- Resources: These are read-only bounded-by-inventory traversals with no copied
  census or new allocations. The caller must already fund and bound its ordered
  tuple inventory. Prefix, assembly, keyed children, captures and downstream
  consumers keep their separate simultaneous quantity obligations. Insufficient
  capacity leaves existing originals and attempt history unchanged.
- Extension: The plural API explicitly generalizes single-input arity while
  preserving phase, settlement, same-original and cleanup laws. It introduces
  neither a new resource owner nor a count-only exception or spare-budget path.
- Verification: original_captured_inputs_wbtest.mbt covers exact tuple ordering,
  missing/duplicate/foreign tokens, live and pending source backing, prefixed and
  unprefixed layouts, spent attempts, failed capacity reservation and pending
  downstream cleanup. Existing single-input keyed census tests remain applicable.
  These focused tests do not establish installed Source authorization, full
  composition funding, runtime artifacts, publication or release acceptance.
