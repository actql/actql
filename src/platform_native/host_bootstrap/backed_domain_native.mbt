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
}

///|
pub(all) enum NativeBackedDomainAcquisition[T, C] {
  DomainReady(NativeBackedExecutionDomain[T, C])
  DomainPending(NativeBackedExecutionDomain[T, C], NativeBackedExecutionIssue)
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
  if domain.closed {
    return Ok(())
  }
  if !(domain.view.domain is Some(selected) && physical_equal(selected, domain)) {
    return Err(Bootstrap(ForeignOriginal))
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
