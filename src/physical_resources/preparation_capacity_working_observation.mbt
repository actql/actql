///|
/// Exact existing reservation of an original working or completed body.
/// This observes no current callback and grants no capacity, borrower or Ledger.
pub fn[I, P] preparation_capacity_reserved_extents(
  owner : PreparationCapacity[I, P],
  input : I,
) -> Result[(Int64, Int64), PreparationCapacityIssue] {
  guard owner.input is Some(original) &&
    physical_equal(original, input) &&
    physical_equal(owner.ledger, owner.reservation.reservation.owner) else {
    return Err(ForeignOriginal)
  }
  if !owner.reservation.reservation.open || owner.phase == Closed {
    return Err(Retired)
  }
  if !(preparation_capacity_phase_is_working(owner.phase) ||
    owner.phase == Ready) ||
    preparation_capacity_has_executing_work(owner) {
    return Err(WorkActive)
  }
  let token = owner.reservation.reservation
  Ok((token.retention, token.execution))
}

///|
/// Exact debit of this original working token, not available policy headroom
/// or a grant. Domain phase drivers preserve this already-live base before
/// adding their next independently owned construction envelope. No callback,
/// mutation, Ledger or reservation token escapes.
pub fn[I, P] preparation_capacity_working_extents(
  owner : PreparationCapacity[I, P],
  input : I,
) -> Result[(Int64, Int64), PreparationCapacityIssue] {
  let observed = preparation_capacity_reserved_extents(owner, input)
  match observed {
    Err(_) => return observed
    Ok(_) => ()
  }
  if !preparation_capacity_phase_is_working(owner.phase) ||
    owner.body is Some(_) ||
    preparation_capacity_has_executing_work(owner) {
    return Err(WorkActive)
  }
  observed
}

///|
/// Original current/stopping fence for new constructor work, separate from
/// the read-only debit observation. Reuse the SAME reservation/current Owner
/// and its reentry latch; this issues no permission or capacity and performs
/// no no-op resize, accounting mutation, stop or cleanup acknowledgement.
pub fn[I, P] check_working_preparation_capacity_current(
  owner : PreparationCapacity[I, P],
  input : I,
) -> Result[Unit, PreparationCapacityIssue] {
  match preparation_capacity_working_extents(owner, input) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let working_phase = owner.phase
  owner.phase = Completing
  let result = match
    reservation_check(owner.ledger, owner.reservation.reservation) {
    Err(issue) => Err(issue)
    Ok(_) => check_imported_child_admission_current(owner.ledger)
  }
  owner.phase = working_phase
  match result {
    Err(issue) => Err(Resource(issue))
    Ok(_) =>
      // Same callback-free census fence as the public typed continuation.
      // Retirement may start during the one original current callback.
      if owner.ledger.original_inventory is Some(inventory) && inventory.closing {
        Err(Resource(ClosedReservation))
      } else {
        Ok(())
      }
  }
}

///|
/// Same original working reservation accounting, without completing a fake
/// body or acquiring a borrow. This never supplies a physical cleanup proof.
pub fn[I, P] preparation_capacity_working_usage_isolated(
  owner : PreparationCapacity[I, P],
  input : I,
  ledger : Ledger,
) -> Bool {
  preparation_capacity_working_extents(owner, input) is Ok(_) &&
  preparation_capacity_usage_isolated(owner, ledger)
}
