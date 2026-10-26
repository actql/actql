///|
priv enum PreparationCapacityPhase {
  Working
  Completing
  Ready
  Transferring
  Run
  Retiring
  Settling
  Closed
} derive(Eq)

///|
/// One preparation allocation on an already selected original Ledger. This
/// API cannot create a Ledger, select a Host, or grant a second resource pool.
/// The fixed supplier must fund this control envelope before constructing it.
struct PreparationCapacity[I, P] {
  ledger : Ledger
  reservation : CapacityReservation
  mut input : I?
  mut body : P?
  mut phase : PreparationCapacityPhase
  mut borrowers : Int
  max_borrowers : Int
  mut retirement_claimed : Bool
  mut active_phase_work : Ref[Bool]?
  mut last_work_phase : Int
}

///|
struct PreparationCapacityBorrow[I, P] {
  owner : PreparationCapacity[I, P]
  mut body : P?
  mut returned : Bool
}

///|
pub(all) enum PreparationCapacityIssue {
  ForeignOriginal
  WorkActive
  AlreadyCompleted
  AlreadyTransferred
  Retired
  BorrowReturned
  InvalidExtent
  Resource(LedgerIssue)
} derive(Eq, Debug)

///|
pub fn[I, P] reserve_preparation_capacity(
  ledger : Ledger,
  input : I,
  retained_peak : Int64,
  execution_peak : Int64,
  max_borrowers~ : Int,
) -> Result[PreparationCapacity[I, P], PreparationCapacityIssue] {
  if max_borrowers < 1 || retained_peak <= 0L || execution_peak < 0L {
    return Err(InvalidExtent)
  }
  reserve_capacity(ledger, retained_peak, execution_peak)
  .map_err(issue => PreparationCapacityIssue::Resource(issue))
  .map(reservation => {
    ledger,
    reservation,
    input: Some(input),
    body: None,
    phase: Working,
    borrowers: 0,
    max_borrowers,
    retirement_claimed: false,
    active_phase_work: None,
    last_work_phase: -1,
  })
}

///|
/// Reserve the complete next phase coexistence envelope before allocating it.
/// The prior immutable dependency body remains owned until completion installs
/// its replacement. This is not a second reservation or an authority refill.
/// Only the fixed preparation driver may provide a proof-derived envelope.
pub fn[I, P] begin_preparation_capacity_phase(
  owner : PreparationCapacity[I, P],
  input : I,
  previous : P,
  retained_peak : Int64,
  execution_peak : Int64,
) -> Result[Unit, PreparationCapacityIssue] {
  if !(owner.input is Some(original) && physical_equal(original, input)) ||
    !(owner.body is Some(original) && physical_equal(original, previous)) {
    return Err(ForeignOriginal)
  }
  if owner.phase != Ready || owner.borrowers != 0 {
    return Err(WorkActive)
  }
  let token = owner.reservation.reservation
  if retained_peak < token.retention || execution_peak < token.execution {
    return Err(InvalidExtent)
  }
  // Latch before original currentness callbacks; reentry cannot start a phase.
  owner.phase = Completing
  match
    resize_capacity_reservation(
      owner.ledger,
      owner.reservation,
      retained_peak,
      execution_peak,
    ) {
    Err(issue) => {
      owner.phase = Ready
      return Err(Resource(issue))
    }
    Ok(_) => ()
  }
  owner.phase = Working
  Ok(())
}

///|
/// The original completed body is retained before the currentness check. On
/// failure its original peak remains charged and the same owner must retire it.
/// The supplied extent must come from the fixed consumer's complete inventory,
/// not a successful sample or a claim that another owner released its memory.
pub fn[I, P] complete_preparation_capacity(
  owner : PreparationCapacity[I, P],
  input : I,
  body : P,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[Unit, PreparationCapacityIssue] {
  if !(owner.input is Some(original) && physical_equal(original, input)) {
    return Err(ForeignOriginal)
  }
  if owner.phase != Working {
    return Err(AlreadyCompleted)
  }
  if owner.active_phase_work is Some(_) {
    return Err(WorkActive)
  }
  if retained_bytes <= 0L ||
    execution_bytes < 0L ||
    retained_bytes > owner.reservation.reservation.retention ||
    execution_bytes > owner.reservation.reservation.execution {
    return Err(InvalidExtent)
  }
  owner.body = Some(body)
  owner.phase = Completing
  match
    resize_capacity_reservation(
      owner.ledger,
      owner.reservation,
      retained_bytes,
      execution_bytes,
    ) {
    Err(issue) => {
      owner.phase = Retiring
      Err(Resource(issue))
    }
    Ok(_) => {
      owner.phase = Ready
      Ok(())
    }
  }
}

///|
/// Transfer custody, not bytes: the exact original reservation stays on the
/// exact original Ledger, once, with no release/reacquire gap or per-task debit.
pub fn[I, P] transfer_preparation_capacity_to_run(
  owner : PreparationCapacity[I, P],
  input : I,
  body : P,
  ledger : Ledger,
) -> Result[Unit, PreparationCapacityIssue] {
  if !physical_equal(owner.ledger, ledger) ||
    !(owner.input is Some(original) && physical_equal(original, input)) ||
    !(owner.body is Some(original) && physical_equal(original, body)) {
    return Err(ForeignOriginal)
  }
  match owner.phase {
    Run => return Err(AlreadyTransferred)
    Ready => ()
    Working | Completing | Transferring => return Err(WorkActive)
    _ => return Err(Retired)
  }
  owner.phase = Transferring
  match reservation_check(ledger, owner.reservation.reservation) {
    Err(issue) => {
      owner.phase = Ready
      return Err(Resource(issue))
    }
    Ok(_) => ()
  }
  if (ledger.imported_child is Some(origin) && origin.stopping) ||
    (ledger.original_inventory is Some(inventory) && inventory.closing) {
    owner.phase = Ready
    return Err(Resource(ClosedReservation))
  }
  owner.phase = Run
  Ok(())
}

///|
pub fn[I, P] borrow_preparation_capacity(
  owner : PreparationCapacity[I, P],
) -> Result[PreparationCapacityBorrow[I, P], PreparationCapacityIssue] {
  if owner.phase != Ready && owner.phase != Run {
    return Err(Retired)
  }
  if owner.borrowers >= owner.max_borrowers {
    return Err(InvalidExtent)
  }
  guard owner.body is Some(body) else { return Err(Retired) }
  // Claim the finite borrower slot before invoking imported currentness. A
  // reentrant retirement cannot release the body's reservation during that
  // callback, and recursive borrows cannot bypass the original slot bound.
  owner.borrowers += 1
  match check_imported_child_admission(owner.ledger) {
    Err(issue) => {
      owner.borrowers -= 1
      return Err(Resource(issue))
    }
    Ok(_) => ()
  }
  if owner.phase != Ready && owner.phase != Run {
    owner.borrowers -= 1
    // The existing retirement owner retries cleanup; do not convert a failed
    // borrow into an independent release acknowledgement.
    return Err(Retired)
  }
  Ok({ owner, body: Some(body), returned: false, })
}

///|
pub fn[I, P] preparation_capacity_borrow_value(
  value : PreparationCapacityBorrow[I, P],
) -> P? {
  if value.returned {
    None
  } else {
    value.body
  }
}

///|
fn[I, P] finish_preparation_retirement(
  owner : PreparationCapacity[I, P],
) -> Result[Bool, PreparationCapacityIssue] {
  if owner.phase == Closed {
    return Ok(true)
  }
  if owner.borrowers != 0 {
    return Ok(false)
  }
  // Remove actual strong references before returning the retained allowance.
  owner.body = None
  owner.input = None
  owner.phase = Settling
  match settle_capacity(owner.ledger, owner.reservation) {
    Err(issue) => {
      owner.phase = Retiring
      Err(Resource(issue))
    }
    Ok(_) => {
      owner.phase = Closed
      Ok(true)
    }
  }
}

///|
pub fn[I, P] retire_preparation_capacity(
  owner : PreparationCapacity[I, P],
) -> Result[Bool, PreparationCapacityIssue] {
  if owner.phase == Working ||
    owner.phase == Completing ||
    owner.phase == Transferring ||
    owner.phase == Settling {
    return Err(WorkActive)
  }
  if owner.phase != Closed {
    owner.phase = Retiring
  }
  finish_preparation_retirement(owner)
}

///|
/// Only the fixed synchronous preparation owner calls this after its failed
/// construction has unwound and disposed its scratch. Cancellation alone is
/// not such an acknowledgement and must not invoke this entry prematurely.
pub fn[I, P] abort_preparation_capacity_after_cleanup(
  owner : PreparationCapacity[I, P],
  input : I,
) -> Result[Bool, PreparationCapacityIssue] {
  if !(owner.input is Some(original) && physical_equal(original, input)) {
    return Err(ForeignOriginal)
  }
  if owner.phase != Working {
    return Err(AlreadyCompleted)
  }
  if owner.active_phase_work is Some(_) {
    return Err(WorkActive)
  }
  owner.phase = Retiring
  finish_preparation_retirement(owner)
}

///|
pub fn[I, P] return_preparation_capacity_borrow(
  value : PreparationCapacityBorrow[I, P],
) -> Result[Bool, PreparationCapacityIssue] {
  if value.returned {
    return Err(BorrowReturned)
  }
  value.returned = true
  value.body = None
  value.owner.borrowers -= 1
  if value.owner.phase == Retiring {
    finish_preparation_retirement(value.owner)
  } else {
    Ok(false)
  }
}

///|
/// Type-erased cleanup custody, not a callback supplied by an adapter. The
/// private closure retains the exact original phase owner; all borrowers and
/// bytes remain governed by that owner, with no second counter or reservation.
struct PreparationRetirement {
  retire_original : () -> Result[Bool, PreparationCapacityIssue]
}

///|
/// The fixed Node adoption path transfers the original reservation and returns
/// its cleanup custody together. Its constructor envelope must fund this one
/// handle/closure before calling. No raw generic input survives in the Run API.
pub fn[I, P] transfer_preparation_retirement_to_run(
  owner : PreparationCapacity[I, P],
  input : I,
  body : P,
  ledger : Ledger,
) -> Result[PreparationRetirement, PreparationCapacityIssue] {
  if owner.retirement_claimed {
    return Err(AlreadyTransferred)
  }
  match transfer_preparation_capacity_to_run(owner, input, body, ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  owner.retirement_claimed = true
  Ok({ retire_original: () => retire_preparation_capacity(owner), })
}

///|
pub fn retire_transferred_preparation(
  value : PreparationRetirement,
) -> Result[Bool, PreparationCapacityIssue] {
  (value.retire_original)()
}

///|
/// An erased input-type adapter over one original Core borrower. The fixed
/// closures capture the borrower token, never a separately retained raw body.
/// Returning it clears that token's body and decrements the same owner once.
struct PreparationBodyBorrow[P] {
  read_original : () -> P?
  return_original : () -> Result[Bool, PreparationCapacityIssue]
  retirement_started_original : () -> Bool
  borrow_original : () -> Result[
    PreparationBodyBorrow[P],
    PreparationCapacityIssue,
  ]
  isolated_usage_original : (Ledger, CapacityReservation?) -> Bool
}

///|
pub fn[I, P] borrow_preparation_body(
  owner : PreparationCapacity[I, P],
) -> Result[PreparationBodyBorrow[P], PreparationCapacityIssue] {
  match borrow_preparation_capacity(owner) {
    Err(issue) => Err(issue)
    Ok(value) =>
      Ok({
        read_original: () => preparation_capacity_borrow_value(value),
        return_original: () => return_preparation_capacity_borrow(value),
        retirement_started_original: () => {
          value.owner.phase == Retiring ||
          value.owner.phase == Settling ||
          value.owner.phase == Closed
        },
        borrow_original: () => {
          if value.returned {
            Err(BorrowReturned)
          } else {
            borrow_preparation_body(value.owner)
          }
        },
        isolated_usage_original: (ledger, bootstrap) => {
          !value.returned &&
          preparation_capacity_usage_isolated(value.owner, ledger, bootstrap)
        },
      })
  }
}

///|
pub fn[P] preparation_body_borrow_value(value : PreparationBodyBorrow[P]) -> P? {
  (value.read_original)()
}

///|
pub fn[P] return_preparation_body_borrow(
  value : PreparationBodyBorrow[P],
) -> Result[Bool, PreparationCapacityIssue] {
  (value.return_original)()
}

///|
/// Read-only phase provenance for the fixed holder-clearing path. It grants no
/// cleanup acknowledgement, does not mutate the phase and supplies no bytes.
pub fn[P] preparation_body_retirement_started(
  value : PreparationBodyBorrow[P],
) -> Bool {
  (value.retirement_started_original)()
}

///|
/// The fixed Run/Host holder may retain an operation dependency from the same
/// original owner, without recovering its generic input or creating a pool.
/// A returned holder and a retiring owner cannot authorize new operation use.
pub fn[P] borrow_preparation_body_sibling(
  value : PreparationBodyBorrow[P],
) -> Result[PreparationBodyBorrow[P], PreparationCapacityIssue] {
  (value.borrow_original)()
}

///|
/// Read-only accounting correspondence, NOT a physical-stop or cleanup proof.
/// Historical planning/attempt/transfer/peak counters are intentionally ignored;
/// they cannot establish current liveness and are never reset by this check.
fn[I, P] preparation_capacity_usage_isolated(
  owner : PreparationCapacity[I, P],
  ledger : Ledger,
  bootstrap : CapacityReservation?,
) -> Bool {
  if !physical_equal(owner.ledger, ledger) {
    return false
  }
  let token = owner.reservation.reservation
  if !token.open || token.cleanup_pending {
    return false
  }
  if ledger.imported_child is Some(origin) && origin.unavailable {
    return false
  }
  if ledger.original_inventory is Some(inventory) && inventory.park is Some(_) {
    return false
  }
  if ledger.quantity_usage.reserved != zero_quantities() ||
    ledger.quantity_usage.uncertain != zero_quantities() {
    return false
  }
  let (bootstrap_retention, bootstrap_execution) = match bootstrap {
    None => (0L, 0L)
    Some(bootstrap) => {
      guard ledger.original_inventory is Some(inventory) &&
        physical_equal(inventory.bootstrap, bootstrap) &&
        physical_equal(bootstrap.reservation.owner, ledger) &&
        capacity_reservation_open(bootstrap) &&
        !bootstrap.reservation.cleanup_pending else {
        return false
      }
      (bootstrap.reservation.retention, bootstrap.reservation.execution)
    }
  }
  // Zero-byte children still occupy original identities. Byte equality alone
  // cannot prove that this preparation (and its exact bootstrap) is isolated.
  if ledger.original_inventory is Some(inventory) {
    if inventory.reservations.length() != 1 ||
      !physical_equal(inventory.reservations[0], token) ||
      !inventory.holdings.is_empty() ||
      !inventory.delegations.is_empty() {
      return false
    }
  }
  let expected_reservations = if bootstrap is Some(_) { 2 } else { 1 }
  let usage = ledger.usage
  usage.live_reservations == expected_reservations &&
  usage.live_delegations == 0 &&
  usage.holdings == 0 &&
  usage.reserved_attempts == 0 &&
  usage.reserved_retention_bytes >= token.retention &&
  usage.reserved_execution_bytes >= token.execution &&
  usage.held_bytes == 0L &&
  usage.reserved_transfer_bytes == 0L &&
  usage.uncertain_transfer_bytes == 0L &&
  usage.reserved_retention_bytes - token.retention == bootstrap_retention &&
  usage.reserved_execution_bytes - token.execution == bootstrap_execution &&
  ledger.delegated_planning == 0 &&
  ledger.delegated_attempts == 0 &&
  ledger.delegated_holdings == 0
}

///|
/// Use only alongside the existing confirmed physical-stop/reader witnesses.
/// It replaces a numerical zero-use test when the same preparation is rightly
/// still retained; it never authorizes severing or returns the reservation.
pub fn[P] preparation_body_usage_isolated(
  value : PreparationBodyBorrow[P],
  ledger : Ledger,
) -> Bool {
  (value.isolated_usage_original)(ledger, None)
}

///|
/// Grow the next constructor's complete coexistence envelope while the fixed
/// synchronous preparation driver still owns typed intermediate representations.
/// P is bound only at final completion; no fake Prepared is used for parser ASTs.
/// This is not a phase-completion or cancellation acknowledgement.
pub fn[I, P] reserve_working_preparation_phase(
  owner : PreparationCapacity[I, P],
  input : I,
  retained_peak : Int64,
  execution_peak : Int64,
) -> Result[Unit, PreparationCapacityIssue] {
  if !(owner.input is Some(original) && physical_equal(original, input)) {
    return Err(ForeignOriginal)
  }
  if owner.phase != Working ||
    owner.body is Some(_) ||
    owner.active_phase_work is Some(_) {
    return Err(WorkActive)
  }
  let token = owner.reservation.reservation
  if retained_peak < token.retention || execution_peak < token.execution {
    return Err(InvalidExtent)
  }
  owner.phase = Completing
  let outcome = resize_capacity_reservation(
    owner.ledger,
    owner.reservation,
    retained_peak,
    execution_peak,
  )
  owner.phase = Working
  outcome.map_err(issue => PreparationCapacityIssue::Resource(issue))
}

///|
/// Called by that same fixed driver only after previous phase scratch is
/// disposed. Live parser/indexed/checked dependencies remain in retained_bytes;
/// this does not retire the working owner or clear any intermediate by fiat.
pub fn[I, P] reconcile_working_preparation_phase(
  owner : PreparationCapacity[I, P],
  input : I,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[Unit, PreparationCapacityIssue] {
  if !(owner.input is Some(original) && physical_equal(original, input)) {
    return Err(ForeignOriginal)
  }
  if owner.phase != Working ||
    owner.body is Some(_) ||
    owner.active_phase_work is Some(_) {
    return Err(WorkActive)
  }
  let token = owner.reservation.reservation
  if retained_bytes <= 0L ||
    execution_bytes < 0L ||
    retained_bytes > token.retention ||
    execution_bytes > token.execution {
    return Err(InvalidExtent)
  }
  owner.phase = Completing
  let outcome = resize_capacity_reservation(
    owner.ledger,
    owner.reservation,
    retained_bytes,
    execution_bytes,
  )
  owner.phase = Working
  outcome.map_err(issue => PreparationCapacityIssue::Resource(issue))
}
