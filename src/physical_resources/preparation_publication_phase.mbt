///|
/// Fixed publication driver only: extend the original adopted preparation
/// reservation, never create a new Ledger or reservation. The caller derives
/// both totals from retained original plans and constructor inventories.
/// Live body borrowers remain charged; execution is a monotone high-water
/// debit until actual retirement, not a claim about garbage collection.
pub fn[I,P] reserve_preparation_publication_phase(
  owner : PreparationCapacity[I,P],input : I,body : P,
  retained_peak : Int64,execution_peak : Int64,
) -> Result[Unit,PreparationCapacityIssue] {
  guard owner.input is Some(original) && physical_equal(original,input) &&
    owner.body is Some(original_body) && physical_equal(original_body,body) else {
    return Err(ForeignOriginal)
  }
  if owner.phase!=Run || owner.borrowers<=0 || owner.active_phase_work is Some(_) {
    return Err(WorkActive)
  }
  let token=owner.reservation.reservation
  if retained_peak<token.retention || execution_peak<token.execution {
    return Err(InvalidExtent)
  }
  // The existing transition latch blocks retirement, new borrowers, and a
  // reentrant publication grow before imported currentness is invoked.
  owner.phase=Transferring
  let outcome=resize_capacity_reservation(owner.ledger,owner.reservation,retained_peak,execution_peak)
  owner.phase=Run
  match outcome {
    Err(issue)=>Err(Resource(issue))
    Ok(_)=>{
      // A currentness callback can return an existing borrower. Do not
      // authorize construction if the last live body custody was cut there.
      // The admitted debit remains charged for the ordinary retirement path.
      if owner.ledger.imported_child is Some(origin) && origin.stopping {
        Err(Resource(ClosedReservation))
      } else if owner.borrowers<=0 {Err(WorkActive)} else {Ok(())}
    }
  }
}
