///|
/// Request input view of the existing fresh backed-child admission. The
/// physical issuer owns its region, lease, report and after-owner-ACK cleanup.
/// A previously started Read/Host frame cannot be converted into this view.
struct BackedPreparationAdmission[I] {
  mut original : BackedPreparationAdmission[I]?
  initial : BackedInitializationAdmission[I]
  mut transitioning : Bool
  mut transferred : Bool
}

///|
/// The original input and live projection, not numbers, callbacks or an
/// equivalent Ledger, select the already backed Request child once.
pub fn[P, C, I] prepare_backed_preparation_admission(
  projection : BackedExecutionLiveProjection[P, C, I],
  input : I,
) -> Result[BackedPreparationAdmission[I], ImportedChildLedgerIssue] {
  let initial = match
    prepare_backed_initialization_admission(projection, input) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let owner : BackedPreparationAdmission[I] = {
    original: None,
    initial,
    transitioning: false,
    transferred: false,
  }
  owner.original = Some(owner)
  Ok(owner)
}

///|
fn[I] backed_preparation_original(
  owner : BackedPreparationAdmission[I],
) -> Result[Unit, ImportedChildLedgerIssue] {
  if !(owner.original is Some(original) && physical_equal(owner, original)) {
    return Err(ForeignOriginal)
  }
  if owner.transitioning {
    Err(Unknown)
  } else if owner.transferred {
    Err(AlreadyConsumed)
  } else {
    Ok(())
  }
}

///|
pub fn[I] check_backed_preparation_input(
  owner : BackedPreparationAdmission[I],
  input : I,
) -> Result[Unit, ImportedChildLedgerIssue] {
  match backed_preparation_original(owner) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  check_backed_initialization_input(owner.initial, input)
}

///|
/// Fresh original admission only. Its physical issuer retains the SAME child
/// before this start, including a failed start/take; no fresh Root is created.
pub fn[I] start_backed_preparation_admission(
  owner : BackedPreparationAdmission[I],
  input : I,
) -> Result[Ledger, ImportedChildLedgerIssue] {
  match check_backed_preparation_input(owner, input) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if owner.initial.host_taken {
    return Err(AlreadyConsumed)
  }
  owner.initial.host_taken = true
  owner.transitioning = true
  let result = start_backed_initialization_admission(owner.initial)
  owner.transitioning = false
  result
}

///|
/// Physical issuer's original frame, never a caller replacement or new take.
pub fn[I] backed_preparation_original_frame(
  owner : BackedPreparationAdmission[I],
  input : I,
) -> Result[ImportedChildLedger, ImportedChildLedgerIssue] {
  match check_backed_preparation_input(owner, input) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  backed_initialization_original_frame(owner.initial, input)
}

///|
/// Immutable limits of this SAME started input child. This is DATA only;
/// constructor, input, output and failed-child coexistence require backing.
pub fn[I] backed_preparation_limits(
  owner : BackedPreparationAdmission[I],
  input : I,
) -> Result[LedgerLimits, ImportedChildLedgerIssue] {
  match check_backed_preparation_input(owner, input) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard owner.initial.host_taken && owner.initial.frame.ledger is Some(ledger) else {
    return Err(Unavailable)
  }
  Ok(ledger_limits(ledger))
}

///|
/// The same physical issuer completes its own stop/report/after-owner-ACK
/// sequence. This adapter never settles the enclosing Host or VM allocation.
pub fn[I] cleanup_backed_preparation_admission(
  owner : BackedPreparationAdmission[I],
) -> Result[Unit, ImportedChildLedgerIssue] {
  match backed_preparation_original(owner) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  owner.transitioning = true
  let result = cleanup_backed_initialization_admission(owner.initial)
  owner.transitioning = false
  result
}

///|
/// Same original child and two existing preparation holders after transfer.
/// The erased cleanup captures the existing input admission, not a callback
/// supplied by a driver. Neither this view nor the body grants execution.
struct BackedPreparedRunAdmission[P] {
  mut original : BackedPreparedRunAdmission[P]?
  child : ImportedChildLedger
  mut holder : PreparationBodyBorrow[P]?
  cleanup_original : () -> Result[Unit, ImportedChildLedgerIssue]
  owner_retired : () -> Bool
  mut transitioning : Bool
  mut cleaned : Bool
}

///|
pub fn[I, P] adopt_backed_preparation_admission(
  owner : BackedPreparationAdmission[I],
  input : I,
  capacity : PreparationCapacity[I, P],
  prepared : P,
) -> Result[
  (
    BackedPreparedRunAdmission[P],
    Ledger,
    PreparationRetirement,
    PreparationBodyBorrow[P],
  ),
  ImportedChildLedgerIssue,
] {
  match check_backed_preparation_input(owner, input) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let initial = owner.initial
  let child = initial.frame
  guard initial.host_taken && child.taken && child.ledger is Some(ledger) else {
    return Err(Unavailable)
  }
  if child.pending_report is Some(_) ||
    child.pending_report_issue is Some(_) ||
    child.stop_attempted ||
    child.origin.stopping {
    return Err(Unavailable)
  }
  if !physical_equal(capacity.ledger, ledger) ||
    !(capacity.input is Some(original) && physical_equal(original, input)) ||
    !(capacity.body is Some(original) && physical_equal(original, prepared)) {
    return Err(ForeignOriginal)
  }
  if capacity.phase != Ready ||
    capacity.retirement_claimed ||
    capacity.borrowers > capacity.max_borrowers - 2 {
    return Err(Unavailable)
  }
  owner.transitioning = true
  let transferred = transfer_preparation_adoption_holders(
    capacity,
    input,
    prepared,
    ledger,
    () => check_imported_original_child_ledger(child, ledger),
  )
  let (retirement, holder, run_holder) = match transferred {
    Err(issue) => {
      owner.transitioning = false
      return Err(issue)
    }
    Ok(value) => value
  }
  let next : BackedPreparedRunAdmission[P] = {
    original: None,
    child,
    holder: Some(holder),
    cleanup_original: () => cleanup_backed_initialization_admission(initial),
    owner_retired: initial.owner_retired,
    transitioning: false,
    cleaned: false,
  }
  next.original = Some(next)
  owner.transferred = true
  owner.transitioning = false
  Ok((next, ledger, retirement, run_holder))
}

///|
fn[P] backed_prepared_run_original(
  owner : BackedPreparedRunAdmission[P],
) -> Result[Unit, ImportedChildLedgerIssue] {
  if !(owner.original is Some(original) && physical_equal(owner, original)) {
    return Err(ForeignOriginal)
  }
  if owner.transitioning {
    Err(Unknown)
  } else {
    Ok(())
  }
}

///|
pub fn[P] check_backed_prepared_run_admission(
  owner : BackedPreparedRunAdmission[P],
  prepared : P,
  ledger : Ledger,
) -> Result[Unit, ImportedChildLedgerIssue] {
  match check_backed_prepared_run_binding(owner, prepared, ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match check_imported_original_child_ledger(owner.child, ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match check_backed_prepared_run_binding(owner, prepared, ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  check_original_resources_mutable_current(ledger).map_err(issue => {
    Resource(issue)
  })
}

///|
fn[P] check_backed_prepared_run_binding(
  owner : BackedPreparedRunAdmission[P],
  prepared : P,
  ledger : Ledger,
) -> Result[Unit, ImportedChildLedgerIssue] {
  match backed_prepared_run_original(owner) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if owner.cleaned || (owner.owner_retired)() {
    return Err(Unavailable)
  }
  guard owner.holder is Some(holder) &&
    preparation_body_borrow_value(holder) is Some(body) &&
    physical_equal(body, prepared) &&
    !preparation_body_retirement_started(holder) &&
    owner.child.ledger is Some(original) &&
    physical_equal(original, ledger) else {
    return Err(ForeignOriginal)
  }
  Ok(())
}

///|
pub fn[P] check_backed_preparation_cleanup_original(
  owner : BackedPreparedRunAdmission[P],
  ledger : Ledger,
) -> Result[Unit, ImportedChildLedgerIssue] {
  match backed_prepared_run_original(owner) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if owner.cleaned || !owner.child.taken {
    return Err(Unavailable)
  }
  guard owner.child.ledger is Some(original) &&
    physical_equal(original, ledger) &&
    ledger.imported_child is Some(origin) &&
    physical_equal(origin, owner.child.origin) else {
    return Err(ForeignOriginal)
  }
  check_imported_child_ledger(ledger).map_err(issue => Resource(issue))
}

///|
pub fn[P] backed_preparation_usage_isolated(
  owner : BackedPreparedRunAdmission[P],
  ledger : Ledger,
) -> Bool {
  guard check_backed_preparation_cleanup_original(owner, ledger) is Ok(_) &&
    owner.holder is Some(holder) else {
    return false
  }
  preparation_body_usage_isolated(holder, ledger)
}

///|
/// Return the admission's original heavy holder only after the same capacity
/// enters retirement. Other live borrowers keep their own original aliases.
pub fn[P] release_backed_preparation_holder(
  owner : BackedPreparedRunAdmission[P],
) -> Result[Bool, ImportedChildLedgerIssue] {
  match backed_prepared_run_original(owner) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard owner.holder is Some(holder) else { return Ok(false) }
  if !preparation_body_retirement_started(holder) {
    return Err(Unavailable)
  }
  owner.holder = None
  return_preparation_body_borrow(holder).map_err(issue => {
    match issue {
      Resource(issue) => ImportedChildLedgerIssue::Resource(issue)
      _ => Unavailable
    }
  })
}

///|
/// Same existing physical cleanup. A returned body/zero usage is not an ACK;
/// the original backing issuer must still retire its exact live projection.
pub fn[P] cleanup_backed_prepared_run_admission(
  owner : BackedPreparedRunAdmission[P],
) -> Result[Unit, ImportedChildLedgerIssue] {
  match backed_prepared_run_original(owner) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if owner.cleaned {
    return Ok(())
  }
  if owner.holder is Some(_) {
    return Err(Unavailable)
  }
  owner.transitioning = true
  let result = (owner.cleanup_original)()
  owner.transitioning = false
  if result is Ok(_) {
    owner.cleaned = true
  }
  result
}
