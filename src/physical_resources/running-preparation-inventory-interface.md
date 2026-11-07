# Running preparation census growth

- Responsibility: The existing PreparationCapacity and Ledger extend their own
  census after Run adoption, before a domain constructor needs additional slots.
  This operation admits backing, not Source access or a new Run.
- Inputs and outputs: The original capacity, input, completed body and census
  identity accompany complete retained/execution peaks and monotonic slot maxima.
  Success updates the same reservation and slot capacities; failure returns the
  existing Resource or preparation issue.
- Identity: Input, body, Ledger, bootstrap, census and identity must all match by
  physical identity. Run phase and the original bound census are mandatory.
  An adopted Run uses its existing PreparationBodyBorrow after Request aliases
  are dropped; the exact holder must still be live before and after currentness.
  Claiming cleanup custody is not retirement and does not forbid Run work.
- Ownership: The original bootstrap owns control storage. Child reservations,
  holdings, delegations and their physical cleanup duties remain unchanged.
- Synchronization: Currentness is called once. Exact identities, phase,
  retirement, stopping, closing, park, pending cleanup and monotonicity are
  checked again afterward. The final fence, byte admission and slot growth
  contain no external callback. One original scalar fences reentrant growth;
  entry rejects before constructing the variable operation payload. Deferred
  exit clears the fence on every typed result path. Retirement remains allowed
  during currentness and invalidates the final fence.
- Failure: Negative or overflowing slot geometry, shrinking demand, changed
  originals or insufficient backing refuse before publishing new maxima. A
  returned resize refusal leaves existing custody and usage intact. Allocation
  failure after a successful debit is not a rollback or refund guarantee.
- Cancellation: Retiring, closing, parked or imported-stopping owners refuse
  new growth, including zero-byte slot extensions. Growth cannot acknowledge
  cleanup, reopen an original or reset consumed serials and attempt history.
- Resources: The domain caller must price the full simultaneous control layout,
  including Map storage and old/new scalar backing during growth. This API does
  not derive that quote from caller numbers or treat a count as permission.
  Byte admission precedes slot reserve. Policy ceilings remain unchanged.
- Extension: A closed private operation discriminant reuses the existing body
  borrow's phase-reservation closure; no new closure or owner is added. The
  original capacity adds one growth-active scalar, priced in the Request's
  initial fixed control envelope. Fixed entry carriers, including one refused
  nested entry, fit the already-reserved private control group before growth;
  the new variable resize does not fund its own entry arguments.
  Constructor-only input borrows reject Run census growth. This is a Run-phase
  continuation of the existing preparation owner,
  separate from its pre-Run growth operation. Known demand may inform planning;
  this primitive does not require or manufacture a static Source row proof.
- Verification: running_preparation_inventory_wbtest.mbt covers exact/foreign
  originals, monotonicity, overflow, state refusal, retained failed prefixes,
  reentrant retirement/refused nested growth and imported stop with zero byte change. JS array
  reserve is a no-op, so these tests establish lifecycle behavior, not native
  allocator or domain coexistence quantities. Dynamic callers need their own
  constructor, cancellation and physical-provider tests.
