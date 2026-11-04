///|
// Whole key-set barrier, not permission to read another Source or send a Model.
// Source/Compute prefix/assembly/child identities and all actual holdings must
// remain present. The assembly's last holding follows the unique child holdings.
pub fn original_keyed_serialization_preparation_available(
  identity : OriginalLedgerIdentity,
  ledger : Ledger,
  prefix : Reservation,
  assembly : Reservation,
  children : Int,
) -> Bool {
  guard physical_equal(identity.ledger, ledger) &&
    original_ledger_preparation_available(identity) &&
    children >= 0 &&
    children <= 2147483644 &&
    ledger.original_inventory is Some(inventory) &&
    inventory.reservations.length() == children + 3 &&
    inventory.holdings.length() == children + 2 &&
    inventory.delegations.is_empty() &&
    ledger.next_capacity_serial == Some(-2) &&
    original_prefix_attempt_count_is(inventory, children + 3) &&
    !inventory.reservations[0].open &&
    inventory.holdings[0].reservation_serial == inventory.reservations[0].serial &&
    physical_equal(inventory.reservations[1], prefix) &&
    physical_equal(prefix.owner, ledger) &&
    prefix.open &&
    !prefix.cleanup_pending &&
    physical_equal(inventory.reservations[2], assembly) &&
    physical_equal(assembly.owner, ledger) &&
    !assembly.open &&
    inventory.holdings[children + 1].reservation_serial == assembly.serial else {
    return false
  }
  for index in 0..<inventory.holdings.length() {
    let token = inventory.holdings[index]
    if !holding_available(ledger, token) {
      return false
    }
  }
  for index in 0..<children {
    let token = inventory.reservations[index + 3]
    if token.open ||
      inventory.holdings[index + 1].reservation_serial != token.serial {
      return false
    }
  }
  true
}

///|
// A physical downstream reservation remains a borrow, even when the Scope
// rejects new use. Do not release the assembly behind its active/failed child.
pub fn original_keyed_lookup_dependents_retired(
  ledger : Ledger,
  assembly : Reservation,
) -> Bool {
  guard ledger.original_inventory is Some(inventory) &&
    inventory.reservations.length() >= 3 &&
    physical_equal(inventory.reservations[2], assembly) &&
    physical_equal(assembly.owner, ledger) else {
    return false
  }
  for index in 3..<inventory.reservations.length() {
    let token = inventory.reservations[index]
    // settle_reservation closes the token after trusted cleanup ACK; its
    // historical cleanup_pending field need not be reset by that operation.
    if token.open {
      return false
    }
  }
  true
}

///|
// Whole-set barrier for exact plural originals. Assembly output follows all
// distinct child holdings; original sources must already be physically settled.
pub fn original_keyed_inputs_serialization_preparation_available(
  identity : OriginalLedgerIdentity,
  ledger : Ledger,
  originals : Array[(Reservation, Holding)],
  prefix : Reservation,
  assembly : Reservation,
  children : Int,
) -> Bool {
  let count = originals.length()
  guard count <= 2147483645 &&
    children >= 0 &&
    children <= 2147483645 - count &&
    physical_equal(identity.ledger, ledger) &&
    original_ledger_preparation_available(identity) &&
    original_captured_inputs_live(ledger, originals, true) &&
    ledger.original_inventory is Some(inventory) &&
    inventory.reservations.length() == children + count + 2 &&
    inventory.holdings.length() == children + count + 1 &&
    inventory.delegations.is_empty() &&
    ledger.next_capacity_serial == Some(-2) &&
    original_prefix_attempt_count_is(inventory, children + count + 2) &&
    physical_equal(inventory.reservations[count], prefix) &&
    physical_equal(prefix.owner, ledger) &&
    prefix.open &&
    !prefix.cleanup_pending &&
    physical_equal(inventory.reservations[count + 1], assembly) &&
    physical_equal(assembly.owner, ledger) &&
    !assembly.open &&
    inventory.holdings[children + count].reservation_serial == assembly.serial else {
    return false
  }
  for index in count..<inventory.holdings.length() {
    if !holding_available(ledger, inventory.holdings[index]) {
      return false
    }
  }
  for index in 0..<children {
    let reservation = inventory.reservations[index + count + 2]
    if !physical_equal(reservation.owner, ledger) ||
      reservation.open ||
      inventory.holdings[index + count].reservation_serial != reservation.serial {
      return false
    }
  }
  true
}

///|
// Cleanup does not require a usable phase. Exact original custody and the
// assembly position are still required; a pending downstream token stays live.
pub fn original_keyed_inputs_lookup_dependents_retired(
  ledger : Ledger,
  originals : Array[(Reservation, Holding)],
  assembly : Reservation,
  prefix? : Reservation? = None,
) -> Bool {
  guard original_captured_inputs_cleanup_match(ledger, originals)
    is Some(serial) &&
    ledger.original_inventory is Some(inventory) else {
    return false
  }
  let assembly_serial = match prefix {
    None => serial
    Some(token) => {
      if serial == 2147483647 ||
        !original_cleanup_reservation_matches(ledger, token, serial) {
        return false
      }
      serial + 1
    }
  }
  if !original_cleanup_reservation_matches(ledger, assembly, assembly_serial) {
    return false
  }
  // Per-key settled holdings still belong to the existing assembly cleanup;
  // downstream open reservations, including pending failures, block it.
  !inventory.reservations.any(token => {
    token.serial > assembly_serial && token.open
  })
}
