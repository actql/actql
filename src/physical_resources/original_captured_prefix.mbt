///|
// Core preparation phase only, not a byte grant, stable cut or send authority.
// Captured children are allowed, but an issued descriptor/read cannot acquire
// another prefix behind the original immutable snapshot.
pub fn original_ledger_preparation_available(
  identity : OriginalLedgerIdentity,
) -> Bool {
  guard original_ledger_inventory_available(identity) &&
    identity.ledger.original_inventory is Some(value) else {
    return false
  }
  !value.descriptor_issued && !value.read_claimed
}

///|
// Only the accounted Row capture Owner supplies these exact opaque tokens.
// The completed Direct capture must be the single recorded child/holding.
// A selected provider can still own live scratch/cleanup backing; borrowing
// it never settles that reservation. Pending cleanup refuses new use. After
// the prefix reserves its attempt, even successful cleanup cannot restore this
// prerequisite. Capacity failure leaves the same original capture retryable.
pub fn original_captured_prefix_available(
  ledger : Ledger,
  reservation : Reservation,
  holding : Holding,
) -> Bool {
  guard ledger.original_inventory is Some(value) &&
    original_ledger_preparation_available(value.identity) else {
    return false
  }
  value.reservations.length() == 1 &&
  physical_equal(value.reservations[0], reservation) &&
  physical_equal(reservation.owner, ledger) &&
  !reservation_pending(reservation) &&
  value.holdings.length() == 1 &&
  physical_equal(value.holdings[0], holding) &&
  holding_available(ledger, holding) &&
  holding.reservation_serial == reservation.serial &&
  value.delegations.is_empty() &&
  ledger.next_capacity_serial == Some(-2) &&
  original_prefix_attempt_count_is(value, 1)
}

///|
// The same original capture and its still-live checked Compute reservation.
// Exact tokens, not counts alone, permit the closed Core receiver to borrow.
pub fn original_captured_prefix_reservation_available(
  ledger : Ledger,
  reservation : Reservation,
  holding : Holding,
  prefix : Reservation,
) -> Bool {
  guard ledger.original_inventory is Some(value) &&
    original_ledger_preparation_available(value.identity) else {
    return false
  }
  value.reservations.length() == 2 &&
  physical_equal(value.reservations[0], reservation) &&
  physical_equal(reservation.owner, ledger) &&
  !reservation_pending(reservation) &&
  value.holdings.length() == 1 &&
  physical_equal(value.holdings[0], holding) &&
  holding_available(ledger, holding) &&
  holding.reservation_serial == reservation.serial &&
  physical_equal(value.reservations[1], prefix) &&
  physical_equal(prefix.owner, ledger) &&
  prefix.open &&
  !prefix.cleanup_pending &&
  value.delegations.is_empty() &&
  ledger.next_capacity_serial == Some(-2) &&
  original_prefix_attempt_count_is(value, 2)
}
