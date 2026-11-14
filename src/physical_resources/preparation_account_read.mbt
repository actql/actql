///|
/// Account metadata borrows the existing preparation's nominal input and
/// retirement slot. Its byte-only child remains on that SAME Ledger. Neither
/// this view nor a quoted amount issues a Ledger, transfer or authorization.
struct PreparationAccountRead {
  prepare_original : (Int64, Int64) -> Result[Unit, PreparationCapacityIssue]
  complete_original : () -> Result[Unit, PreparationCapacityIssue]
  close_original : (Bool) -> Result[Bool, PreparationCapacityIssue]
}

///|
/// Fixed state, exact construction-input borrower, three closure records,
/// returned alternatives and current/failure controls; the fixed Node frame,
/// registry entry and bound methods are included before variable input.
pub fn preparation_account_read_control_slots() -> (Int64, Int64, Int64) {
  // The completion closure and its single-consume Ref add two records,
  // ten captured/owner references and one scalar to the same funded cohort.
  (66L, 202L, 97L)
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
  let completed = Ref(false)
  Ok({
    prepare_original: (retained, execution) => {
      if closed.val ||
        busy.val ||
        failed.val ||
        completed.val ||
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
    complete_original: () => {
      if completed.val {
        Err(AlreadyCompleted)
      } else if closed.val ||
        busy.val ||
        failed.val ||
        preparation_body_retirement_started(holder) ||
        !(owner.input is Some(original) && physical_equal(original, input)) ||
        !preparation_borrow_phase_matches(owner.phase, true) {
        Err(Retired)
      } else {
        busy.val = true
        let result : Result[Unit, PreparationCapacityIssue] = match
          reservation_check(owner.ledger, token.reservation) {
          Err(issue) => Err(Resource(issue))
          Ok(_) =>
            // Recheck the SAME parent after its fallible current callback.
            // Retirement during that callback cannot release the old peak.
            if preparation_body_retirement_started(holder) ||
              !(owner.input is Some(original) && physical_equal(original, input)) ||
              !preparation_borrow_phase_matches(owner.phase, true) {
              Err(Retired)
            } else if token.reservation.retention <= 0L ||
              token.reservation.retention > token.reservation.execution {
              Err(InvalidExtent)
            } else {
              // Preserve ALL admitted retained bytes and the live Read/borrow.
              // Only the returned synchronous constructor's workspace ends.
              // No caller amount, new token or physical-close ACK enters here.
              resize_capacity_reservation_current(
                owner.ledger,
                token,
                token.reservation.retention,
                token.reservation.retention,
              ).map_err(issue => PreparationCapacityIssue::Resource(issue))
            }
        }
        busy.val = false
        if result is Err(_) {
          failed.val = true
        } else {
          completed.val = true
        }
        result
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

///|
/// The fixed Account constructor calls this only after retaining its actual
/// completed DATA/gate and disposing synchronous parse/canonical/admission
/// scratch. It keeps the exact retained debit and original cleanup obligation;
/// it supplies neither an authorization decision nor physical retirement.
pub fn complete_account_read_construction(
  read : PreparationAccountRead,
) -> Result[Unit, PreparationCapacityIssue] {
  (read.complete_original)()
}
