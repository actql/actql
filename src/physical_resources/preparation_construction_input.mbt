///|
// A construction input uses the SAME borrower slots/retirement engine. It is
// immutable DATA held before a final body exists, not a completed body, Plan,
// execution permission or a second owner of the reservation.
fn preparation_borrow_phase_matches(
  phase : PreparationCapacityPhase,
  construction : Bool,
) -> Bool {
  phase == Ready ||
  phase == Run ||
  (construction && preparation_capacity_phase_is_working(phase))
}

///|
fn[I, P] reserve_preparation_borrow_slot(
  owner : PreparationCapacity[I, P],
  construction : Bool,
) -> Result[Unit, PreparationCapacityIssue] {
  if !preparation_borrow_phase_matches(owner.phase, construction) ||
    !preparation_capacity_inventory_open(owner) {
    return Err(Retired)
  }
  if owner.borrowers >= owner.max_borrowers {
    return Err(InvalidExtent)
  }
  // Claim before any original current callback. Reentry cannot allocate the
  // same last slot or release this owner's debit during its pending borrow.
  owner.borrowers += 1
  Ok(())
}

///|
fn[I, P] claim_preparation_borrow_slot(
  owner : PreparationCapacity[I, P],
  construction : Bool,
) -> Result[Unit, PreparationCapacityIssue] {
  match reserve_preparation_borrow_slot(owner, construction) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match check_imported_child_admission(owner.ledger) {
    Err(issue) => {
      owner.borrowers -= 1
      return Err(Resource(issue))
    }
    Ok(_) => ()
  }
  if !preparation_borrow_phase_matches(owner.phase, construction) ||
    !preparation_capacity_inventory_open(owner) {
    owner.borrowers -= 1
    // The same owner retries retirement; rollback is not a cleanup ACK.
    return Err(Retired)
  }
  Ok(())
}

///|
/// Reserve the original next-phase peak and retain its immutable constructor
/// input in one currentness boundary. The input was produced by the fixed
/// domain on this SAME reservation. Domain code supplies its actual inventory;
/// these scalar extents do not establish its meaning or authorize execution.
pub fn[I, P, D] reserve_preparation_construction_input(
  owner : PreparationCapacity[I, P],
  input : I,
  data : D,
  retained : Int64,
  execution : Int64,
) -> Result[PreparationBodyBorrow[D], PreparationCapacityIssue] {
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  if !preparation_capacity_phase_is_working(owner.phase) {
    return Err(AlreadyCompleted)
  }
  match reserve_preparation_borrow_slot(owner, true) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // The original resize already performs currentness, with its transient
  // phase fencing reentry. No check-then-borrow second callback is needed.
  match reserve_working_preparation_phase(owner, input, retained, execution) {
    Err(issue) => {
      owner.borrowers -= 1
      return Err(issue)
    }
    Ok(_) => ()
  }
  if !preparation_capacity_phase_is_working(owner.phase) ||
    !(owner.input is Some(original) && physical_equal(original, input)) {
    owner.borrowers -= 1
    return Err(ForeignOriginal)
  }
  if !preparation_capacity_inventory_open(owner) {
    owner.borrowers -= 1
    return Err(Retired)
  }
  make_preparation_construction_input_borrow(owner, data)
}

///|
// The actual slot has already been claimed. The type-erased view retains its
// DATA only until the original return. No generic raw input survives return.
fn[I, P, D] make_preparation_construction_input_borrow(
  owner : PreparationCapacity[I, P],
  data : D,
) -> Result[PreparationBodyBorrow[D], PreparationCapacityIssue] {
  let slot : PreparationCapacityBorrow[I, P] = {
    owner,
    body: None,
    returned: false,
  }
  let retained : Ref[D?] = Ref(Some(data))
  Ok({
    read_original: () => if slot.returned { None } else { retained.val },
    reserved_extents_original: () => {
      if slot.returned {
        Err(BorrowReturned)
      } else if !preparation_borrow_phase_matches(owner.phase, true) {
        Err(Retired)
      } else {
        let token = owner.reservation.reservation
        if token.open {
          Ok((token.retention, token.execution))
        } else {
          Err(Retired)
        }
      }
    },
    return_original: () => {
      if slot.returned {
        return Err(BorrowReturned)
      }
      retained.val = None
      return_preparation_capacity_borrow(slot)
    },
    retirement_started_original: () => {
      owner.phase == Retiring ||
      owner.phase == Settling ||
      owner.phase == Closed
    },
    borrow_original: () => {
      if slot.returned {
        return Err(BorrowReturned)
      }
      guard retained.val is Some(original) else { return Err(Retired) }
      match claim_preparation_borrow_slot(owner, true) {
        Err(issue) => Err(issue)
        Ok(_) => make_preparation_construction_input_borrow(owner, original)
      }
    },
    // Constructor DATA cannot stand in for a completed adopted body or
    // obtain publication growth through a matching payload/reference.
    isolated_usage_original: _ => false,
    reserve_phase_original: (_, _, _, _) => Err(ForeignOriginal),
  })
}
