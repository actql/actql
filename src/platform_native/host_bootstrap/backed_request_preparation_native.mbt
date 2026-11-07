///|
// Cleanup DATA retained by the existing physical live-child issuer. Common
// owns Request start, its original preparation census, and Run transfer.
priv struct NativeBackedRequestPreparation[T, C, I] {
  original : NativeBackedLiveChild[T, C, I]
  mut admission : @resources.BackedPreparationAdmission[I]?
  mut frame : @resources.ImportedChildLedger?
  mut transitioning : Bool
  mut closing : Bool
  mut physical_retired : Bool
  mut report_required : Bool?
  mut reported : Bool
  mut ready_for_owner_ack : Bool
  mut closed : Bool
}

///|
pub(all) enum NativeBackedRequestPreparationIssue {
  Domain(NativeBackedExecutionIssue)
  Child(@resources.ImportedChildLedgerIssue)
}

///|
/// Select a fresh Request purpose on the same current allocator context.
/// No Read, Initialization, or Worker child can be converted into a Request.
pub fn[T, C, I] NativeHostBootstrap::prepare_backed_request_live_child(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
  input : I,
) -> Result[
  NativeBackedLiveChildAcquisition[T, C, I],
  NativeBackedExecutionIssue,
] {
  // This record outlives the child allocator. Refuse before its one-shot
  // acquisition latch or any control can be allocated inside that child.
  if request_control_scope_ffi(self.backing, domain.physical) != 1 {
    return Err(Bootstrap(ReadersPending))
  }
  match self.require_backed_read_context_current(original, domain, child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  self.issue_backed_live_child_from_read(
    original,
    domain,
    child,
    input,
    Request,
  )
}

///|
/// Retain the same input-bound frame before Common's one-shot start. Native
/// controls are funded in the enclosing original lifetime: no bootstrap token
/// or Initialization census is inserted into the pristine Request Ledger.
pub fn[T, C, I] NativeHostBootstrap::prepare_backed_request_admission(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChild[T, C, I],
  input : I,
) -> Result[
  @resources.BackedPreparationAdmission[I],
  NativeBackedRequestPreparationIssue,
] {
  match self.original_live_child(original, record, input) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  if record.purpose != Request {
    return Err(Domain(Bootstrap(ForeignOriginal)))
  }
  if record.request_preparation is Some(_) {
    return Err(Domain(Bootstrap(AlreadyConsumed)))
  }
  if request_control_scope_ffi(self.backing, record.domain.physical) != 1 {
    return Err(Domain(Bootstrap(ReadersPending)))
  }
  let state : NativeBackedRequestPreparation[T, C, I] = {
    original: record,
    admission: None,
    frame: None,
    transitioning: true,
    closing: false,
    physical_retired: false,
    report_required: None,
    reported: false,
    ready_for_owner_ack: false,
    closed: false,
  }
  record.request_preparation = Some(state)
  let outcome = self.prepare_backed_request_admission_original(
    original, record, input, state,
  )
  state.transitioning = false
  outcome
}

///|
fn[T, C, I] NativeHostBootstrap::prepare_backed_request_admission_original(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChild[T, C, I],
  input : I,
  state : NativeBackedRequestPreparation[T, C, I],
) -> Result[
  @resources.BackedPreparationAdmission[I],
  NativeBackedRequestPreparationIssue,
] {
  match self.admit_backed_live_child(original, record, input) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  guard record.projection is Some(projection) else {
    return Err(Domain(Bootstrap(Unavailable)))
  }
  let admission = match
    @resources.prepare_backed_preparation_admission(projection, input) {
    Err(issue) => return Err(Child(issue))
    Ok(value) => value
  }
  state.admission = Some(admission)
  let frame = match
    @resources.backed_preparation_original_frame(admission, input) {
    Err(issue) => return Err(Child(issue))
    Ok(value) => value
  }
  state.frame = Some(frame)
  Ok(admission)
}

///|
/// Retire only the physical issuer's retained original. Request/Run must first
/// unwind their actual body, borrowers and children. Transfer does not require
/// re-taking an admission or replacing its frame. Failed physical close or a
/// lost report remains pending on this same record.
pub fn[T, C, I] NativeHostBootstrap::close_backed_request_preparation(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChild[T, C, I],
) -> Result[Unit, NativeBackedRequestPreparationIssue] {
  if !physical_equal(record.owner, self) || record.purpose != Request {
    return Err(Domain(Bootstrap(ForeignOriginal)))
  }
  guard record.request_preparation is Some(state) &&
    physical_equal(state.original, record) else {
    return Err(Domain(Bootstrap(ForeignOriginal)))
  }
  match self.original_domain_carrier(original, record.domain, record.child) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  if state.closed {
    return Ok(())
  }
  if state.transitioning {
    return Err(Domain(Bootstrap(ReadersPending)))
  }
  state.transitioning = true
  state.closing = true
  let outcome = self.close_backed_request_preparation_original(
    original, record, state,
  )
  state.transitioning = false
  outcome
}

///|
/// Observe the SAME Request frame inside its actual current physical scope.
/// The issuer retained it before Common start and keeps it across Run transfer.
/// This does not take/start/admit the frame or expose its Ledger. Callers must
/// still bind the frame to their original Common Source read before use.
pub fn[T, C, I] NativeHostBootstrap::borrow_backed_request_read_frame(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChild[T, C, I],
  input : I,
) -> Result[@resources.ImportedChildLedger, NativeBackedRequestPreparationIssue] {
  let state = match self.original_request_read_state(original, record, input) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  if state.closing {
    return Err(Domain(Bootstrap(Closing)))
  }
  guard state.frame is Some(frame) else {
    return Err(Child(@resources.Unavailable))
  }
  match self.backed_live_child_state(original, record, input) {
    Err(issue) => return Err(Domain(issue))
    Ok(@resources.LiveClosing) => return Err(Domain(Bootstrap(Closing)))
    Ok(@resources.LiveOpen) => ()
  }
  match
    self.require_backed_read_context_entered(
      original,
      record.domain,
      record.child,
    ) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  // Keep the exact retained tuple after the physical current boundary. Never
  // ask the transferred preparation admission to issue its frame again.
  match self.original_request_read_state(original, record, input) {
    Err(issue) => return Err(issue)
    Ok(selected) =>
      if !physical_equal(selected, state) || state.closing {
        return Err(Domain(Bootstrap(Closing)))
      }
  }
  guard state.frame is Some(selected) && physical_equal(selected, frame) else {
    return Err(Domain(Bootstrap(ForeignOriginal)))
  }
  Ok(frame)
}

///|
// Identity/custody only: ordinary currentness is deliberately separate, so
// stopped originals can still observe their own pending cleanup scope.
fn[T, C, I] NativeHostBootstrap::original_request_read_state(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChild[T, C, I],
  input : I,
) -> Result[
  NativeBackedRequestPreparation[T, C, I],
  NativeBackedRequestPreparationIssue,
] {
  match self.original_live_child(original, record, input) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  guard record.purpose == Request &&
    record.request_preparation is Some(state) &&
    physical_equal(state.original, record) else {
    return Err(Domain(Bootstrap(ForeignOriginal)))
  }
  if state.closed || state.physical_retired {
    return Err(Domain(Bootstrap(Unavailable)))
  }
  if state.transitioning {
    return Err(Domain(Bootstrap(ReadersPending)))
  }
  Ok(state)
}

///|
/// Observe cleanup entry on the same original Request after stop/refusal.
/// No frame, normal read permission, retirement, report or ACK is returned.
pub fn[T, C, I] NativeHostBootstrap::observe_backed_request_read_cleanup_scope(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChild[T, C, I],
  input : I,
) -> Result[NativeBackedReadScope, NativeBackedRequestPreparationIssue] {
  match self.original_request_read_state(original, record, input) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  self
  .observe_backed_read_cleanup_scope(original, record.domain, record.child)
  .map_err(issue => Domain(issue))
}

///|
fn[T, C, I] NativeHostBootstrap::close_backed_request_preparation_original(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChild[T, C, I],
  state : NativeBackedRequestPreparation[T, C, I],
) -> Result[Unit, NativeBackedRequestPreparationIssue] {
  // Keep a partially prepared admission reachable until its original frame is
  // retained. Never interpret a missing frame after admission as an unstarted
  // child that can be acknowledged without checking the same original.
  if state.frame is None && state.admission is Some(admission) {
    guard record.runtime is Some(input) else {
      return Err(Domain(Bootstrap(ForeignOriginal)))
    }
    match @resources.backed_preparation_original_frame(admission, input) {
      Err(issue) => return Err(Child(issue))
      Ok(frame) => state.frame = Some(frame)
    }
  }
  if state.frame is Some(frame) {
    match @resources.stop_imported_child_ledger(frame) {
      Err(issue) => return Err(Child(issue))
      Ok(_) => ()
    }
    if state.report_required is None {
      match @resources.imported_child_retirement_readiness(frame) {
        Err(issue) => return Err(Child(issue))
        Ok(value) => state.report_required = Some(value)
      }
    }
  }
  if !state.physical_retired {
    if request_control_scope_ffi(self.backing, record.domain.physical) != 1 {
      return Err(Domain(Bootstrap(ReadersPending)))
    }
    if state.report_required == Some(true) && state.frame is Some(frame) {
      match @resources.relocate_imported_child_cleanup_usage(frame) {
        Err(issue) => return Err(Child(issue))
        Ok(_) => ()
      }
    }
    let closed = self.close_backed_read_context(
      original,
      record.domain,
      record.child,
    )
    match
      self.require_backed_read_context_retired(
        original,
        record.domain,
        record.child,
      ) {
      Err(_) =>
        return match closed {
          Err(issue) => Err(Domain(issue))
          Ok(_) => Err(Domain(Bootstrap(ReadersPending)))
        }
      Ok(_) => state.physical_retired = true
    }
  }
  if state.report_required == Some(true) && !state.reported {
    guard state.frame is Some(frame) else {
      return Err(Child(@resources.Unavailable))
    }
    match @resources.report_imported_child_ledger(frame) {
      Err(issue) => return Err(Child(issue))
      Ok(_) => state.reported = true
    }
  }
  state.ready_for_owner_ack = true
  if !record.retired {
    guard record.runtime is Some(input) else {
      return Err(Domain(Bootstrap(ForeignOriginal)))
    }
    if record.access is None {
      // A refused access may return its Common read use in the first physical
      // close. That already-returned use is not an identity credential.
      match
        self.retire_refused_request_after_read_return(
          original, record, input, state,
        ) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
    } else {
      match
        self.retire_backed_live_child_after_owner_ack(original, record, input) {
        Err(issue) => return Err(Domain(issue))
        Ok(_) => ()
      }
    }
  }
  // Common Request or its transferred Run owns admission cleanup. Calling the
  // old admission here would fail after transfer and could lose the successor.
  if record.domain.read_use is Some(_) {
    match
      self.close_backed_read_context(original, record.domain, record.child) {
      Err(issue) => return Err(Domain(issue))
      Ok(_) => ()
    }
  }
  state.admission = None
  state.frame = None
  state.closed = true
  Ok(())
}

///|
fn[T, C, I] NativeHostBootstrap::retire_refused_request_after_read_return(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChild[T, C, I],
  input : I,
  state : NativeBackedRequestPreparation[T, C, I],
) -> Result[Unit, NativeBackedRequestPreparationIssue] {
  if !physical_equal(record.owner, self) ||
    record.purpose != Request ||
    !(record.original is Some(selected) && physical_equal(selected, record)) ||
    !(record.runtime is Some(selected) && physical_equal(selected, input)) ||
    !physical_equal(state.original, record) ||
    !state.physical_retired ||
    record.access is Some(_) ||
    record.projection is Some(_) ||
    state.admission is Some(_) ||
    state.frame is Some(_) {
    return Err(Domain(Bootstrap(ForeignOriginal)))
  }
  match
    self.require_backed_read_context_retired(
      original,
      record.domain,
      record.child,
    ) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  if record.domain.read_use is Some(_) {
    match
      self.close_backed_read_context(original, record.domain, record.child) {
      Err(issue) => return Err(Domain(issue))
      Ok(_) => ()
    }
  }
  // No Common live access or admission ever escaped this original record.
  // Its real context retirement and read-use return are both now observed.
  record.runtime = None
  record.original = None
  record.retired = true
  Ok(())
}
