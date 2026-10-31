///|
// The existing opaque census authenticates its own single captured child.
// This is a phase/lifetime prerequisite, not capture evidence or byte funding.
// Local still checks its exact Row capture against these nominal tokens.
pub fn original_ledger_captured_preparation_available(
  identity : OriginalLedgerIdentity,
  prefix? : Reservation? = None,
) -> Bool {
  guard original_ledger_preparation_available(identity) &&
    identity.ledger.original_inventory is Some(value) &&
    value.reservations.length() == (if prefix is Some(_) { 2 } else { 1 }) &&
    value.holdings.length() == 1 else {
    return false
  }
  match prefix {
    None =>
      original_captured_prefix_available(
        identity.ledger,
        value.reservations[0],
        value.holdings[0],
      )
    Some(token) =>
      original_captured_prefix_reservation_available(
        identity.ledger,
        value.reservations[0],
        value.holdings[0],
        token,
      )
  }
}

///|
// Closed Core Row receiver prerequisite for the NEXT physical keyed child.
// The Host supplies the count from its private accepted distinct-key cache,
// never a caller's row/usage aggregate. The exact assembly token and ordered
// original inventory prevent a second child from using the same opportunity.
// This does not reserve, reset a spent identity, or grant Source/Model I/O.
pub fn original_keyed_child_preparation_available(
  identity : OriginalLedgerIdentity,
  ledger : Ledger,
  assembly : Reservation,
  accepted_children : Int,
  prefix? : Reservation? = None,
) -> Bool {
  let assembly_index = if prefix is Some(_) { 2 } else { 1 }
  guard physical_equal(identity.ledger, ledger) &&
    original_ledger_preparation_available(identity) &&
    accepted_children >= 0 &&
    accepted_children <= 2147483646 - assembly_index &&
    ledger.original_inventory is Some(inventory) &&
    inventory.reservations.length() == accepted_children + assembly_index + 1 &&
    inventory.holdings.length() == accepted_children + 1 &&
    inventory.delegations.is_empty() &&
    ledger.next_capacity_serial == Some(-2) &&
    original_prefix_attempt_count_is(
      inventory,
      accepted_children + assembly_index + 1,
    ) &&
    physical_equal(inventory.reservations[assembly_index], assembly) &&
    physical_equal(assembly.owner, ledger) &&
    assembly.open &&
    !assembly.cleanup_pending &&
    !inventory.reservations[0].open &&
    inventory.holdings[0].reservation_serial == inventory.reservations[0].serial else {
    return false
  }
  if prefix is Some(token) &&
    (
      !physical_equal(inventory.reservations[1], token) ||
      !physical_equal(token.owner, ledger) ||
      !token.open ||
      token.cleanup_pending
    ) {
    return false
  }
  for index in 0..<inventory.holdings.length() {
    let token = inventory.holdings[index]
    if !holding_available(ledger, token) {
      return false
    }
  }
  for index in (assembly_index + 1)..<inventory.reservations.length() {
    if inventory.reservations[index].open ||
      inventory.holdings[index - assembly_index].reservation_serial !=
      inventory.reservations[index].serial {
      return false
    }
  }
  true
}

///|
// Cleanup fact only: closing/current refusal is NOT physical retirement.
// The original Direct holding has its own later cleanup; every downstream
// assembly/child token must really be retired before its prefix can settle.
pub fn original_keyed_prefix_dependents_retired(
  ledger : Ledger,
  prefix : Reservation,
) -> Bool {
  guard ledger.original_inventory is Some(inventory) &&
    inventory.reservations.length() >= 2 &&
    physical_equal(inventory.reservations[1], prefix) &&
    physical_equal(prefix.owner, ledger) else {
    return false
  }
  for index in 2..<inventory.reservations.length() {
    let token = inventory.reservations[index]
    // Pending is a live obligation only while open. A trusted successful
    // settle may leave the historical flag set on the closed token.
    if token.open {
      return false
    }
  }
  for index in 1..<inventory.holdings.length() {
    if inventory.holdings[index].live {
      return false
    }
  }
  true
}
