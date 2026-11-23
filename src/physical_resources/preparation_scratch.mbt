///|
/// A measured increment of one working reservation. This same receipt can
/// cross adoption and return the increment once, after its owner drops the
/// scratch. Callers cannot supply either measured extent.
struct PreparationScratch[I, P] {
  owner : PreparationCapacity[I, P]
  baseline : (Int64, Int64)
  charged : (Int64, Int64)
  mut returned : Bool
}

///|
/// Back the measurement receipt before running the trusted synchronous
/// constructor. The constructor adds scratch on this same working owner.
/// Its Result is retained so an optional refusal can return the actual debit.
pub fn[I, P, V] measure_working_preparation_scratch(
  owner : PreparationCapacity[I, P],
  input : I,
  control_bytes : Int64,
  construct : () -> V,
) -> Result[(V, PreparationScratch[I, P]), PreparationCapacityIssue] {
  if control_bytes <= 0L {
    return Err(InvalidExtent)
  }
  if owner.inventory_growth_active {
    return Err(WorkActive)
  }
  let baseline = match preparation_capacity_working_extents(owner, input) {
    Err(issue) => return Err(issue)
    Ok(extent) => extent
  }
  guard @preparation_counts.checked_nonnegative_add_product(
      baseline.0,
      control_bytes,
      1L,
    )
    is Some(retained) &&
    @preparation_counts.checked_nonnegative_add_product(
      baseline.1,
      control_bytes,
      1L,
    )
    is Some(execution) else {
    return Err(InvalidExtent)
  }
  // The same owner-local growth latch also prevents nested measurement of
  // the same debit. Ordinary working resizes keep their own current latch.
  owner.inventory_growth_active = true
  let result = match
    reserve_working_preparation_phase(owner, input, retained, execution) {
    Err(issue) => Err(issue)
    Ok(_) => {
      let value = construct()
      preparation_capacity_working_extents(owner, input).bind(charged => {
        if charged.0 < retained || charged.1 < execution {
          Err(InvalidExtent)
        } else {
          Ok((value, { owner, baseline, charged, returned: false, }))
        }
      })
    }
  }
  owner.inventory_growth_active = false
  result
}

///|
/// Return one measured scratch ticket on the original preparation or its
/// adopted Run. A refusal keeps the debit and receipt in the original custody.
pub fn[I, P] return_preparation_scratch(
  owner : PreparationCapacity[I, P],
  input : I,
  scratch : PreparationScratch[I, P],
) -> Result[Unit, PreparationCapacityIssue] {
  if !physical_equal(owner, scratch.owner) ||
    !(owner.input is Some(original) && physical_equal(original, input)) {
    return Err(ForeignOriginal)
  }
  if scratch.returned {
    return Err(BorrowReturned)
  }
  let original_phase = owner.phase
  let run = original_phase == Run
  if run {
    if owner.body is None ||
      owner.borrowers <= 0 ||
      (
        owner.active_phase_work is Some(_) &&
        !preparation_run_publication_work_returned(owner)
      ) {
      return Err(WorkActive)
    }
  } else if preparation_capacity_working_extents(owner, input) is Err(issue) {
    return Err(issue)
  }
  if owner.inventory_growth_active {
    return Err(WorkActive)
  }
  let token = owner.reservation.reservation
  let (retained, execution) = (token.retention, token.execution)
  if retained < scratch.charged.0 || execution < scratch.charged.1 {
    return Err(InvalidExtent)
  }
  let fence = if run { Transferring } else { Completing }
  owner.phase = fence
  let outcome : Result[Unit, PreparationCapacityIssue] = match
    reservation_check(owner.ledger, token) {
    Err(issue) => Err(Resource(issue))
    Ok(_) =>
      if owner.phase != fence ||
        scratch.returned ||
        !(owner.input is Some(original) && physical_equal(original, input)) ||
        (run && (owner.body is None || owner.borrowers <= 0)) ||
        !physical_equal(owner.reservation.reservation, token) ||
        token.retention != retained ||
        token.execution != execution {
        Err(ForeignOriginal)
      } else {
        match check_imported_child_admission_current(owner.ledger) {
          Err(issue) => Err(Resource(issue))
          Ok(_) =>
            if owner.ledger.original_inventory is Some(inventory) &&
              inventory.closing {
              Err(Resource(ClosedReservation))
            } else {
              resize_capacity_reservation_current(
                owner.ledger,
                owner.reservation,
                retained - (scratch.charged.0 - scratch.baseline.0),
                execution - (scratch.charged.1 - scratch.baseline.1),
              )
              .map_err(issue => PreparationCapacityIssue::Resource(issue))
              .map(_ => scratch.returned = true)
            }
        }
      }
  }
  if owner.phase == fence {
    owner.phase = original_phase
  }
  outcome
}
