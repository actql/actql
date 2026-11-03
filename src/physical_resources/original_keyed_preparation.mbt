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

///|
// The owner supplies its exact originals, never a count-based census exemption.
pub fn original_ledger_captured_inputs_preparation_available(
  identity : OriginalLedgerIdentity,
  originals : Array[(Reservation, Holding)],
  prefix? : Reservation? = None,
) -> Bool {
  guard original_ledger_preparation_available(identity) else { return false }
  match prefix {
    None =>
      original_captured_inputs_prefix_available(identity.ledger, originals)
    Some(token) =>
      original_captured_inputs_prefix_reservation_available(
        identity.ledger,
        originals,
        token,
      )
  }
}

///|
// Same single-input keyed contract, with each exact settled original occupying
// its ordered slot. This grants no Source/Model I/O and creates no resource.
pub fn original_keyed_inputs_child_preparation_available(
  identity : OriginalLedgerIdentity,
  ledger : Ledger,
  originals : Array[(Reservation, Holding)],
  assembly : Reservation,
  accepted_children : Int,
  prefix? : Reservation? = None,
) -> Bool {
  guard originals.length() <= 2147483645 else { return false }
  let count = originals.length()
  let assembly_index = count + (if prefix is Some(_) { 1 } else { 0 })
  guard physical_equal(identity.ledger, ledger) &&
    original_ledger_preparation_available(identity) &&
    original_captured_inputs_live(ledger, originals, true) &&
    accepted_children >= 0 &&
    accepted_children <= 2147483646 - assembly_index &&
    ledger.original_inventory is Some(inventory) &&
    inventory.reservations.length() == accepted_children + assembly_index + 1 &&
    inventory.holdings.length() == accepted_children + count &&
    inventory.delegations.is_empty() &&
    ledger.next_capacity_serial == Some(-2) &&
    original_prefix_attempt_count_is(
      inventory,
      accepted_children + assembly_index + 1,
    ) &&
    physical_equal(inventory.reservations[assembly_index], assembly) &&
    physical_equal(assembly.owner, ledger) &&
    assembly.open &&
    !assembly.cleanup_pending else {
    return false
  }
  if prefix is Some(token) &&
    (
      !physical_equal(inventory.reservations[count], token) ||
      !physical_equal(token.owner, ledger) ||
      !token.open ||
      token.cleanup_pending
    ) {
    return false
  }
  for index in 0..<accepted_children {
    let reservation = inventory.reservations[assembly_index + 1 + index]
    let holding = inventory.holdings[count + index]
    if !physical_equal(reservation.owner, ledger) ||
      reservation.open ||
      !holding_available(ledger, holding) ||
      holding.reservation_serial != reservation.serial {
      return false
    }
  }
  true
}

///|
// Original captures remain borrowed until the prefix itself is acknowledged.
// This only reports retirement of its dependents, even if the prefix is pending.
pub fn original_keyed_inputs_prefix_dependents_retired(
  ledger : Ledger,
  originals : Array[(Reservation, Holding)],
  prefix : Reservation,
) -> Bool {
  guard original_captured_inputs_cleanup_match(ledger, originals)
    is Some(serial) &&
    original_cleanup_reservation_matches(ledger, prefix, serial) &&
    ledger.original_inventory is Some(inventory) else {
    return false
  }
  !inventory.reservations.any(token => token.serial > serial && token.open) &&
  !inventory.holdings.any(token => {
    token.reservation_serial >= serial && token.live
  })
}
