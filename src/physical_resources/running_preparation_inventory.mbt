///|
fn[I, P] running_preparation_inventory_matches(
  owner : PreparationCapacity[I, P],
  input : I,
  body : P,
  identity : OriginalLedgerIdentity,
  value : LedgerOriginalInventory,
) -> Bool {
  owner.phase == Run &&
  owner.active_phase_work is None &&
  (owner.input is Some(original) && physical_equal(original, input)) &&
  (owner.body is Some(original) && physical_equal(original, body)) &&
  physical_equal(identity.ledger, owner.ledger) &&
  physical_equal(identity.bootstrap, owner.reservation) &&
  physical_equal(value.identity, identity) &&
  physical_equal(value.bootstrap, owner.reservation) &&
  (
    owner.ledger.original_inventory is Some(current) &&
    physical_equal(current, value)
  ) &&
  (value.binding == PreparationBound || value.binding == PreparationBoundSpent) &&
  !value.closing &&
  // A zero-byte slot extension is still new work. Do not rely on resize's
  // positive-byte stopping check to fence cancellation of the parent.
  !(owner.ledger.imported_child is Some(parent) && parent.stopping) &&
  value.park is None &&
  !value.bootstrap.reservation.cleanup_pending
}

///|
/// Grow the SAME original Run's census before the next admitted constructor.
/// The domain owner supplies its complete typed coexistence quote; these byte
/// amounts are not permission or a prediction of unseen Source rows. Existing
/// tokens, serials, usage, policy ceilings and cleanup ownership remain intact.
pub fn[I, P] grow_running_preparation_capacity_inventory(
  owner : PreparationCapacity[I, P],
  input : I,
  body : P,
  identity : OriginalLedgerIdentity,
  retained_peak : Int64,
  execution_peak : Int64,
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
) -> Result[Unit, PreparationCapacityIssue] {
  match enter_preparation_inventory_growth(owner, body, None) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  defer leave_preparation_inventory_growth(owner)
  grow_running_preparation_capacity_inventory_owned(
    owner,
    input,
    body,
    identity,
    retained_peak,
    execution_peak,
    max_reservations,
    max_holdings,
    max_delegations,
    None,
  )
}

///|
fn[I, P] grow_running_preparation_capacity_inventory_owned(
  owner : PreparationCapacity[I, P],
  input : I,
  body : P,
  identity : OriginalLedgerIdentity,
  retained_peak : Int64,
  execution_peak : Int64,
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
  borrowed : PreparationCapacityBorrow[I, P]?,
) -> Result[Unit, PreparationCapacityIssue] {
  if !owner.inventory_growth_active {
    return Err(WorkActive)
  }
  if !running_preparation_borrow_matches(borrowed, owner, body) {
    return Err(BorrowReturned)
  }
  guard owner.ledger.original_inventory is Some(value) &&
    running_preparation_inventory_matches(owner, input, body, identity, value) else {
    return Err(ForeignOriginal)
  }
  if max_reservations < 0 ||
    max_holdings < 0 ||
    max_delegations < 0 ||
    max_holdings > 2147483647 - max_reservations ||
    max_delegations > 2147483647 - max_reservations - max_holdings {
    return Err(InvalidExtent)
  }
  let token = owner.reservation.reservation
  if retained_peak < token.retention ||
    execution_peak < token.execution ||
    max_reservations < value.max_reservations ||
    max_holdings < value.max_holdings ||
    max_delegations < value.max_delegations {
    return Err(InvalidExtent)
  }
  // Refresh the existing physical owner's currentness exactly once. A callback
  // may close, park, retire or grow this same original, so no prior comparison
  // remains a mutable-state proof after this call.
  match reservation_check(owner.ledger, token) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  if !owner.inventory_growth_active {
    return Err(WorkActive)
  }
  if !running_preparation_borrow_matches(borrowed, owner, body) {
    return Err(BorrowReturned)
  }
  guard running_preparation_inventory_matches(
    owner, input, body, identity, value,
  ) else {
    return Err(ForeignOriginal)
  }
  if retained_peak < token.retention ||
    execution_peak < token.execution ||
    max_reservations < value.max_reservations ||
    max_holdings < value.max_holdings ||
    max_delegations < value.max_delegations {
    return Err(InvalidExtent)
  }
  // No callback between this fence, backing mutation and array growth. A
  // refused byte grow does not publish slots or discard the retained prefix.
  match
    resize_capacity_reservation_current(
      owner.ledger,
      owner.reservation,
      retained_peak,
      execution_peak,
    ) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  value.reservations.reserve_capacity(max_reservations)
  value.holdings.reserve_capacity(max_holdings)
  value.delegations.reserve_capacity(max_delegations)
  value.max_reservations = max_reservations
  value.max_holdings = max_holdings
  value.max_delegations = max_delegations
  Ok(())
}

///|
fn[I, P] running_preparation_borrow_matches(
  borrowed : PreparationCapacityBorrow[I, P]?,
  owner : PreparationCapacity[I, P],
  body : P,
) -> Bool {
  match borrowed {
    None => true
    Some(value) =>
      !value.returned &&
      physical_equal(value.owner, owner) &&
      (value.body is Some(original) && physical_equal(original, body)) &&
      owner.borrowers > 0
  }
}

///|
/// The existing adopted Run holder retains its original capacity after Request
/// handoff clears its aliases. This borrows that custody; no new token or owner.
pub fn[P] grow_preparation_body_inventory(
  holder : PreparationBodyBorrow[P],
  body : P,
  identity : OriginalLedgerIdentity,
  retained_peak : Int64,
  execution_peak : Int64,
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
) -> Result[Unit, PreparationCapacityIssue] {
  match (holder.reserve_phase_original)(body, 0L, 0L, EnterRunningInventory) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  defer (holder.reserve_phase_original)(body, 0L, 0L, LeaveRunningInventory)
    |> ignore
  (holder.reserve_phase_original)(
    body,
    retained_peak,
    execution_peak,
    RunningInventory(identity, max_reservations, max_holdings, max_delegations),
  )
}

///|
fn[I, P] grow_original_preparation_body_inventory(
  borrowed : PreparationCapacityBorrow[I, P],
  body : P,
  identity : OriginalLedgerIdentity,
  retained_peak : Int64,
  execution_peak : Int64,
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
) -> Result[Unit, PreparationCapacityIssue] {
  guard borrowed.owner.input is Some(input) else { return Err(Retired) }
  grow_running_preparation_capacity_inventory_owned(
    borrowed.owner,
    input,
    body,
    identity,
    retained_peak,
    execution_peak,
    max_reservations,
    max_holdings,
    max_delegations,
    Some(borrowed),
  )
}

///|
/// Fixed entry carriers, already funded by the caller BEFORE invoking growth:
/// RunningInventory (identity + three counts + tag), the selected borrow Some,
/// and overlapping Result/error wrappers on refusal. One rejected reentrant
/// entry may overlap: its borrowed Some and refusal carriers are included;
/// it cannot invoke currentness or construct another RunningInventory payload.
/// Originals are borrowed. Count both outer/nested entry Some+Result pairs,
/// the running payload and owned-borrow Some, two refusal wrappers, exit Result
/// and caller Result (ten controls). Ten references and sixteen words cover
/// their original pointers/tags and the payload's three counts without sharing.
/// This is constructor DATA, not the variable census quote or an admission.
pub(all) struct PreparationInventoryGrowthConstruction {
  record_headers : Int64
  reference_slots : Int64
  scalar_words : Int64
} derive(Eq, Debug)

///|
let preparation_inventory_growth_entry : PreparationInventoryGrowthConstruction = {
  record_headers: 10L,
  reference_slots: 10L,
  scalar_words: 16L,
}

///|
pub fn preparation_inventory_growth_entry_construction() -> PreparationInventoryGrowthConstruction {
  preparation_inventory_growth_entry
}

///|
fn[I, P] enter_preparation_inventory_growth(
  owner : PreparationCapacity[I, P],
  body : P,
  borrowed : PreparationCapacityBorrow[I, P]?,
) -> Result[Unit, PreparationCapacityIssue] {
  if owner.inventory_growth_active {
    return Err(WorkActive)
  }
  if owner.phase != Run ||
    !(owner.body is Some(original) && physical_equal(original, body)) ||
    !running_preparation_borrow_matches(borrowed, owner, body) {
    return Err(ForeignOriginal)
  }
  owner.inventory_growth_active = true
  Ok(())
}

///|
fn[I, P] leave_preparation_inventory_growth(
  owner : PreparationCapacity[I, P],
) -> Unit {
  owner.inventory_growth_active = false
}
