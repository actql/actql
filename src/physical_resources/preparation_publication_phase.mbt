///|
/// Publication extends the SAME adopted reservation through its original live
/// body borrow. The generic preparation input and raw capacity never return
/// to the caller. This is not a new grant, borrower or retirement owner.
pub fn[P] reserve_preparation_publication_phase(
  holder : PreparationBodyBorrow[P],
  body : P,
  retained_peak : Int64,
  execution_peak : Int64,
) -> Result[Unit, PreparationCapacityIssue] {
  (holder.reserve_phase_original)(body, retained_peak, execution_peak, Publication)
}

///|
fn[I, P] reserve_original_preparation_publication_phase(
  borrowed : PreparationCapacityBorrow[I, P],
  body : P,
  retained_peak : Int64,
  execution_peak : Int64,
) -> Result[Unit, PreparationCapacityIssue] {
  if borrowed.returned {
    return Err(BorrowReturned)
  }
  let owner = borrowed.owner
  guard borrowed.body is Some(original) &&
    physical_equal(original, body) &&
    owner.body is Some(original_body) &&
    physical_equal(original_body, body) else {
    return Err(ForeignOriginal)
  }
  if owner.phase != Run ||
    owner.borrowers <= 0 ||
    owner.active_phase_work is Some(_) {
    return Err(WorkActive)
  }
  let token = owner.reservation.reservation
  if retained_peak < token.retention || execution_peak < token.execution {
    return Err(InvalidExtent)
  }
  // The existing transition latch blocks retirement, new borrowers, and a
  // reentrant publication grow before imported currentness is invoked.
  owner.phase = Transferring
  let outcome = resize_capacity_reservation(
    owner.ledger,
    owner.reservation,
    retained_peak,
    execution_peak,
  )
  owner.phase = Run
  match outcome {
    Err(issue) => Err(Resource(issue))
    Ok(_) =>
      // A currentness callback can return an existing borrower. Do not
      // authorize construction after this selected custody was returned,
      // even while another slot remains live. Original stopping precedence
      // and the admitted debit remain with the ordinary retirement path.
      if owner.ledger.imported_child is Some(origin) && origin.stopping {
        Err(Resource(ClosedReservation))
      } else if borrowed.returned {
        Err(BorrowReturned)
      } else if owner.borrowers <= 0 {
        Err(WorkActive)
      } else {
        Ok(())
      }
  }
}
