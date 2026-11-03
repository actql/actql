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

///|
// Borrow exact caller-held originals in census order. This neither reconstructs
// the census nor turns a count or an equal-state token into capture authority.
// Cleanup uses identity only because refusal/closing is not physical retirement.
fn original_captured_inputs_match(
  ledger : Ledger,
  originals : Array[(Reservation, Holding)],
) -> Bool {
  guard ledger.original_inventory is Some(value) &&
    !originals.is_empty() &&
    value.reservations.length() >= originals.length() &&
    value.holdings.length() >= originals.length() else {
    return false
  }
  for index in 0..<originals.length() {
    let (reservation, holding) = originals[index]
    if !physical_equal(value.reservations[index], reservation) ||
      !physical_equal(value.holdings[index], holding) ||
      !physical_equal(reservation.owner, ledger) ||
      !physical_equal(holding.owner, ledger) ||
      holding.reservation_serial != reservation.serial {
      return false
    }
    // Issuance serials are strictly ordered, so duplicate pairs cannot pass.
    if index > 0 &&
      (
        originals[index - 1].0.serial >= reservation.serial ||
        originals[index - 1].1.serial >= holding.serial
      ) {
      return false
    }
  }
  true
}

///|
fn original_captured_inputs_live(
  ledger : Ledger,
  originals : Array[(Reservation, Holding)],
  settled : Bool,
) -> Bool {
  guard original_captured_inputs_match(ledger, originals) else { return false }
  for pair in originals {
    let (reservation, holding) = pair
    if !holding_available(ledger, holding) ||
      reservation_pending(reservation) ||
      (settled && reservation.open) {
      return false
    }
  }
  true
}

///|
// Exact ordered captured inputs only; live nonpending Source backing may still
// exist. A spent prefix opportunity is never restored by downstream cleanup.
pub fn original_captured_inputs_prefix_available(
  ledger : Ledger,
  originals : Array[(Reservation, Holding)],
) -> Bool {
  guard ledger.original_inventory is Some(value) &&
    original_ledger_preparation_available(value.identity) &&
    original_captured_inputs_live(ledger, originals, false) else {
    return false
  }
  value.reservations.length() == originals.length() &&
  value.holdings.length() == originals.length() &&
  value.delegations.is_empty() &&
  ledger.next_capacity_serial == Some(-2) &&
  original_prefix_attempt_count_is(value, originals.length())
}

///|
pub fn original_captured_inputs_prefix_reservation_available(
  ledger : Ledger,
  originals : Array[(Reservation, Holding)],
  prefix : Reservation,
) -> Bool {
  guard ledger.original_inventory is Some(value) &&
    original_ledger_preparation_available(value.identity) &&
    originals.length() < 2147483647 &&
    original_captured_inputs_live(ledger, originals, false) else {
    return false
  }
  value.reservations.length() == originals.length() + 1 &&
  value.holdings.length() == originals.length() &&
  physical_equal(value.reservations[originals.length()], prefix) &&
  physical_equal(prefix.owner, ledger) &&
  prefix.open &&
  !prefix.cleanup_pending &&
  value.delegations.is_empty() &&
  ledger.next_capacity_serial == Some(-2) &&
  original_prefix_attempt_count_is(value, originals.length() + 1)
}
