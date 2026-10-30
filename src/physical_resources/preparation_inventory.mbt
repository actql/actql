///|
fn original_inventory_preparation_owned(
  value : LedgerOriginalInventory,
) -> Bool {
  match value.binding {
    PreparationUnbound
    | PreparationBound
    | PreparationFinishing
    | PreparationQuiescent
    | PreparationSettling => true
    StandaloneUnbound | StandaloneBound => false
  }
}

///|
fn[I, P] preparation_capacity_inventory_open(
  owner : PreparationCapacity[I, P],
) -> Bool {
  match owner.ledger.original_inventory {
    Some(value) if physical_equal(value.bootstrap, owner.reservation) &&
      original_inventory_preparation_owned(value) => !value.closing
    _ => true
  }
}

///|
/// Install the original census on the first preparation reservation, before
/// variable work or another token exists. The fixed caller must already fund
/// its controls, backing and initial slot bounds in this SAME capacity.
/// This creates neither another reservation nor a Model permission/Scope.
pub fn[I, P] begin_preparation_capacity_inventory(
  owner : PreparationCapacity[I, P],
  input : I,
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
) -> Result[OriginalLedgerIdentity, OriginalReadIssue] {
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOrigin)
  }
  if owner.phase != Working ||
    owner.body is Some(_) ||
    owner.borrowers != 0 ||
    owner.active_phase_work is Some(_) ||
    owner.last_work_phase != -1 ||
    owner.retirement_claimed {
    return Err(ChangedOriginalState)
  }
  begin_original_ledger_inventory_owned(
    owner.ledger,
    owner.reservation,
    max_reservations,
    max_holdings,
    max_delegations,
    PreparationUnbound,
  )
}

///|
/// The fixed domain grows its actual census and coexistence backing together,
/// before Run binding or descriptor/read issuance. Counts only increase;
/// existing tokens, vacant slots, serials and spent work remain unchanged.
/// Byte extents must come from that domain's full checked inventory. Resource
/// does not manufacture a tariff, infer demand or replace a physical recipe.
pub fn[I, P] grow_preparation_capacity_inventory(
  owner : PreparationCapacity[I, P],
  input : I,
  retained_peak : Int64,
  execution_peak : Int64,
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
) -> Result[Unit, PreparationCapacityIssue] {
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  guard owner.ledger.original_inventory is Some(value) &&
    physical_equal(value.bootstrap, owner.reservation) &&
    value.binding == PreparationUnbound &&
    !value.closing &&
    !value.descriptor_issued &&
    !value.read_claimed else {
    return Err(WorkActive)
  }
  if value.park is Some(_) {
    return Err(Resource(ResourceParked))
  }
  if max_reservations < value.max_reservations ||
    max_holdings < value.max_holdings ||
    max_delegations < value.max_delegations ||
    max_holdings > 2147483647 - max_reservations ||
    max_delegations > 2147483647 - max_reservations - max_holdings {
    return Err(InvalidExtent)
  }
  match
    reserve_working_preparation_phase(
      owner, input, retained_peak, execution_peak,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // Original current may synchronously close, bind or issue this inventory.
  // Debit growth remains charged on refusal; never publish stale new slots.
  guard owner.ledger.original_inventory is Some(current) &&
    physical_equal(value, current) &&
    value.binding == PreparationUnbound &&
    !value.closing &&
    !value.descriptor_issued &&
    !value.read_claimed &&
    value.park is None else {
    return Err(WorkActive)
  }
  value.max_reservations = max_reservations
  value.max_holdings = max_holdings
  value.max_delegations = max_delegations
  Ok(())
}

///|
fn preparation_inventory_children_closed(
  value : LedgerOriginalInventory,
) -> Bool {
  value.park is None &&
  !value.reservations.any(token => token.open) &&
  !value.holdings.any(token => token.live) &&
  !value.delegations.any(token => token.reservation.open)
}

///|
// Existing preparation retirement is the sole settlement owner. A bound
// Scope must first acknowledge its own physical cleanup; outstanding manager
// or operation borrows are separately checked by finish_preparation_retirement.
fn preparation_inventory_can_retire(value : LedgerOriginalInventory) -> Bool {
  preparation_inventory_children_closed(value) &&
  (value.binding == PreparationUnbound || value.binding == PreparationQuiescent)
}

///|
// Called only after the original current boundary while the preparation is
// Settling and the census allocation fence is closed. No external callback
// may occur while detaching the census and settling its bootstrap token.
fn settle_preparation_inventory_current(
  ledger : Ledger,
  reservation : CapacityReservation,
  value : LedgerOriginalInventory,
) -> Result[Unit, LedgerIssue] {
  guard ledger.original_inventory is Some(current) &&
    physical_equal(current, value) &&
    physical_equal(value.bootstrap, reservation) &&
    original_inventory_preparation_owned(value) &&
    value.closing &&
    value.binding == PreparationSettling &&
    preparation_inventory_children_closed(value) else {
    return Err(InvalidCharge)
  }
  match reservation_check_current(ledger, reservation.reservation) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  ledger.original_inventory = None
  match settle_reservation_current(ledger, reservation.reservation) {
    Err(issue) => {
      ledger.original_inventory = Some(value)
      Err(issue)
    }
    Ok(_) => {
      value.reservations.clear()
      value.reservations.shrink_to_fit()
      value.holdings.clear()
      value.holdings.shrink_to_fit()
      value.delegations.clear()
      value.delegations.shrink_to_fit()
      Ok(())
    }
  }
}
