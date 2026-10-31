///|
fn original_inventory_preparation_owned(
  value : LedgerOriginalInventory,
) -> Bool {
  match value.binding {
    PreparationUnbound
    | PreparationBound
    | PreparationFinishing
    | PreparationQuiescent
    | PreparationSettling
    | PreparationUnboundSpent
    | PreparationBoundSpent => true
    StandaloneUnbound | StandaloneBound => false
  }
}

///|
fn original_inventory_preparation_unbound(
  value : LedgerOriginalInventory,
) -> Bool {
  value.binding == PreparationUnbound ||
  value.binding == PreparationUnboundSpent
}

///|
// One scalar provenance fence, not a second usage ledger or refundable budget.
// Only begin_preparation_io can classify its original pre-binding input token.
fn record_original_non_preparation_token(
  value : LedgerOriginalInventory,
) -> Unit {
  value.binding = match value.binding {
    PreparationUnbound => PreparationUnboundSpent
    PreparationBound => PreparationBoundSpent
    original => original
  }
}

///|
fn record_original_prefix_work(ledger : Ledger, work : Int) -> Unit {
  if work > 0 &&
    ledger.original_inventory is Some(value) &&
    value.binding == PreparationBound {
    value.binding = PreparationBoundSpent
  }
}

///|
// Exact absolute issuance history remains on the Ledger. Captured/keyed
// consumers count their own children from the same original Run cut, after
// preparation-input attempts. No settled or foreign token can refill it.
fn original_prefix_attempt_count_is(
  value : LedgerOriginalInventory,
  count : Int,
) -> Bool {
  let base = if original_inventory_preparation_owned(value) {
    value.preparation_attempt_base
  } else {
    0
  }
  count >= 0 &&
  base >= 0 &&
  count <= 2147483647 - base &&
  value.identity.ledger.next_attempt_serial == Some(base + count)
}

///|
// One closed-input predicate for first-prefix use and one-time quantity
// installation. It observes actual custody, never an input-reported aggregate.
// Spent byte/work/attempt history remains on this SAME preparation Ledger.
fn original_preparation_input_closed(value : LedgerOriginalInventory) -> Bool {
  let ledger = value.identity.ledger
  let usage = ledger.usage
  !value.closing &&
  value.park is None &&
  !value.descriptor_issued &&
  !value.read_claimed &&
  value.reservations.is_empty() &&
  value.holdings.is_empty() &&
  value.delegations.is_empty() &&
  capacity_reservation_open(value.bootstrap) &&
  usage.reserved_attempts == 0 &&
  usage.holdings == 0 &&
  usage.live_reservations == 1 &&
  usage.live_delegations == 0 &&
  usage.uncertain_transfer_bytes == 0L &&
  usage.reserved_transfer_bytes == 0L &&
  usage.held_bytes == 0L &&
  usage.reserved_retention_bytes == value.bootstrap.reservation.retention &&
  usage.reserved_execution_bytes == value.bootstrap.reservation.execution &&
  ledger.delegated_planning == 0 &&
  ledger.delegated_attempts == 0 &&
  ledger.delegated_holdings == 0 &&
  ledger.quantity_usage ==
  {
    reserved: zero_quantities(),
    uncertain: zero_quantities(),
    consumed: zero_quantities(),
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
    original_inventory_preparation_unbound(value) &&
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
    original_inventory_preparation_unbound(value) &&
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
  (
    original_inventory_preparation_unbound(value) ||
    value.binding == PreparationQuiescent
  )
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
