///|
priv type PhysicalExtentDomain

///|
#borrow(view)
extern "C" fn acquire_domain_ffi(
  view : PhysicalRegionView,
) -> PhysicalExtentDomain = "actql_bootstrap_acquire_domain"

///|
#borrow(domain)
extern "C" fn domain_status_ffi(domain : PhysicalExtentDomain) -> Int = "actql_bootstrap_domain_status"

///|
#borrow(domain)
extern "C" fn transfer_domain_ffi(domain : PhysicalExtentDomain) -> Int = "actql_bootstrap_transfer_domain"

///|
#borrow(domain)
extern "C" fn enter_domain_ffi(domain : PhysicalExtentDomain) -> Int = "actql_bootstrap_enter_domain"

///|
#borrow(domain)
extern "C" fn leave_domain_ffi(domain : PhysicalExtentDomain) -> Int = "actql_bootstrap_leave_domain"

///|
#borrow(view, domain)
extern "C" fn close_domain_ffi(
  view : PhysicalRegionView,
  domain : PhysicalExtentDomain,
) -> Int = "actql_bootstrap_close_domain"

///|
/// Same original view/loan holding. No new Ledger, Root or physical reserve.
/// The control table consumes the original payload before runtime allocations.
struct NativeBackedExecutionDomain[T, C] {
  view : NativeBackedExecutionView[T, C]
  physical : PhysicalExtentDomain
  mut transfer_attempted : Bool
  mut transferred : Bool
  mut closed : Bool
  // Same domain/loan carrier even when read initialization or cleanup fails.
  // Additional controls require their own reviewed physical holding inventory.
  mut read_use : @resources.BackedExecutionReadUse[NativeHostBootstrap[T], C]?
  mut read_attempted : Bool
  mut read_retired : Bool
  mut live_child_attempted : Bool
  // Same original physical channel carrier, registered before capture/admit.
  mut live_channel : NativeBackedLiveChannel[T, C]?
  mut live_channel_attempted : Bool
  // Original pre-spawn process binding also owns partial FD/view retirement.
  mut process_region : NativeBackedProcessRegion[T, C]?
  // The same pending root transaction and physical receipt, never a new owner.
  mut working_growth_prepared : Bool
  mut working_growth_serial : Int64?
}

///|
pub(all) enum NativeBackedDomainAcquisition[T, C] {
  DomainReady(NativeBackedExecutionDomain[T, C])
  DomainPending(NativeBackedExecutionDomain[T, C], NativeBackedExecutionIssue)
}

///|
/// Checked original transport DATA, not a launch/funding/Account grant. The
/// same trusted worker bootstrap must retain its nominal and durable originals.
pub(all) struct NativePreparedDomainTransport {
  extent : NativeBackedExtentTransport
  limits : @resources.LedgerLimits
} derive(Eq, Debug)

///|
/// Reuse the existing region/child/ticket Owner before projecting any material.
/// Transfer is the original physical preparation, not child startup success.
pub fn[T, C] NativeHostBootstrap::project_prepared_domain(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
) -> Result[NativePreparedDomainTransport, NativeBackedExecutionIssue] {
  match self.require_domain_current(original, domain, child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !domain.transferred {
    return Err(Bootstrap(Unavailable))
  }
  let (_, _, limits) = match
    @resources.backed_execution_delegation_description(
      domain.view.loan.region.accounting,
      self,
      child,
      domain.view.loan.accounting,
    ) {
    Err(issue) => return Err(Accounting(issue))
    Ok(value) => value
  }
  let extent = match
    self.project_backed_extent(original, domain.view.loan, child) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  Ok({ extent, limits, })
}

///|
pub fn[T, C] NativeHostBootstrap::acquire_backed_domain(
  self : NativeHostBootstrap[T],
  original : T,
  view : NativeBackedExecutionView[T, C],
  child : C,
) -> Result[NativeBackedDomainAcquisition[T, C], NativeBackedExecutionIssue] {
  match self.require_region_child(original, view.loan, child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if view.closed ||
    view.domain_attempted ||
    !(view.loan.view is Some(selected) && physical_equal(selected, view)) {
    return Err(Bootstrap(AlreadyConsumed))
  }
  view.domain_attempted = true
  let physical = acquire_domain_ffi(view.physical)
  let domain : NativeBackedExecutionDomain[T, C] = {
    view,
    physical,
    transfer_attempted: false,
    transferred: false,
    closed: false,
    read_use: None,
    read_attempted: false,
    read_retired: false,
    live_child_attempted: false,
    live_channel: None,
    live_channel_attempted: false,
    process_region: None,
    working_growth_prepared: false,
    working_growth_serial: None,
  }
  view.domain = Some(domain)
  let status = domain_status_ffi(physical)
  if status != 0 {
    return Ok(DomainPending(domain, Bootstrap(Physical(status))))
  }
  Ok(DomainReady(domain))
}

///|
fn[T, C] NativeHostBootstrap::require_domain_current(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
) -> Result[Unit, NativeBackedExecutionIssue] {
  match self.require_region_child(original, domain.view.loan, child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if domain.closed ||
    domain.process_region is Some(_) ||
    domain.view.closed ||
    !(domain.view.domain is Some(selected) && physical_equal(selected, domain)) {
    return Err(Bootstrap(ForeignOriginal))
  }
  let status = domain_status_ffi(domain.physical)
  if status != 0 {
    return Err(Bootstrap(Physical(status)))
  }
  Ok(())
}

///|
/// Identity-only original carrier, also valid during its existing cleanup.
/// This observes no physical retirement, fresh permission or returned loan.
fn[T, C] NativeHostBootstrap::original_domain_carrier(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
) -> Result[Unit, NativeBackedExecutionIssue] {
  if !physical_equal(self.supplier.original, original) ||
    !physical_equal(domain.view.loan.region.owner, self) ||
    !physical_equal(domain.view.loan.child, child) ||
    domain.closed ||
    domain.view.closed ||
    !(domain.view.domain is Some(selected) && physical_equal(selected, domain)) {
    Err(Bootstrap(ForeignOriginal))
  } else {
    Ok(())
  }
}

///|
/// Transfer the same physical domain once. This is not Core/Run permission.
pub fn[T, C] NativeHostBootstrap::transfer_backed_domain(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
) -> Result[Unit, NativeBackedExecutionIssue] {
  match self.require_domain_current(original, domain, child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if domain.transfer_attempted {
    return Err(Bootstrap(AlreadyConsumed))
  }
  domain.transfer_attempted = true
  let status = transfer_domain_ffi(domain.physical)
  if status != 0 {
    return Err(Bootstrap(Physical(status)))
  }
  domain.transferred = true
  Ok(())
}

///|
pub fn[T, C] NativeHostBootstrap::enter_backed_domain(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
) -> Result[Unit, NativeBackedExecutionIssue] {
  match self.require_domain_current(original, domain, child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !domain.transferred {
    return Err(Bootstrap(Unavailable))
  }
  let status = enter_domain_ffi(domain.physical)
  if status != 0 {
    Err(Bootstrap(Physical(status)))
  } else {
    Ok(())
  }
}

///|
/// Cleanup leaves remain available after original Host/region closing.
pub fn[T, C] NativeHostBootstrap::leave_backed_domain(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
) -> Result[Unit, NativeBackedExecutionIssue] {
  if !physical_equal(self.supplier.original, original) ||
    !physical_equal(domain.view.loan.region.owner, self) ||
    !physical_equal(domain.view.loan.child, child) ||
    domain.closed ||
    !(domain.view.domain is Some(selected) && physical_equal(selected, domain)) {
    return Err(Bootstrap(ForeignOriginal))
  }
  let status = leave_domain_ffi(domain.physical)
  if status != 0 {
    Err(Bootstrap(Physical(status)))
  } else {
    Ok(())
  }
}

///|
/// Close only this original domain. A failed close keeps the same C slot/loan;
/// success is not outer-view cleanup, FD close, worker-stop or parent return.
pub fn[T, C] NativeHostBootstrap::close_backed_domain(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
) -> Result[Unit, NativeBackedExecutionIssue] {
  if !physical_equal(self.supplier.original, original) ||
    !physical_equal(domain.view.loan.region.owner, self) ||
    !physical_equal(domain.view.loan.child, child) {
    return Err(Bootstrap(ForeignOriginal))
  }
  if domain.process_region is Some(_) {
    return Err(Bootstrap(ReadersPending))
  }
  if domain.closed {
    return Ok(())
  }
  if !(domain.view.domain is Some(selected) && physical_equal(selected, domain)) {
    return Err(Bootstrap(ForeignOriginal))
  }
  if domain.live_channel is Some(_) {
    return Err(Accounting(@resources.CleanupPending))
  }
  match self.finish_failed_backed_read_bookkeeping(original) {
    Err(issue) => return Err(Bootstrap(issue))
    Ok(_) => ()
  }
  if domain.read_use is Some(_) {
    match self.close_backed_read_context(original, domain, child) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  if domain.working_growth_serial is Some(_) {
    match self.reconcile_backed_domain_working(original, domain, child) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  let status = close_domain_ffi(domain.view.physical, domain.physical)
  if status != 0 {
    return Err(Bootstrap(Physical(status)))
  }
  domain.closed = true
  domain.view.domain = None
  Ok(())
}

///|
/// Preserve the original domain's physical/current checks at foreign callers.
/// Presence of a pending handle is never successful current observation.
pub fn[T, C] NativeHostBootstrap::require_backed_domain_current(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
) -> Result[Unit, NativeBackedExecutionIssue] {
  self.require_domain_current(original, domain, child)
}
