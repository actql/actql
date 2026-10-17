///|
/// Read the original capacity/Run Ledger correspondence without exposing the
/// inner reservation or changing capacity. Equal limits and free bytes on a
/// different Ledger do not substitute. This is not allocation or a read grant.
pub fn shared_capacity_matches_ledger(
  capacity : SharedCapacity,
  ledger : Ledger,
) -> Bool {
  physical_equal(capacity.ledger, ledger) &&
  physical_equal(capacity.reservation.owner, ledger) &&
  !capacity.closing &&
  reservation_open(capacity.reservation)
}

///|
/// Observe the original outstanding borrower without changing it or invoking
/// Host callbacks. This is neither phase assignment nor a new read grant;
/// the private supplier must bind that exact original occurrence separately.
pub fn shared_borrow_matches_ledger(
  borrow : SharedBorrow,
  ledger : Ledger,
) -> Bool {
  let allocation = borrow.allocation
  !borrow.returned &&
  !allocation.retiring &&
  !allocation.released &&
  shared_capacity_matches_ledger(allocation.owner, ledger)
}
