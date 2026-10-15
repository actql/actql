///|
/// Same parent domain and Common live access. R is an original installed
/// physical slot, not a wire pointer or a caller-supplied description. The
/// physical issuer binds its actual channel/VM/FD/domain before admission.
struct NativeBackedLiveChild[T, C, R] {
  mut original : NativeBackedLiveChild[T, C, R]?
  owner : NativeHostBootstrap[T]
  domain : NativeBackedExecutionDomain[T, C]
  child : C
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
  let record : NativeBackedLiveChild[T, C, R] = {
    original: None,
    owner: self,
    domain,
    child,
    runtime: Some(runtime),
    access: None,
    projection: None,
    retired: false,
  }
  match self.borrow_backed_domain_read_use(original, domain, child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
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
