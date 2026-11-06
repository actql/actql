///|
extern "C" fn retained_execution_control_scope_clear_ffi() -> Int = "actql_bootstrap_control_scope_clear"

///|
pub(all) enum InstalledArenaRetainedExecutionIssue {
  Domain(@bootstrap.NativeBackedExecutionIssue)
  Child(@resources.ImportedChildLedgerIssue)
  Initialization(@bootstrap.NativeBackedInitializationIssue)
}

///|
/// The same existing Host's in-process business domain. Its actual Read
/// allocator context and original delegated Ledger stay joined through cleanup;
/// this is neither the command's static Read nor a synthetic worker channel.
struct InstalledArenaRetainedExecution {
  domain : InstalledArenaDomain
  mut live : @bootstrap.NativeBackedLiveChild[
    InstalledArenaHost,
    InstalledArenaDomain,
    InstalledArenaRetainedExecution,
  ]?
  mut frame : @resources.ImportedChildLedger?
  mut ledger : @resources.Ledger?
  mut initialization_cleanup : (() -> Result[
    Unit,
    @bootstrap.NativeBackedInitializationIssue,
  ])?
  mut owns_read : Bool
  mut child_started : Bool
  mut active : Bool
  mut scope_failed : Bool
  mut physical_retired : Bool
  mut reported : Bool
  mut ready : Bool
  mut closing : Bool
  mut closed : Bool
}

///|
pub(all) enum InstalledArenaRetainedExecutionAcquisition {
  ReadyRetainedExecution(InstalledArenaRetainedExecution)
  PendingRetainedExecution(
    InstalledArenaRetainedExecution,
    InstalledArenaRetainedExecutionIssue
  )
}

///|
/// Trusted installed assembly only, after the distinct physical business domain
/// and complete simultaneous candidate were supplied. No limit DATA, callback,
/// bootstrap scalar or new parent reservation enters this original issuer.
pub fn InstalledArenaHost::prepare_domain_retained_execution(
  self : InstalledArenaHost,
  domain : InstalledArenaDomain,
) -> Result[
  InstalledArenaRetainedExecutionAcquisition,
  InstalledArenaRetainedExecutionIssue,
] {
  let record = match self.prepare_domain_retained_execution_record(domain) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  match record.prepare_original() {
    Err(issue) => Ok(PendingRetainedExecution(record, issue))
    Ok(_) => {
      record.ready = true
      Ok(ReadyRetainedExecution(record))
    }
  }
}

///|
fn InstalledArenaHost::prepare_domain_retained_execution_record(
  self : InstalledArenaHost,
  domain : InstalledArenaDomain,
) -> Result[
  InstalledArenaRetainedExecution,
  InstalledArenaRetainedExecutionIssue,
] {
  match self.require_domain_read_current(domain) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  if domain.retained_execution is Some(_) ||
    domain.original_read is Some(_) ||
    domain.crypto_component is Some(_) ||
    domain.sqlite_library is Some(_) ||
    domain.live_channel is Some(_) {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.AlreadyConsumed)))
  }
  let record : InstalledArenaRetainedExecution = {
    domain,
    live: None,
    frame: None,
    ledger: None,
    initialization_cleanup: None,
    owns_read: false,
    child_started: false,
    active: false,
    scope_failed: false,
    physical_retired: false,
    reported: false,
    ready: false,
    closing: false,
    closed: false,
  }
  // The original domain retains every partial stage before admission/start.
  domain.retained_execution = Some(record)
  Ok(record)
}

///|
pub(all) enum InstalledArenaRequestExecutionAcquisition[I] {
  ReadyRequestExecution(
    InstalledArenaRetainedExecution,
    @resources.BackedPreparationAdmission[I]
  )
  PendingRequestExecution(
    InstalledArenaRetainedExecution,
    InstalledArenaRetainedExecutionIssue
  )
}

///|
/// Select the Request before this original frame starts. The same registered
/// Native execution carrier retains every pending stage and its physical ACK.
pub fn[I] InstalledArenaHost::prepare_domain_retained_request_execution(
  self : InstalledArenaHost,
  domain : InstalledArenaDomain,
  input : I,
  budget : @bootstrap.NativeBackedInitializationBudget,
) -> Result[
  InstalledArenaRequestExecutionAcquisition[I],
  InstalledArenaRetainedExecutionIssue,
] {
  let record = match self.prepare_domain_retained_execution_record(domain) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let original = domain.domain.unwrap()
  let live = match
    domain.backing.prepare_backed_initialization_live_child(
      self, original, domain, input,
    ) {
    Err(issue) => return Ok(PendingRequestExecution(record, Domain(issue)))
    Ok(@bootstrap.LiveChildPending(live, issue)) => {
      record.owns_read = true
      record.initialization_cleanup = Some(() => {
        domain.backing.close_backed_preparation(self, live)
      })
      return Ok(PendingRequestExecution(record, Domain(issue)))
    }
    Ok(@bootstrap.LiveChildReady(live)) => live
  }
  record.owns_read = true
  record.initialization_cleanup = Some(() => {
    domain.backing.close_backed_preparation(self, live)
  })
  let initial = match
    domain.backing.initialize_backed_request_preparation(
      self, live, input, budget,
    ) {
    Err(issue) =>
      return Ok(PendingRequestExecution(record, Initialization(issue)))
    Ok(value) => value
  }
  let frame = match
    @resources.backed_preparation_original_frame(initial, input) {
    Err(issue) => return Ok(PendingRequestExecution(record, Child(issue)))
    Ok(value) => value
  }
  record.frame = Some(frame)
  record.child_started = true
  let ledger = match
    domain.backing.borrow_initialized_preparation_ledger(self, live, input) {
    Err(issue) =>
      return Ok(PendingRequestExecution(record, Initialization(issue)))
    Ok(value) => value
  }
  record.ledger = Some(ledger)
  record.ready = true
  Ok(ReadyRequestExecution(record, initial))
}

///|
fn InstalledArenaRetainedExecution::prepare_original(
  self : InstalledArenaRetainedExecution,
) -> Result[Unit, InstalledArenaRetainedExecutionIssue] {
  match self.prepare_original_frame() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let frame = self.frame.unwrap()
  match @resources.start_imported_child_ledger(frame) {
    Err(issue) => return Err(Child(issue))
    Ok(_) => self.child_started = true
  }
  match @resources.take_imported_original_child_ledger(frame) {
    Err(issue) => return Err(Child(issue))
    Ok(ledger) => self.ledger = Some(ledger)
  }
  Ok(())
}

///|
// Retain the same actual Native frame before start/take. This private boundary
// creates no preparation admission or second resource owner. Its caller owns
// the original pending cleanup even when acquisition or admission refuses.
fn InstalledArenaRetainedExecution::prepare_original_frame(
  self : InstalledArenaRetainedExecution,
) -> Result[Unit, InstalledArenaRetainedExecutionIssue] {
  let domain = self.domain
  let host = domain.host
  let backing = domain.backing
  let original = domain.domain.unwrap()
  let live = match
    backing.prepare_backed_read_live_child(host, original, domain, self) {
    Err(issue) => return Err(Domain(issue))
    Ok(@bootstrap.LiveChildPending(live, issue)) => {
      self.live = Some(live)
      self.owns_read = true
      return Err(Domain(issue))
    }
    Ok(@bootstrap.LiveChildReady(live)) => live
  }
  self.live = Some(live)
  self.owns_read = true
  match backing.admit_backed_live_child(host, live, self) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  let frame = match
    backing.prepare_backed_original_read_ledger(host, live, self) {
    Err(@bootstrap.Domain(issue)) => return Err(Domain(issue))
    Err(@bootstrap.Child(issue)) => return Err(Child(issue))
    Ok(value) => value
  }
  self.frame = Some(frame)
  Ok(())
}

///|
fn InstalledArenaHost::original_retained_execution(
  self : InstalledArenaHost,
  record : InstalledArenaRetainedExecution,
) -> Result[Unit, InstalledArenaRetainedExecutionIssue] {
  let domain = record.domain
  if !physical_equal(domain.host, self) ||
    domain.closed ||
    !self.domains.any(original => physical_equal(original, domain)) ||
    !(domain.retained_execution is Some(original) &&
    physical_equal(original, record)) {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal)))
  }
  // Identity-only cleanup also covers a refused prepare that never acquired
  // a physical domain/context. Normal entry separately requires actual current.
  Ok(())
}

///|
pub fn InstalledArenaHost::require_domain_retained_execution_current(
  self : InstalledArenaHost,
  record : InstalledArenaRetainedExecution,
) -> Result[Unit, InstalledArenaRetainedExecutionIssue] {
  match self.original_retained_execution(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !record.ready || record.closing || record.closed || record.scope_failed {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.Closing)))
  }
  match self.require_domain_read_current(record.domain) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  guard record.ledger is Some(ledger) else {
    return Err(Child(@resources.Unavailable))
  }
  @resources.check_original_resources_mutable(ledger).map_err(issue => {
    Child(@resources.Resource(issue))
  })
}

///|
/// Each serial scope uses this same original physical allocator. Leaving a
/// phase does not settle/refill it or issue another child Ledger.
pub fn InstalledArenaHost::enter_domain_retained_execution(
  self : InstalledArenaHost,
  record : InstalledArenaRetainedExecution,
) -> Result[Unit, InstalledArenaRetainedExecutionIssue] {
  match self.require_domain_retained_execution_current(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if record.active {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.ReadersPending)))
  }
  record.active = true
  match self.enter_domain_read(record.domain) {
    Err(issue) => {
      record.scope_failed = true
      Err(Domain(issue))
    }
    Ok(_) => Ok(())
  }
}

///|
/// Borrow exactly the already taken Ledger only inside its actual entered C
/// frame. Existing Common consumers keep its nominal/current restrictions;
/// this projection supplies no Account or Result publication authority.
pub fn InstalledArenaHost::borrow_domain_retained_execution_ledger(
  self : InstalledArenaHost,
  record : InstalledArenaRetainedExecution,
) -> Result[@resources.Ledger, InstalledArenaRetainedExecutionIssue] {
  match self.require_domain_retained_execution_current(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !record.active {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.ReadersPending)))
  }
  let domain = record.domain
  match
    domain.backing.require_backed_read_context_entered(
      self,
      domain.domain.unwrap(),
      domain,
    ) {
    Err(issue) => Err(Domain(issue))
    Ok(_) => Ok(record.ledger.unwrap())
  }
}

///|
/// Same-original leave remains available after a normal current refusal.
/// Failure retains its original active/cleanup duty; it never resets the use.
pub fn InstalledArenaHost::leave_domain_retained_execution(
  self : InstalledArenaHost,
  record : InstalledArenaRetainedExecution,
) -> Result[Unit, InstalledArenaRetainedExecutionIssue] {
  match self.original_retained_execution(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if record.closed || !record.active {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.ReadersPending)))
  }
  match self.leave_domain_read(record.domain) {
    Err(issue) => {
      record.scope_failed = true
      Err(Domain(issue))
    }
    Ok(_) => {
      record.active = false
      Ok(())
    }
  }
}

///|
/// Complete only a failed entry's original flight after actual non-entry (or
/// its recorded owned-scope unwind) is confirmed. An entered frame still needs
/// the ordinary original leave. Failure stays sticky and normal use is spent.
pub fn InstalledArenaHost::finish_domain_retained_execution_failed_entry_cleanup(
  self : InstalledArenaHost,
  record : InstalledArenaRetainedExecution,
) -> Result[Unit, InstalledArenaRetainedExecutionIssue] {
  match self.original_retained_execution(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if record.closed ||
    record.physical_retired ||
    !record.owns_read ||
    !record.scope_failed ||
    !record.active {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.ReadersPending)))
  }
  record.closing = true
  record.ready = false
  let domain = record.domain
  match
    domain.backing.finish_backed_failed_read_entry_cleanup(
      self,
      domain.domain.unwrap(),
      domain,
    ) {
    Err(issue) => Err(Domain(issue))
    Ok(_) => {
      record.active = false
      Ok(())
    }
  }
}

///|
/// Reenter only the same retained original to retire its outputs after failure
/// or close. This monotonically stops normal use; no Ledger or business call
/// may be borrowed from the cleanup frame. Actual leave remains separate.
pub fn InstalledArenaHost::enter_domain_retained_execution_cleanup(
  self : InstalledArenaHost,
  record : InstalledArenaRetainedExecution,
) -> Result[Unit, InstalledArenaRetainedExecutionIssue] {
  match self.original_retained_execution(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if record.closed ||
    record.physical_retired ||
    !record.owns_read ||
    record.active {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.ReadersPending)))
  }
  record.closing = true
  record.ready = false
  record.active = true
  match self.enter_domain_read_cleanup(record.domain) {
    Err(issue) => {
      record.scope_failed = true
      Err(Domain(issue))
    }
    Ok(_) => Ok(())
  }
}

///|
/// Consumers first retire their own retained outputs/Store and managed aliases.
/// C-context ACK is independent of the original report, parent loan and FD.
pub fn InstalledArenaHost::close_domain_retained_execution(
  self : InstalledArenaHost,
  record : InstalledArenaRetainedExecution,
) -> Result[Unit, InstalledArenaRetainedExecutionIssue] {
  match self.original_retained_execution(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if record.closed {
    return Ok(())
  }
  record.closing = true
  record.ready = false
  if record.active {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.ReadersPending)))
  }
  if !record.owns_read {
    record.closed = true
    return Ok(())
  }
  let domain = record.domain
  let original = domain.domain.unwrap()
  if record.initialization_cleanup is Some(cleanup) {
    match cleanup() {
      Err(issue) => return Err(Initialization(issue))
      Ok(_) => ()
    }
    record.initialization_cleanup = None
    record.physical_retired = true
    record.reported = true
    record.ledger = None
    record.frame = None
    record.closed = true
    return Ok(())
  }
  if record.frame is Some(frame) {
    match @resources.stop_imported_child_ledger(frame) {
      Err(issue) => return Err(Child(issue))
      Ok(_) => ()
    }
  }
  if !record.physical_retired {
    // Snapshot replacement must allocate in the existing outer control, never
    // in this child or a sibling Read. Logical stop supplies no physical ACK.
    if retained_execution_control_scope_clear_ffi() != 1 {
      return Err(Domain(@bootstrap.Bootstrap(@bootstrap.ReadersPending)))
    }
    if record.frame is Some(frame) {
      match @resources.relocate_imported_child_cleanup_usage(frame) {
        Err(issue) => return Err(Child(issue))
        Ok(_) => ()
      }
    }
    let close = domain.backing.close_backed_read_context(self, original, domain)
    match
      domain.backing.require_backed_read_context_retired(self, original, domain) {
      Err(_) =>
        return match close {
          Err(issue) => Err(Domain(issue))
          Ok(_) => Err(Domain(@bootstrap.Bootstrap(@bootstrap.ReadersPending)))
        }
      Ok(_) => record.physical_retired = true
    }
  }
  if !record.reported && record.child_started && record.frame is Some(frame) {
    match @resources.report_imported_child_ledger(frame) {
      Err(issue) => return Err(Child(issue))
      Ok(_) => ()
    }
    record.reported = true
  }
  if record.live is Some(live) {
    match
      domain.backing.retire_backed_live_child_after_owner_ack(
        self, live, record,
      ) {
      Err(issue) => return Err(Domain(issue))
      Ok(_) => ()
    }
    record.live = None
  }
  match domain.backing.close_backed_read_context(self, original, domain) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  record.ledger = None
  record.frame = None
  record.closed = true
  Ok(())
}

///|
/// Fixed coordinator observation only. Both the original nominal active latch
/// and actual physical frame must agree; an Err is never an inactive result.
pub fn InstalledArenaHost::observe_domain_retained_execution_scope(
  self : InstalledArenaHost,
  record : InstalledArenaRetainedExecution,
) -> Result[
  @bootstrap.NativeBackedReadScope,
  InstalledArenaRetainedExecutionIssue,
] {
  match self.require_domain_retained_execution_current(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let domain = record.domain
  let scope = match
    domain.backing.observe_backed_read_context_scope(
      self,
      domain.domain.unwrap(),
      domain,
    ) {
    Err(issue) => return Err(Domain(issue))
    Ok(value) => value
  }
  if record.active != (scope == @bootstrap.BackedReadEntered) {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.ReadersPending)))
  }
  Ok(scope)
}

///|
/// The fixed cleanup consumer can inspect an already-closing original. A
/// failed observation is never inactivity; normal current and Ledger borrowing
/// remain unavailable, and the actual scope must agree with its active latch.
pub fn InstalledArenaHost::observe_domain_retained_execution_cleanup_scope(
  self : InstalledArenaHost,
  record : InstalledArenaRetainedExecution,
) -> Result[
  @bootstrap.NativeBackedReadScope,
  InstalledArenaRetainedExecutionIssue,
] {
  match self.original_retained_execution(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !record.closing ||
    record.closed ||
    record.physical_retired ||
    !record.owns_read {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.Closing)))
  }
  let domain = record.domain
  let scope = match
    domain.backing.observe_backed_read_cleanup_scope(
      self,
      domain.domain.unwrap(),
      domain,
    ) {
    Err(issue) => return Err(Domain(issue))
    Ok(value) => value
  }
  if record.active != (scope == @bootstrap.BackedReadEntered) {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.ReadersPending)))
  }
  Ok(scope)
}
