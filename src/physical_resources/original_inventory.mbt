///|
// Finite private custody on the existing Ledger, not another registry owner.
// The bootstrap pays for all backing/control/snapshots for the original Run.
// Bounds alone do not establish those byte coefficients or public adoption.
priv struct LedgerOriginalInventory {
  identity : OriginalLedgerIdentity
  bootstrap : CapacityReservation
  max_reservations : Int
  max_holdings : Int
  max_delegations : Int
  reservations : OriginalTokenSlots[Reservation]
  holdings : OriginalTokenSlots[Holding]
  delegations : OriginalTokenSlots[ExecutionDelegation]
  // One checked Run binding may be installed after preparation, before reads.
  mut run_binding_claimed : Bool
  mut descriptor_issued : Bool
  mut read_claimed : Bool
  mut closing : Bool
  // Resident even when None. The original bootstrap/installed envelope must
  // fund this reference and any live park controls before registration/use.
  mut park : OriginalResourceParkFence?
}

///|
// A private-constructor identity for the census installed before any child.
// The checked Run owner binds this token to its original Run and Host.
struct OriginalLedgerIdentity {
  ledger : Ledger
  bootstrap : CapacityReservation
}

///|
// Register before the first ordinary resource token, including zero bytes.
// A spent/settled token cannot be erased by installing a census afterwards.
pub fn begin_original_ledger_inventory(
  ledger : Ledger,
  bootstrap : CapacityReservation,
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
) -> Result[OriginalLedgerIdentity, OriginalReadIssue] {
  if ledger.original_inventory is Some(_) ||
    !original_read_bootstrap_available(ledger, bootstrap) ||
    bootstrap.reservation.serial != -1 ||
    ledger.next_capacity_serial != Some(-2) {
    return Err(InvalidBootstrap)
  }
  if ledger.next_attempt_serial != Some(0) ||
    ledger.next_holding_serial != Some(0) ||
    !original_ledger_has_only_bootstrap(ledger, bootstrap) {
    return Err(ChangedOriginalState)
  }
  if max_reservations < 0 ||
    max_holdings < 0 ||
    max_delegations < 0 ||
    max_holdings > 2147483647 - max_reservations ||
    max_delegations > 2147483647 - max_reservations - max_holdings {
    return Err(IncompleteInventory)
  }
  let identity : OriginalLedgerIdentity = { ledger, bootstrap, }
  ledger.original_inventory = Some({
    identity,
    bootstrap,
    max_reservations,
    max_holdings,
    max_delegations,
    reservations: original_token_slots(),
    holdings: original_token_slots(),
    delegations: original_token_slots(),
    run_binding_claimed: false,
    descriptor_issued: false,
    read_claimed: false,
    closing: false,
    park: None,
  })
  Ok(identity)
}

///|
fn original_ledger_has_only_bootstrap(
  ledger : Ledger,
  bootstrap : CapacityReservation,
) -> Bool {
  original_ledger_has_no_child_usage(
    ledger,
    bootstrap.reservation.retention,
    bootstrap.reservation.execution,
    live_reservations=1,
  )
}

///|
fn original_ledger_has_no_child_usage(
  ledger : Ledger,
  retained_bytes : Int64,
  execution_bytes : Int64,
  live_reservations? : Int = 0,
) -> Bool {
  let usage = ledger.usage
  !(usage.planning_work != 0 ||
  usage.attempts != 0 ||
  usage.reserved_attempts != 0 ||
  usage.holdings != 0 ||
  usage.live_reservations != live_reservations ||
  usage.live_delegations != 0 ||
  usage.transferred_bytes != 0L ||
  usage.uncertain_transfer_bytes != 0L ||
  usage.reserved_transfer_bytes != 0L ||
  usage.held_bytes != 0L ||
  usage.reserved_retention_bytes != retained_bytes ||
  usage.reserved_execution_bytes != execution_bytes ||
  usage.peak_retention_bytes != retained_bytes ||
  ledger.delegated_planning != 0 ||
  ledger.delegated_attempts != 0 ||
  ledger.delegated_holdings != 0 ||
  ledger.quantity_usage !=
  {
    reserved: zero_quantities(),
    uncertain: zero_quantities(),
    consumed: zero_quantities(),
  })
}

///|
fn check_original_inventory_open(
  value : LedgerOriginalInventory,
) -> Result[Unit, LedgerIssue] {
  if value.park is Some(_) {
    Err(ResourceParked)
  } else if value.closing || !capacity_reservation_open(value.bootstrap) {
    Err(ClosedReservation)
  } else {
    Ok(())
  }
}

///|
// Read-only lifetime guard on the same opaque census/bootstrap. Issued read
// state is allowed; closing/reclaimed custody is not. This neither freezes a
// Ledger nor establishes a stable cut, byte adequacy or restoration authority.
pub fn original_ledger_inventory_available(
  identity : OriginalLedgerIdentity,
) -> Bool {
  guard identity.ledger.original_inventory is Some(value) else { return false }
  physical_equal(identity, value.identity) &&
  physical_equal(identity.bootstrap, value.bootstrap) &&
  !value.closing &&
  value.park is None &&
  original_read_bootstrap_available(identity.ledger, identity.bootstrap)
}

///|
// Bind the original checked Run to a census installed before preparation.
// Existing child identities and consumed work remain recorded. This claims
// only the existing binding slot; it does not issue a descriptor or Model
// permission, rebuild a census, or create another resource owner. The initial
// bootstrap must fund this scalar word before the census is constructed.
pub fn claim_original_ledger_run_binding(
  identity : OriginalLedgerIdentity,
  ledger : Ledger,
) -> Result[Unit, OriginalReadIssue] {
  if !physical_equal(identity.ledger, ledger) {
    return Err(ForeignOrigin)
  }
  guard original_ledger_inventory_available(identity) &&
    ledger.original_inventory is Some(value) else {
    return Err(InvalidBootstrap)
  }
  if value.run_binding_claimed || value.descriptor_issued || value.read_claimed {
    return Err(SpentClaim)
  }
  value.run_binding_claimed = true
  Ok(())
}

///|
// Read-only lifetime of the same original census/bootstrap. A parked Run may
// retain its existing borrow while allocation and mutation remain fenced.
// This neither unparks resources nor admits a read, Model start or send.
pub fn original_ledger_inventory_live(
  identity : OriginalLedgerIdentity,
) -> Bool {
  guard identity.ledger.original_inventory is Some(value) else { return false }
  physical_equal(identity, value.identity) &&
  physical_equal(identity.bootstrap, value.bootstrap) &&
  !value.closing &&
  original_read_bootstrap_available(identity.ledger, identity.bootstrap)
}

///|
// Core-only prerequisite for the checked source-free prefix constructor.
// Unlike the ordinary lifetime getter, this rejects descriptor/read issuance
// and every spent child identity, including a zero-byte or settled attempt.
// It neither lends a Ledger to JS nor grants Model send/restore authority.
pub fn original_ledger_prefix_available(
  identity : OriginalLedgerIdentity,
) -> Bool {
  guard original_ledger_inventory_available(identity) &&
    identity.ledger.original_inventory is Some(value) else {
    return false
  }
  !value.descriptor_issued &&
  !value.read_claimed &&
  value.reservations.is_empty() &&
  value.holdings.is_empty() &&
  value.delegations.is_empty() &&
  identity.ledger.next_capacity_serial == Some(-2) &&
  identity.ledger.next_attempt_serial == Some(0) &&
  identity.ledger.next_holding_serial == Some(0) &&
  original_ledger_has_only_bootstrap(identity.ledger, identity.bootstrap)
}

///|
fn check_original_reservation_slot(
  ledger : Ledger,
) -> Result[Unit, LedgerIssue] {
  match check_imported_child_admission(ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  check_original_reservation_slot_current(ledger)
}

///|
// No callbacks after the caller's final current observation. A synchronous
// observation may reenter this Ledger and alter its live inventory/quotas.
fn check_original_reservation_slot_current(
  ledger : Ledger,
) -> Result[Unit, LedgerIssue] {
  guard ledger.original_inventory is Some(value) else { return Ok(()) }
  match check_original_inventory_open(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if value.reservations.length() >= value.max_reservations {
    Err(RetentionLimit)
  } else {
    Ok(())
  }
}

///|
fn check_original_holding_slot(ledger : Ledger) -> Result[Unit, LedgerIssue] {
  guard ledger.original_inventory is Some(value) else { return Ok(()) }
  match check_original_inventory_open(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if value.holdings.length() >= value.max_holdings {
    Err(RetentionLimit)
  } else {
    Ok(())
  }
}

///|
fn check_original_delegation_slot(ledger : Ledger) -> Result[Unit, LedgerIssue] {
  match check_imported_child_admission(ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard ledger.original_inventory is Some(value) else { return Ok(()) }
  match check_original_inventory_open(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if value.delegations.length() >= value.max_delegations {
    Err(RetentionLimit)
  } else {
    Ok(())
  }
}

///|
fn record_original_reservation(ledger : Ledger, value : Reservation) -> Unit {
  if ledger.original_inventory is Some(inventory) {
    inventory.reservations.push(value)
  }
}

///|
fn record_original_holding(ledger : Ledger, value : Holding) -> Unit {
  if ledger.original_inventory is Some(inventory) {
    inventory.holdings.push(value)
  }
}

///|
fn record_original_delegation(
  ledger : Ledger,
  value : ExecutionDelegation,
) -> Unit {
  if ledger.original_inventory is Some(inventory) {
    inventory.delegations.push(value)
  }
}

///|
fn retire_original_reservation(ledger : Ledger, value : Reservation) -> Unit {
  if ledger.original_inventory is Some(inventory) {
    // A retained output still requires the original closed reservation binding.
    // This is live custody, unlike an expired identity retained only as history.
    if inventory.holdings.any(holding => {
        holding.live && holding.reservation_serial == value.serial
      }) {
      return
    }
    for index in 0..<inventory.reservations.length() {
      if physical_equal(inventory.reservations[index], value) {
        inventory.reservations.remove(index) |> ignore
        break
      }
    }
  }
}

///|
fn retire_original_holding(ledger : Ledger, value : Holding) -> Unit {
  if ledger.original_inventory is Some(inventory) {
    for index in 0..<inventory.holdings.length() {
      if physical_equal(inventory.holdings[index], value) {
        inventory.holdings.remove(index) |> ignore
        break
      }
    }
    for index in 0..<inventory.reservations.length() {
      let reservation = inventory.reservations[index]
      if reservation.serial == value.reservation_serial && !reservation.open {
        retire_original_reservation(ledger, reservation)
        break
      }
    }
  }
}

///|
fn retire_original_delegation(
  ledger : Ledger,
  value : ExecutionDelegation,
) -> Unit {
  if ledger.original_inventory is Some(inventory) {
    for index in 0..<inventory.delegations.length() {
      if physical_equal(inventory.delegations[index], value) {
        inventory.delegations.remove(index) |> ignore
        break
      }
    }
  }
}

///|
pub fn[T] issue_recorded_original_ledger_descriptor(
  identity : OriginalLedgerIdentity,
  origin : T,
) -> Result[OriginalLedgerDescriptor[T], OriginalReadIssue] {
  let ledger = identity.ledger
  let bootstrap = identity.bootstrap
  guard ledger.original_inventory is Some(value) &&
    physical_equal(identity, value.identity) &&
    !value.closing else {
    return Err(IncompleteInventory)
  }
  if value.park is Some(_) {
    return Err(Resource(ResourceParked))
  }
  if value.descriptor_issued {
    return Err(SpentClaim)
  }
  let descriptor = match
    issue_original_ledger_descriptor_from_slots(
      ledger,
      origin,
      bootstrap,
      value.reservations,
      value.holdings,
      value.delegations,
      value.max_reservations + value.max_holdings + value.max_delegations,
    ) {
    Ok(descriptor) => descriptor
    Err(issue) => return Err(issue)
  }
  value.descriptor_issued = true
  Ok(descriptor)
}

///|
// The same Run's final owning cleanup performs this after child cleanup. A
// read child cannot return census/bootstrap capacity while another child or
// original allocation is still alive. Unknown quantities are never zeroed.
pub fn finish_original_ledger_inventory(
  ledger : Ledger,
  physical_cleanup_complete : Bool,
) -> Result[Bool, OriginalReadIssue] {
  guard ledger.original_inventory is Some(value) else { return Err(SpentClaim) }
  if value.park is Some(_) {
    return Err(Resource(ResourceParked))
  }
  value.closing = true
  if !physical_cleanup_complete ||
    value.reservations.any(token => token.open) ||
    value.holdings.any(token => token.live) ||
    value.delegations.any(token => token.reservation.open) {
    return Ok(false)
  }
  match reservation_check(ledger, value.bootstrap.reservation) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  value.reservations.clear()
  value.reservations.shrink_to_fit()
  value.holdings.clear()
  value.holdings.shrink_to_fit()
  value.delegations.clear()
  value.delegations.shrink_to_fit()
  ledger.original_inventory = None
  settle_capacity(ledger, value.bootstrap)
  .map(_ => true)
  .map_err(issue => Resource(issue))
}
