///|
/// Exact debit of this original working token, not available policy headroom
/// or a grant. Domain phase drivers preserve this already-live base before
/// adding their next independently owned construction envelope. No callback,
/// mutation, Ledger or reservation token escapes.
pub fn[I, P] preparation_capacity_working_extents(
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
  if !preparation_capacity_phase_is_working(owner.phase) ||
    owner.body is Some(_) ||
    owner.active_phase_work is Some(_) {
    return Err(WorkActive)
  }
  let token = owner.reservation.reservation
  Ok((token.retention, token.execution))
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
