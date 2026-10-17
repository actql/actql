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
