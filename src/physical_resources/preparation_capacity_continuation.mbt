///|
/// Select the eventual body type once, before any body or borrower exists.
/// A Source frontend can therefore retain one input reservation while its
/// original parsed result determines Pure or Effect compilation. No P value
/// is converted to Q: there is no completed P value at this boundary.
///
/// The fixed parent must fund the old/new control-record coexistence before
/// this call. This does not reserve, resize, narrow or refund anything. The
/// same input, Ledger, reservation, borrower bound and work history continue.
/// It is a typed continuation, never another Root, supplier or byte allowance.
pub fn[I, P, Q] continue_preparation_capacity(
  owner : PreparationCapacity[I, P],
  input : I,
) -> Result[PreparationCapacity[I, Q], PreparationCapacityIssue] {
  if owner.phase == Continued {
    return Err(AlreadyTransferred)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  if owner.phase == SelectedWorking {
    return Err(AlreadyTransferred)
  }
  if owner.phase != Working ||
    owner.body is Some(_) ||
    owner.borrowers != 0 ||
    owner.retirement_claimed ||
    owner.active_phase_work is Some(_) {
    return Err(WorkActive)
  }
  // Imported currentness may reenter. Fence the old handle before that call;
  // a refusal leaves that same working handle responsible for cleanup.
  owner.phase = Transferring
  match reservation_check(owner.ledger, owner.reservation.reservation) {
    Err(issue) => {
      owner.phase = Working
      return Err(Resource(issue))
    }
    Ok(_) => ()
  }
  match check_imported_child_admission_current(owner.ledger) {
    Err(issue) => {
      owner.phase = Working
      return Err(Resource(issue))
    }
    Ok(_) => ()
  }
  // The same original census can begin retirement inside the current callback.
  // Do not transfer its working token after that callback-free lifetime fence.
  if owner.ledger.original_inventory is Some(inventory) && inventory.closing {
    owner.phase = Working
    return Err(Resource(ClosedReservation))
  }
  let next : PreparationCapacity[I, Q] = {
    ledger: owner.ledger,
    reservation: owner.reservation,
    input: owner.input,
    body: None,
    phase: SelectedWorking,
    borrowers: 0,
    max_borrowers: owner.max_borrowers,
    retirement_claimed: false,
    inventory_growth_active: false,
    active_phase_work: None,
    last_work_phase: owner.last_work_phase,
  }
  // The old handle cannot settle the shared token or acknowledge retirement.
  // All later construction/borrowing/cleanup belongs to this one continuation.
  owner.input = None
  owner.phase = Continued
  Ok(next)
}
