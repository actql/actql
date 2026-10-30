///|
/// One physical operation on the SAME preparation Ledger. Its original
/// constructor borrow keeps that parent's reservation alive through cleanup.
/// This is no new Ledger, byte allowance, authority or physical-stop witness.
struct PreparationIo {
  reservation : Reservation
  parent : PreparationBodyBorrow[Unit]
  mut retired : Bool
}

///|
/// The fixed native owner calls immediately before the selected operation.
/// Its variable Buffer/decoder peak must already be reserved on this original
/// preparation; transfer_bytes bounds this operation's possible transfer only.
/// Claim the original borrower before the one current callback so a reentrant
/// retirement cannot release the preparation while physical work is admitted.
pub fn[I, P] begin_preparation_io(
  owner : PreparationCapacity[I, P],
  input : I,
  transfer_bytes : Int64,
) -> Result[PreparationIo, PreparationCapacityIssue] {
  if transfer_bytes < 0L {
    return Err(InvalidExtent)
  }
  match preparation_capacity_working_extents(owner, input) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match reserve_preparation_borrow_slot(owner, true) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let working_phase = owner.phase
  owner.phase = Completing
  let admitted = reserve_attempt(owner.ledger, transfer_bytes, 0L, 0L)
  owner.phase = working_phase
  let reservation = match admitted {
    Err(issue) => {
      owner.borrowers -= 1
      return Err(Resource(issue))
    }
    Ok(value) => value
  }
  // The reserve just checked current and the original census. No external
  // callback belongs between this debit and the same fixed physical start.
  match consume_reserved_attempt_current(owner.ledger, reservation) {
    Err(issue) => {
      settle_reservation_current(owner.ledger, reservation) |> ignore
      owner.borrowers -= 1
      return Err(Resource(issue))
    }
    Ok(_) => ()
  }
  let parent = match make_preparation_construction_input_borrow(owner, ()) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  Ok({ reservation, parent, retired: false, })
}

///|
/// Preserve exact observed bytes even if the operation subsequently fails.
/// The fixed caller supplies the original physical observation, never a
/// synthesized payload's length or a codec/profile estimate.
pub fn charge_preparation_io(
  operation : PreparationIo,
  bytes : Int64,
) -> Result[Unit, PreparationCapacityIssue] {
  if operation.retired {
    return Err(Retired)
  }
  charge_transfer(operation.reservation.owner, operation.reservation, bytes)
  .map_err(issue => PreparationCapacityIssue::Resource(issue))
}

///|
/// A dispatched operation without a confirmed extent retains its remaining
/// reserved upper bound as uncertainty. Cleanup cannot erase that history.
pub fn mark_preparation_io_transfer_uncertain(
  operation : PreparationIo,
) -> Result[Unit, PreparationCapacityIssue] {
  if operation.retired {
    return Err(Retired)
  }
  mark_transfer_uncertain(
    operation.reservation.owner,
    operation.reservation,
    operation.reservation.transfer,
  ).map_err(issue => PreparationCapacityIssue::Resource(issue))
}

///|
/// Only after this original operation's physical cleanup acknowledgement.
/// Settlement failure retains the SAME reservation and parent borrow for
/// retry. A later parent-retirement failure stays with that original parent;
/// completing this operation is never acknowledgement of Source/Host close.
pub fn finish_preparation_io_after_cleanup(
  operation : PreparationIo,
) -> Result[Unit, PreparationCapacityIssue] {
  if operation.retired {
    return Ok(())
  }
  if operation.reservation.open {
    match
      settle_reservation(operation.reservation.owner, operation.reservation) {
      Err(issue) => return Err(Resource(issue))
      Ok(_) => ()
    }
  }
  let returned = return_preparation_body_borrow(operation.parent)
  if preparation_body_borrow_value(operation.parent) is None {
    operation.retired = true
  }
  returned.map(_ => ())
}
