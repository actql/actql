///|
priv enum NativeBackedLiveChildPurpose {
  Worker
  Read
  Initialization
  Request
} derive(Eq)

///|
/// Same parent domain and Common live access. R is an original installed
/// physical slot, not a wire pointer or a caller-supplied description. The
/// physical issuer binds its actual channel/VM/FD/domain before admission.
struct NativeBackedLiveChild[T, C, R] {
  mut original : NativeBackedLiveChild[T, C, R]?
  owner : NativeHostBootstrap[T]
  domain : NativeBackedExecutionDomain[T, C]
  child : C
  purpose : NativeBackedLiveChildPurpose
  mut runtime : R?
  mut access : @resources.BackedExecutionLiveAccess[
    NativeHostBootstrap[T],
    C,
    R,
  ]?
  mut projection : @resources.BackedExecutionLiveProjection[
    NativeHostBootstrap[T],
    C,
    R,
  ]?
  mut retired : Bool
  // Private initialization controls belong to this same physical owner.
  mut initialization : NativeBackedInitialization[T, C, R]?
  // A Request retains its original frame before Common starts it. This is
  // cleanup DATA on this same physical issuer, not another resource owner.
  mut request_preparation : NativeBackedRequestPreparation[T, C, R]?
}

///|
pub(all) enum NativeBackedLiveChildAcquisition[T, C, R] {
  LiveChildReady(NativeBackedLiveChild[T, C, R])
  LiveChildPending(NativeBackedLiveChild[T, C, R], NativeBackedExecutionIssue)
}

///|
/// Retain the original Common borrow before issuing one live access. This
/// creates no parent C read context, fresh Ledger, reservation or child VM.
/// Missing full bootstrap funding still refuses ordinary worker startup.
pub fn[T, C, R] NativeHostBootstrap::prepare_backed_live_child(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
  runtime : R,
) -> Result[
  NativeBackedLiveChildAcquisition[T, C, R],
  NativeBackedExecutionIssue,
] {
  match self.require_domain_current(original, domain, child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if domain.read_attempted {
    return Err(Bootstrap(AlreadyConsumed))
  }
  match self.borrow_backed_domain_read_use(original, domain, child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  self.issue_backed_live_child_from_read(
    original,
    domain,
    child,
    runtime,
    Worker,
  )
}

///|
/// Parent Root/Reader assembly only. Reuse the SAME already prepared physical
/// read context and Common use; do not borrow again or weaken the separate
/// worker entry's exclusion of a parent context in a lent child payload.
pub fn[T, C, R] NativeHostBootstrap::prepare_backed_read_live_child(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
  runtime : R,
) -> Result[
  NativeBackedLiveChildAcquisition[T, C, R],
  NativeBackedExecutionIssue,
] {
  match self.require_backed_read_context_current(original, domain, child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  self.issue_backed_live_child_from_read(original, domain, child, runtime, Read)
}

///|
/// Distinct initialization selection before any frame is issued or started.
/// Reuse the SAME physical allocator context, not an existing Read admission,
/// its small census or a worker's already selected imported child.
pub fn[T, C, I] NativeHostBootstrap::prepare_backed_initialization_live_child(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
  input : I,
) -> Result[
  NativeBackedLiveChildAcquisition[T, C, I],
  NativeBackedExecutionIssue,
] {
  match self.require_backed_read_context_current(original, domain, child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  self.issue_backed_live_child_from_read(
    original,
    domain,
    child,
    input,
    Initialization,
  )
}

///|
fn[T, C, R] NativeHostBootstrap::issue_backed_live_child_from_read(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
  runtime : R,
  purpose : NativeBackedLiveChildPurpose,
) -> Result[
  NativeBackedLiveChildAcquisition[T, C, R],
  NativeBackedExecutionIssue,
] {
  match self.original_read_carrier(original, domain, child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if domain.live_child_attempted {
    return Err(Bootstrap(AlreadyConsumed))
  }
  domain.live_child_attempted = true
  let record : NativeBackedLiveChild[T, C, R] = {
    original: None,
    owner: self,
    domain,
    child,
    purpose,
    runtime: Some(runtime),
    access: None,
    projection: None,
    retired: false,
    initialization: None,
    request_preparation: None,
  }
  record.original = Some(record)
  let loan = domain.view.loan
  match
    @resources.issue_backed_execution_live_access(
      loan.region.accounting,
      self,
      child,
      loan.accounting,
      domain.read_use.unwrap(),
      runtime,
    ) {
    Err(issue) => Ok(LiveChildPending(record, Accounting(issue)))
    Ok(access) => {
      record.access = Some(access)
      Ok(LiveChildReady(record))
    }
  }
}

///|
/// The same parent read issuer keeps the returned frame private. No limits,
/// callback, Ledger or Boolean enters this original child preparation.
pub fn[T, C, R] NativeHostBootstrap::prepare_backed_original_read_ledger(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChild[T, C, R],
  runtime : R,
) -> Result[@resources.ImportedChildLedger, NativeBackedOriginalReadIssue] {
  match self.original_live_child(original, record, runtime) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  if record.purpose != Read {
    return Err(Domain(Bootstrap(ForeignOriginal)))
  }
  match
    self.require_backed_read_context_current(
      original,
      record.domain,
      record.child,
    ) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  guard record.projection is Some(projection) else {
    return Err(Domain(Bootstrap(Unavailable)))
  }
  @resources.prepare_backed_original_child_ledger(projection, runtime).map_err(issue => {
    Child(issue)
  })
}

///|
/// The same input-bound preparation view goes to the portable Host body. The
/// Native issuer retains its original frame for physical cleanup before this
/// fallible body is started; no callback, scalar budget or Ledger is accepted.
pub fn[T, C, I] NativeHostBootstrap::prepare_backed_original_initialization_admission(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChild[T, C, I],
  input : I,
) -> Result[
  @resources.BackedInitializationAdmission[I],
  NativeBackedOriginalReadIssue,
] {
  match self.original_live_child(original, record, input) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  if record.purpose != Initialization {
    return Err(Domain(Bootstrap(ForeignOriginal)))
  }
  match
    self.require_backed_read_context_current(
      original,
      record.domain,
      record.child,
    ) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  guard record.projection is Some(projection) else {
    return Err(Domain(Bootstrap(Unavailable)))
  }
  @resources.prepare_backed_initialization_admission(projection, input).map_err(issue => {
      Child(issue)
    },
  )
}

///|
// Same private physical Owner's pre-bootstrap resource projection. It supplies
// no VM/launch admission or fixed VM/Host capacities. The channel retains the
// returned frame before any reply/current postcheck can leave Native custody.
fn[T, C, R] NativeHostBootstrap::prepare_backed_original_live_ledger(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChild[T, C, R],
  runtime : R,
) -> Result[@resources.ImportedChildLedger, NativeBackedOriginalReadIssue] {
  match self.original_live_child(original, record, runtime) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  if record.purpose != Worker {
    return Err(Domain(Bootstrap(ForeignOriginal)))
  }
  match self.require_domain_current(original, record.domain, record.child) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  guard record.access is Some(access) else {
    return Err(Domain(Bootstrap(Unavailable)))
  }
  let projection = match
    @resources.admit_backed_execution_live_child(access, runtime) {
    Err(issue) => return Err(Domain(Accounting(issue)))
    Ok(projection) => {
      record.projection = Some(projection)
      projection
    }
  }
  @resources.prepare_backed_original_child_ledger(projection, runtime).map_err(issue => {
    Child(issue)
  })
}

///|
pub(all) enum NativeBackedOriginalReadIssue {
  Domain(NativeBackedExecutionIssue)
  Child(@resources.ImportedChildLedgerIssue)
}

///|
fn[T, C, R] NativeHostBootstrap::original_live_child(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChild[T, C, R],
  runtime : R,
) -> Result[Unit, NativeBackedExecutionIssue] {
  if !physical_equal(record.owner, self) ||
    record.retired ||
    !(record.original is Some(selected) && physical_equal(selected, record)) ||
    !(record.runtime is Some(selected) && physical_equal(selected, runtime)) {
    return Err(Bootstrap(ForeignOriginal))
  }
  self.original_read_carrier(original, record.domain, record.child).map(_ => ())
}

///|
/// Trusted physical caller only, after it binds the actual VM to this same
/// original slot/channel/domain. Equal metadata or a successful C load is not
/// that observation. A lost response must retain this record, never readmit.
pub fn[T, C, R] NativeHostBootstrap::admit_backed_live_child(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChild[T, C, R],
  runtime : R,
) -> Result[Unit, NativeBackedExecutionIssue] {
  match self.original_live_child(original, record, runtime) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match self.require_domain_current(original, record.domain, record.child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard record.access is Some(access) else {
    return Err(Bootstrap(Unavailable))
  }
  match @resources.admit_backed_execution_live_child(access, runtime) {
    Err(issue) => Err(Accounting(issue))
    Ok(projection) => {
      record.projection = Some(projection)
      Ok(())
    }
  }
}

///|
/// Observe the original lifecycle without treating a limits refusal as stop.
/// Closing retains original report/cleanup; it is not physical retirement.
pub fn[T, C, R] NativeHostBootstrap::backed_live_child_state(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChild[T, C, R],
  runtime : R,
) -> Result[@resources.BackedExecutionLiveState, NativeBackedExecutionIssue] {
  match self.original_live_child(original, record, runtime) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard record.projection is Some(projection) else {
    return Err(Bootstrap(Unavailable))
  }
  let state = match
    @resources.backed_execution_live_state(projection, runtime) {
    Err(issue) => return Err(Accounting(issue))
    Ok(value) => value
  }
  match state {
    LiveOpen =>
      match self.require_domain_current(original, record.domain, record.child) {
        Err(issue) => Err(issue)
        Ok(_) => Ok(state)
      }
    LiveClosing => Ok(state)
  }
}

///|
/// DATA from the admitted same-parent allowance, never a scalar startup grant.
pub fn[T, C, R] NativeHostBootstrap::backed_live_child_limits(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChild[T, C, R],
  runtime : R,
) -> Result[@resources.LedgerLimits, NativeBackedExecutionIssue] {
  match self.original_live_child(original, record, runtime) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match self.require_domain_current(original, record.domain, record.child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard record.projection is Some(projection) else {
    return Err(Bootstrap(Unavailable))
  }
  @resources.backed_execution_live_limits(projection, runtime).map_err(issue => {
    Accounting(issue)
  })
}

///|
/// Cumulative reporting remains available for original cleanup after closing.
/// No uncertainty becomes zero usage or a replacement parent reservation.
pub fn[T, C, R] NativeHostBootstrap::report_backed_live_child(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChild[T, C, R],
  runtime : R,
  usage : @resources.LedgerUsage,
) -> Result[Unit, NativeBackedExecutionIssue] {
  match self.original_live_child(original, record, runtime) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard record.projection is Some(projection) else {
    return Err(Bootstrap(Unavailable))
  }
  @resources.report_backed_execution_live_child(projection, runtime, usage).map_err(issue => {
      Accounting(issue)
    },
  )
}

///|
pub fn[T, C, R] NativeHostBootstrap::stop_backed_live_child(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChild[T, C, R],
  runtime : R,
) -> Result[Unit, NativeBackedExecutionIssue] {
  match self.original_live_child(original, record, runtime) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard record.access is Some(access) else {
    return Err(Bootstrap(Unavailable))
  }
  @resources.stop_backed_execution_live_child(access, runtime).map_err(issue => {
    Accounting(issue)
  })
}

///|
/// Original physical issuer only, after this same child VM/channel/aliases
/// actually retire. No caller Boolean supplies an ACK. Parent context absence
/// is a separate fact; domain/view/FD/loan cleanup and settlement remain due.
pub fn[T, C, R] NativeHostBootstrap::retire_backed_live_child_after_owner_ack(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChild[T, C, R],
  runtime : R,
) -> Result[Unit, NativeBackedExecutionIssue] {
  match self.original_live_child(original, record, runtime) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if record.initialization is Some(initialization) &&
    (
      !initialization.physical_retired ||
      !initialization.inventory_finished ||
      (initialization.started && !initialization.reported)
    ) {
    return Err(Bootstrap(ReadersPending))
  }
  if record.request_preparation is Some(request) && !request.ready_for_owner_ack {
    return Err(Bootstrap(ReadersPending))
  }
  if record.access is Some(access) {
    match
      @resources.retire_backed_execution_live_child_after_owner_ack(
        access, runtime,
      ) {
      Err(issue) => return Err(Accounting(issue))
      Ok(_) => ()
    }
  }
  // A refused access still retains its original accounting borrow in domain.
  // Break this same partial record only; the separate borrow/physical cleanup
  // remains due and no admission/usage/cleanup success is manufactured.
  record.projection = None
  record.access = None
  record.runtime = None
  record.original = None
  record.retired = true
  Ok(())
}

///|
/// Real original Read caller only: policy is checked before acquisition, then
/// actual usable backing is acquired/published before the later Read resize.
/// The two byte dimensions remain independent: raw placement vs pool cover.
pub fn[T, C, R] NativeHostBootstrap::prepare_backed_original_read_working(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChild[T, C, R],
  runtime : R,
  retained : Int64,
  execution : Int64,
  contiguous_bytes : Int64,
) -> Result[Unit, NativeBackedExecutionIssue] {
  match self.original_live_child(original, record, runtime) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if record.purpose != Read || record.retired {
    return Err(Bootstrap(Unavailable))
  }
  guard record.projection is Some(projection) else {
    return Err(Bootstrap(Unavailable))
  }
  let mut minimum_usable_bytes = 0L
  if record.domain.view.loan.initial_window is Some(_) {
    match
      @resources.check_backed_original_child_window_demand(
        projection, runtime, retained, execution,
      ) {
      Err(issue) => return Err(Accounting(issue))
      Ok(_) => ()
    }
    let current = match
      @resources.read_backed_original_child_window_bytes(projection, runtime) {
      Err(issue) => return Err(Accounting(issue))
      Ok(value) => value
    }
    if retained < 0L ||
      execution < 0L ||
      execution > 9223372036854775807L - retained {
      return Err(Bootstrap(Unavailable))
    }
    minimum_usable_bytes = Int64::max(0L, retained + execution - current)
  } else {
    // Legacy fully-backed children keep their original declared-policy refusal
    // before any physical acquisition, even though they need no window grant.
    let limits = match
      @resources.backed_execution_live_limits(projection, runtime) {
      Err(issue) => return Err(Accounting(issue))
      Ok(value) => value
    }
    if retained < 0L ||
      execution < 0L ||
      retained > limits.retained_bytes ||
      execution > limits.execution_bytes {
      return Err(Accounting(@resources.Resource(@resources.InvalidLimits)))
    }
  }
  self.prepare_backed_read_working(
    original,
    record.domain,
    record.child,
    contiguous_bytes,
    minimum_usable_bytes~,
  )
}
