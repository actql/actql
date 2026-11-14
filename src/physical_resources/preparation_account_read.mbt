///|
/// Account metadata borrows the existing preparation's nominal input and
/// retirement slot. Its byte-only child remains on that SAME Ledger. Neither
/// this view nor a quoted amount issues a Ledger, transfer or authorization.
struct PreparationAccountRead {
  prepare_original : (Int64, Int64) -> Result[Unit, PreparationCapacityIssue]
  close_original : (Bool) -> Result[Bool, PreparationCapacityIssue]
}

///|
/// Fixed state, exact construction-input borrower, three closure records,
/// returned alternatives and current/failure controls; the fixed Node frame,
/// registry entry and bound methods are included before variable input.
pub fn preparation_account_read_control_slots() -> (Int64, Int64, Int64) {
  (64L, 192L, 96L)
}

///|
pub fn[I, P] prepare_account_read(
  owner : PreparationCapacity[I, P],
  input : I,
  control_bytes : Int64,
) -> Result[PreparationAccountRead, PreparationCapacityIssue] {
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  if control_bytes <= 0L || owner.active_phase_work is Some(_) {
    return Err(InvalidExtent)
  }
  match reserve_preparation_borrow_slot(owner, true) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // Claim retirement custody before the one imported-current callback. The
  // fixed read controls are funded before their records/closures are built.
  let token = match
    reserve_capacity(owner.ledger, control_bytes, control_bytes) {
    Err(issue) => {
      owner.borrowers -= 1
      return Err(Resource(issue))
    }
    Ok(value) => value
  }
  let holder = make_preparation_construction_input_borrow(owner, input).unwrap()
  let closed = Ref(false)
  let busy = Ref(false)
  let failed = Ref(false)
  Ok({
    prepare_original: (retained, execution) => {
      if closed.val ||
        busy.val ||
        failed.val ||
        preparation_body_retirement_started(holder) ||
        !(owner.input is Some(original) && physical_equal(original, input)) ||
        !preparation_borrow_phase_matches(owner.phase, true) {
        Err(Retired)
      } else {
        busy.val = true
        let result = grow_capacity_reservation(
          owner.ledger,
          token,
          retained,
          execution,
        ).map_err(issue => PreparationCapacityIssue::Resource(issue))
        busy.val = false
        if result is Err(_) {
          failed.val = true
        }
        if preparation_body_retirement_started(holder) {
          failed.val = true
          Err(Retired)
        } else {
          result
        }
      }
    },
    close_original: acknowledged => {
      if closed.val {
        Ok(true)
      } else if busy.val || !acknowledged {
        Ok(false)
      } else {
        // Caller has disposed constructor/escaped DATA and observed its SAME
        // physical close. Stop/current denial never supplies this ACK.
        match settle_capacity(owner.ledger, token) {
          Err(issue) => Err(Resource(issue))
          Ok(_) => {
            closed.val = true
            return_preparation_body_borrow(holder).map(_ => true)
          }
        }
      }
    },
  })
}

///|
pub fn prepare_account_read_construction(
  read : PreparationAccountRead,
  retained : Int64,
  execution : Int64,
) -> Result[Unit, PreparationCapacityIssue] {
  (read.prepare_original)(retained, execution)
}

///|
pub fn close_preparation_account_read(
  read : PreparationAccountRead,
  physical_and_data_cleanup_complete : Bool,
) -> Result[Bool, PreparationCapacityIssue] {
  (read.close_original)(physical_and_data_cleanup_complete)
}
