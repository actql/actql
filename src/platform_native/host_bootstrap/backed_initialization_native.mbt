///|
// Control DATA on the existing NativeBackedLiveChild, not another resource
// owner. No reference to this private state can admit a child or supply ACK.
priv struct NativeBackedInitialization[T, C, I] {
  original : NativeBackedLiveChild[T, C, I]
  mut initial : @resources.BackedInitializationAdmission[I]?
  mut frame : @resources.ImportedChildLedger?
  mut ledger : @resources.Ledger?
  mut bootstrap : @resources.CapacityReservation?
  mut inventory : @resources.OriginalLedgerIdentity?
  mut transitioning : Bool
  mut start_attempted : Bool
  mut started : Bool
  mut physical_retired : Bool
  mut inventory_finished : Bool
  mut reported : Bool
  mut closed : Bool
  // Original failed acquisition DATA, never a retry or resource grant.
  mut window_issue : NativeBackedExecutionIssue?
}

///|
/// Trusted installed quote for this bootstrap control only. These bytes are
/// charged to the SAME admitted child allowance, not granted as new limits.
/// The selected Source must still quote and grow its original working token.
pub(all) struct NativeBackedInitializationBudget {
  bootstrap_retained : Int64
  bootstrap_execution : Int64
}

///|
pub(all) enum NativeBackedInitializationIssue {
  Domain(NativeBackedExecutionIssue)
  Child(@resources.ImportedChildLedgerIssue)
  Inventory(@resources.OriginalReadIssue)
  Quiescence(@resources.LedgerContinuationIssue)
}

///|
/// Actual Native assembly of the fresh Initialization-purpose child. The
/// caller already retains record, including a refused/partial acquisition.
/// Every acquired value is stored there before the next fallible operation.
/// No Read conversion, second context, replacement Ledger or cleanup callback
/// enters this path. All bootstrap controls allocate in the outer lifetime.
pub fn[T, C, I] NativeHostBootstrap::initialize_backed_preparation(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChild[T, C, I],
  input : I,
  budget : NativeBackedInitializationBudget,
) -> Result[
  @resources.BackedInitializationAdmission[I],
  NativeBackedInitializationIssue,
] {
  self.initialize_backed_preparation_selected(
    original, record, input, budget, false,
  )
}

///|
// Select once before frame construction. Source owns its existing standalone
// bootstrap; Request owns the first preparation reservation/census instead.
// Both use the same Native control carrier and physical retirement sequence.
fn[T, C, I] NativeHostBootstrap::initialize_backed_preparation_selected(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChild[T, C, I],
  input : I,
  budget : NativeBackedInitializationBudget,
  request : Bool,
) -> Result[
  @resources.BackedInitializationAdmission[I],
  NativeBackedInitializationIssue,
] {
  match self.original_live_child(original, record, input) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  if record.purpose != Initialization {
    return Err(Domain(Bootstrap(ForeignOriginal)))
  }
  if record.initialization is Some(_) {
    return Err(Domain(Bootstrap(AlreadyConsumed)))
  }
  if budget.bootstrap_retained <= 0L || budget.bootstrap_execution <= 0L {
    return Err(Inventory(@resources.InvalidBootstrap))
  }
  if initialization_control_scope_clear_ffi() != 1 {
    return Err(Domain(Bootstrap(ReadersPending)))
  }
  let state : NativeBackedInitialization[T, C, I] = {
    original: record,
    initial: None,
    frame: None,
    ledger: None,
    bootstrap: None,
    inventory: None,
    transitioning: true,
    start_attempted: false,
    started: false,
    physical_retired: false,
    inventory_finished: false,
    reported: false,
    closed: false,
    window_issue: None,
  }
  record.initialization = Some(state)
  let outcome = self.initialize_backed_preparation_original(
    original, record, input, budget, state, request,
  )
  state.transitioning = false
  outcome
}

///|
/// The ordinary Request consumes this SAME initialized physical child once.
/// The existing Native carrier keeps its physical frame/partial cleanup and
/// report. The Request funds and owns its FIRST reservation/census; it never
/// converts the Source initializer's standalone bootstrap or resets history.
pub fn[T, C, I] NativeHostBootstrap::initialize_backed_request_preparation(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChild[T, C, I],
  input : I,
  budget : NativeBackedInitializationBudget,
) -> Result[
  @resources.BackedPreparationAdmission[I],
  NativeBackedInitializationIssue,
] {
  let initial = match
    self.initialize_backed_preparation_selected(
      original, record, input, budget, true,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  @resources.prepare_initialized_backed_preparation_admission(initial, input).map_err(issue => {
      Child(issue)
    },
  )
}

///|
/// Trusted Native issuer view of its SAME retained frame. Request adoption
/// does not replace this physical owner's Ledger or after-owner-ACK duties.
pub fn[T, C, I] NativeHostBootstrap::borrow_initialized_preparation_ledger(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChild[T, C, I],
  input : I,
) -> Result[@resources.Ledger, NativeBackedInitializationIssue] {
  match self.original_live_child(original, record, input) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  guard record.initialization is Some(state) &&
    !state.transitioning &&
    state.started &&
    !state.closed &&
    state.ledger is Some(ledger) &&
    state.frame is Some(frame) else {
    return Err(Domain(Bootstrap(Unavailable)))
  }
  match @resources.check_imported_original_child_ledger(frame, ledger) {
    Err(issue) => return Err(Child(issue))
    Ok(_) => ()
  }
  match
    self.require_backed_read_context_current(
      original,
      record.domain,
      record.child,
    ) {
    Err(issue) => Err(Domain(issue))
    Ok(_) => Ok(ledger)
  }
}

///|
fn[T, C, I] NativeHostBootstrap::initialize_backed_preparation_original(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChild[T, C, I],
  input : I,
  budget : NativeBackedInitializationBudget,
  state : NativeBackedInitialization[T, C, I],
  request : Bool,
) -> Result[
  @resources.BackedInitializationAdmission[I],
  NativeBackedInitializationIssue,
] {
  match self.admit_backed_live_child(original, record, input) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  // The same physical issuer binds this optional duty before frame creation.
  // Its closure/captures stay in the existing outer initialization envelope.
  let acquire_window : ((Int64, Int64) -> Result[Unit, @resources.LedgerIssue])? = if request &&
    record.domain.view.loan.initial_window is Some(_) {
    Some((retained, execution) => {
      match
        self.prepare_initialized_working_window(
          original, record, input, retained, execution,
        ) {
        Ok(_) => Ok(())
        Err(issue) => {
          state.window_issue = Some(issue)
          Err(@resources.ChildFundingUnavailable)
        }
      }
    })
  } else {
    None
  }
  let initial = match
    self.prepare_backed_original_initialization_admission(
      original,
      record,
      input,
      acquire_window~,
    ) {
    Err(Domain(issue)) => return Err(Domain(issue))
    Err(Child(issue)) => return Err(Child(issue))
    Ok(value) => value
  }
  state.initial = Some(initial)
  let frame = match
    @resources.backed_initialization_original_frame(initial, input) {
    Err(issue) => return Err(Child(issue))
    Ok(value) => value
  }
  state.frame = Some(frame)
  state.start_attempted = true
  let ledger = match @resources.start_backed_initialization_admission(initial) {
    Err(issue) => return Err(Child(issue))
    Ok(value) => value
  }
  state.ledger = Some(ledger)
  state.started = true
  if request {
    // Native initializer controls are in their existing outer control scope.
    // Before any input/Source payload the same retained Request reserves its
    // complete fixed entrance and grows each variable constructor phase.
    // Installing Source's separate bootstrap here would make that pristine
    // first reservation impossible; never settle/reset it as a workaround.
    match
      self.require_backed_read_context_current(
        original,
        record.domain,
        record.child,
      ) {
      Err(issue) => return Err(Domain(issue))
      Ok(_) => return Ok(initial)
    }
  }
  let bootstrap = match
    @resources.reserve_capacity(
      ledger,
      budget.bootstrap_retained,
      budget.bootstrap_execution,
    ) {
    Err(issue) => return Err(Inventory(@resources.Resource(issue)))
    Ok(value) => value
  }
  state.bootstrap = Some(bootstrap)
  // This initializer creates exactly one working reservation, initially zero
  // bytes, and no holding or delegated child. Its Source successor continues
  // that same token. This is not a census for an unrelated full Source recipe.
  let inventory = match
    @resources.begin_original_ledger_inventory(ledger, bootstrap, 1, 0, 0) {
    Err(issue) => return Err(Inventory(issue))
    Ok(value) => value
  }
  state.inventory = Some(inventory)
  match
    self.require_backed_read_context_current(
      original,
      record.domain,
      record.child,
    ) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  Ok(initial)
}

///|
/// The same record remains a cleanup carrier after logical stop or failed
/// construction. This identity check admits no new work or replacement input.
fn[T, C, I] NativeHostBootstrap::original_initialization_cleanup(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChild[T, C, I],
) -> Result[
  NativeBackedInitialization[T, C, I],
  NativeBackedInitializationIssue,
] {
  if !physical_equal(record.owner, self) || record.purpose != Initialization {
    return Err(Domain(Bootstrap(ForeignOriginal)))
  }
  guard record.initialization is Some(state) &&
    physical_equal(state.original, record) else {
    return Err(Domain(Bootstrap(ForeignOriginal)))
  }
  self
  .original_domain_carrier(original, record.domain, record.child)
  .map(_ => state)
  .map_err(issue => Domain(issue))
}

///|
/// Call only after the actual constructor/Source children and aliases unwind.
/// The C close/retired observation, not a caller Boolean or Host close probe,
/// authorizes census settlement and the original report. Pending stages retain
/// the same fields; neither failed start nor a lost report is replayed.
pub fn[T, C, I] NativeHostBootstrap::close_backed_preparation(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChild[T, C, I],
) -> Result[Unit, NativeBackedInitializationIssue] {
  if record.initialization is None {
    if !(record.original is Some(selected) && physical_equal(selected, record)) ||
      !physical_equal(record.owner, self) ||
      record.purpose != Initialization {
      return Err(Domain(Bootstrap(ForeignOriginal)))
    }
    match self.original_domain_carrier(original, record.domain, record.child) {
      Err(issue) => return Err(Domain(issue))
      Ok(_) => ()
    }
    if record.retired {
      return Ok(())
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
      Err(issue) =>
        return match closed {
          Err(primary) => Err(Domain(primary))
          Ok(_) => Err(Domain(issue))
        }
      Ok(_) => ()
    }
    guard record.runtime is Some(input) else {
      return Err(Domain(Bootstrap(Unavailable)))
    }
    return self
      .retire_backed_live_child_after_owner_ack(original, record, input)
      .map_err(issue => Domain(issue))
  }
  let state = match self.original_initialization_cleanup(original, record) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  if state.closed {
    return Ok(())
  }
  if state.transitioning {
    return Err(Domain(Bootstrap(ReadersPending)))
  }
  state.transitioning = true
  let outcome = self.close_backed_preparation_original(original, record, state)
  state.transitioning = false
  outcome
}

///|
fn[T, C, I] NativeHostBootstrap::close_backed_preparation_original(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChild[T, C, I],
  state : NativeBackedInitialization[T, C, I],
) -> Result[Unit, NativeBackedInitializationIssue] {
  // The Core start stores its Ledger before take's fallible current check.
  // If that check refused, Native has no successfully taken Ledger for
  // relocation/census. Keep the published original pending; never retry take,
  // reconstruct its Ledger, close as a probe, or report invented zero usage.
  if !record.retired &&
    state.start_attempted &&
    !state.started &&
    state.initial is Some(initial) {
    let published = match
      @resources.backed_initialization_ledger_published(
        initial,
        record.runtime.unwrap(),
      ) {
      Err(issue) => return Err(Child(issue))
      Ok(value) => value
    }
    if published {
      return Err(Inventory(@resources.CleanupPending))
    }
  }
  if state.frame is Some(frame) {
    match @resources.stop_imported_child_ledger(frame) {
      Err(issue) => return Err(Child(issue))
      Ok(_) => ()
    }
  }
  if !state.physical_retired {
    if initialization_control_scope_clear_ffi() != 1 {
      return Err(Domain(Bootstrap(ReadersPending)))
    }
    state.window_issue = state.window_issue.map(copy_native_working_issue_data)
    if state.started && state.frame is Some(frame) {
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
  if !state.inventory_finished {
    if state.inventory is Some(_) && state.ledger is Some(ledger) {
      match @resources.finish_original_ledger_inventory(ledger, true) {
        Err(issue) => return Err(Inventory(issue))
        Ok(false) => return Err(Inventory(@resources.CleanupPending))
        Ok(true) => ()
      }
    } else if state.bootstrap is Some(bootstrap) && state.ledger is Some(ledger) {
      match @resources.settle_capacity(ledger, bootstrap) {
        Err(issue) => return Err(Inventory(@resources.Resource(issue)))
        Ok(_) => ()
      }
    }
    state.inventory_finished = true
  }
  if state.started && !state.reported && state.frame is Some(frame) {
    guard state.ledger is Some(ledger) else {
      return Err(Inventory(@resources.CleanupPending))
    }
    // Use Core's complete logical-quiescence/current contract, including
    // zero-byte tokens and delegated quantities. This temporary control DATA
    // is discarded; it neither replaces the Ledger nor resumes any work.
    match @resources.capture_quiescent_ledger_state(ledger) {
      Err(issue) => return Err(Quiescence(issue))
      Ok(_) => ()
    }
    match @resources.report_imported_child_ledger(frame) {
      Err(issue) => return Err(Child(issue))
      Ok(_) => state.reported = true
    }
  }
  if !record.retired {
    guard record.runtime is Some(input) else {
      return Err(Domain(Bootstrap(ForeignOriginal)))
    }
    match
      self.retire_backed_live_child_after_owner_ack(original, record, input) {
      Err(issue) => return Err(Domain(issue))
      Ok(_) => ()
    }
  }
  if state.initial is Some(initial) {
    match @resources.cleanup_backed_initialization_admission(initial) {
      Err(issue) => return Err(Child(issue))
      Ok(_) => ()
    }
  }
  // The Common read-use return can have remained pending on this exact live
  // access. Retry only that return after its owner retirement, not C startup.
  match self.close_backed_read_context(original, record.domain, record.child) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  state.initial = None
  state.frame = None
  state.ledger = None
  state.bootstrap = None
  state.inventory = None
  state.closed = true
  Ok(())
}

///|
extern "C" fn initialization_control_scope_clear_ffi() -> Int = "actql_bootstrap_control_scope_clear"

///|
/// Actual initialized Native caller only. This covers the SAME acquired pool
/// before a canonical reservation; it claims no contiguous constructor span.
/// Raw Reader/String/array geometry remains a separate physical obligation.
pub fn[T, C, I] NativeHostBootstrap::prepare_initialized_working_window(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChild[T, C, I],
  input : I,
  retained : Int64,
  execution : Int64,
) -> Result[Unit, NativeBackedExecutionIssue] {
  match self.original_live_child(original, record, input) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard record.purpose == Initialization &&
    record.initialization is Some(state) &&
    physical_equal(state.original, record) &&
    state.started &&
    !state.transitioning &&
    !state.closed &&
    !state.physical_retired &&
    record.projection is Some(projection) else {
    return Err(Bootstrap(Unavailable))
  }
  if state.window_issue is Some(issue) {
    return Err(issue)
  }
  match
    @resources.check_backed_original_child_window_demand(
      projection, input, retained, execution,
    ) {
    Err(issue) => return Err(Accounting(issue))
    Ok(_) => ()
  }
  let current = match
    @resources.read_backed_original_child_window_bytes(projection, input) {
    Err(issue) => return Err(Accounting(issue))
    Ok(value) => value
  }
  if retained < 0L ||
    execution < 0L ||
    execution > 9223372036854775807L - retained {
    return Err(Bootstrap(Unavailable))
  }
  let additional = Int64::max(0L, retained + execution - current)
  if additional == 0L {
    return Ok(())
  }
  match
    self.require_backed_read_context_current(
      original,
      record.domain,
      record.child,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match
    self.require_backed_read_context_entered(
      original,
      record.domain,
      record.child,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let acquired = self.grow_backed_domain_working(
    original,
    record.domain,
    record.child,
    0L,
    checked_read=true,
    minimum_usable_bytes=additional,
  )
  match acquired {
    Err(issue) => {
      state.window_issue = Some(issue)
      Err(issue)
    }
    Ok(_) =>
      self.require_backed_read_context_current(
        original,
        record.domain,
        record.child,
      )
  }
}

///|
// The same failure DATA moves to the existing outer cleanup lifetime. No
// nominal resource handle, receipt, status or physical acknowledgement is copied.
fn copy_native_working_issue_data(
  issue : NativeBackedExecutionIssue,
) -> NativeBackedExecutionIssue {
  match issue {
    Bootstrap(Physical(code)) => Bootstrap(Physical(code))
    Bootstrap(Resource(code)) => Bootstrap(Resource(code))
    Bootstrap(code) => Bootstrap(code)
    Accounting(@resources.Resource(code)) =>
      Accounting(@resources.Resource(code))
    Accounting(code) => Accounting(code)
  }
}
