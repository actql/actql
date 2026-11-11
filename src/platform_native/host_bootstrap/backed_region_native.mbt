///|
priv type PhysicalRegionLoan

///|
#borrow(backing, extent)
extern "C" fn lend_region_ffi(
  backing : Backing,
  extent : Extent,
  offset : Int64,
  length : Int64,
  writable : Bool,
) -> PhysicalRegionLoan = "actql_bootstrap_lend_region"

///|
#borrow(backing, extent)
extern "C" fn lend_region_in_process_ffi(
  backing : Backing,
  extent : Extent,
  offset : Int64,
  length : Int64,
  writable : Bool,
) -> PhysicalRegionLoan = "actql_bootstrap_lend_region_in_process"

///|
#borrow(loan)
extern "C" fn region_status_ffi(loan : PhysicalRegionLoan) -> Int = "actql_bootstrap_region_status"

///|
#borrow(backing, extent, loan)
extern "C" fn return_region_ffi(
  backing : Backing,
  extent : Extent,
  loan : PhysicalRegionLoan,
) -> Int = "actql_bootstrap_return_region"

///|
pub(all) enum NativeBackedExecutionIssue {
  Bootstrap(NativeBootstrapIssue)
  Accounting(@resources.BackedExecutionIssue)
} derive(Eq, Debug)

///|
/// Nominal projection of the same Host/allocation, never another byte reserve.
/// Fixed physical records remain in the original control envelope. Independent
/// process/FD/VM/control overhead still requires separate selected funding.
struct NativeBackedExecutionRegion[T, C] {
  owner : NativeHostBootstrap[T]
  allocation : NativeBootstrapAllocation[T]
  accounting : @resources.BackedExecutionRegion[NativeHostBootstrap[T], C]
  loans : Array[NativeBackedExecutionLoan[T, C]]
  mut closed : Bool
  mut closing : Bool
}

///|
struct NativeBackedExecutionLoan[T, C] {
  region : NativeBackedExecutionRegion[T, C]
  child : C
  accounting : @resources.BackedExecutionDelegation[NativeHostBootstrap[T], C]
  physical : PhysicalRegionLoan
  initial_window : Int64?
  mut physical_returned : Bool
  mut settled : Bool
  mut view : NativeBackedExecutionView[T, C]?
  mut map_attempted : Bool
  mut transport : NativeBackedExtentTransport?
}

///|
pub(all) enum NativeBackedExecutionAcquisition[T, C] {
  Lent(NativeBackedExecutionLoan[T, C])
  Pending(NativeBackedExecutionLoan[T, C], NativeBackedExecutionIssue)
}

///|
pub fn[T, C] NativeHostBootstrap::issue_backed_region(
  self : NativeHostBootstrap[T],
  original : T,
  allocation : NativeBootstrapAllocation[T],
) -> Result[NativeBackedExecutionRegion[T, C], NativeBackedExecutionIssue] {
  match self.require_current(original) {
    Err(issue) => return Err(Bootstrap(issue))
    Ok(_) => ()
  }
  if !physical_equal(allocation.owner, self) ||
    allocation.released ||
    allocation.physical_retired {
    return Err(Bootstrap(ForeignOriginal))
  }
  let status = extent_status_ffi(allocation.extent)
  if status != 0 {
    return Err(Bootstrap(Physical(status)))
  }
  let accounting = match
    @resources.issue_backed_execution_region(
      self.capacity,
      allocation.allocation,
      self,
    ) {
    Err(issue) => return Err(Accounting(issue))
    Ok(value) => value
  }
  Ok({
    owner: self,
    allocation,
    accounting,
    loans: [],
    closed: false,
    closing: false,
  })
}

///|
/// Reserve logical quota before physical lending. Core owns extent exclusion;
/// the same C provider additionally checks actual page alignment and FD backing.
/// Any failure after reservation retains this original loan for explicit cleanup.
pub fn[T, C] NativeHostBootstrap::lend_backed_region(
  self : NativeHostBootstrap[T],
  original : T,
  region : NativeBackedExecutionRegion[T, C],
  scope : NativeBootstrapBorrow[T],
  child : C,
  extent : @resources.BackedExecutionExtent,
  access : @resources.BackedExecutionAccess,
  limits : @resources.LedgerLimits,
  overhead_retained : Int64,
  overhead_execution : Int64,
) -> Result[NativeBackedExecutionAcquisition[T, C], NativeBackedExecutionIssue] {
  self.lend_region_original(
    original, region, scope, child, extent, access, limits, overhead_retained, overhead_execution,
    false,
  )
}

///|
/// Same original anonymous mapping and quota. The local loan cannot be exported
/// or mapped in another process; its child and view ACKs precede parent return.
pub fn[T, C] NativeHostBootstrap::lend_backed_region_in_process(
  self : NativeHostBootstrap[T],
  original : T,
  region : NativeBackedExecutionRegion[T, C],
  scope : NativeBootstrapBorrow[T],
  child : C,
  extent : @resources.BackedExecutionExtent,
  access : @resources.BackedExecutionAccess,
  limits : @resources.LedgerLimits,
  overhead_retained : Int64,
  overhead_execution : Int64,
  initial_window? : Int64? = None,
) -> Result[NativeBackedExecutionAcquisition[T, C], NativeBackedExecutionIssue] {
  self.lend_region_original(
    original,
    region,
    scope,
    child,
    extent,
    access,
    limits,
    overhead_retained,
    overhead_execution,
    true,
    initial_window~,
  )
}

///|
fn[T, C] NativeHostBootstrap::lend_region_original(
  self : NativeHostBootstrap[T],
  original : T,
  region : NativeBackedExecutionRegion[T, C],
  scope : NativeBootstrapBorrow[T],
  child : C,
  extent : @resources.BackedExecutionExtent,
  access : @resources.BackedExecutionAccess,
  limits : @resources.LedgerLimits,
  overhead_retained : Int64,
  overhead_execution : Int64,
  in_process : Bool,
  initial_window? : Int64? = None,
) -> Result[NativeBackedExecutionAcquisition[T, C], NativeBackedExecutionIssue] {
  match self.require_borrow_current(original, scope) {
    Err(issue) => return Err(Bootstrap(issue))
    Ok(_) => ()
  }
  if !physical_equal(region.owner, self) || region.closed {
    return Err(Bootstrap(ForeignOriginal))
  }
  if scope.scopes == 0L ||
    region.loans.length() >= self.supplier.limits.attempts {
    return Err(Bootstrap(Unavailable))
  }
  let accounting = match
    @resources.reserve_backed_execution_delegation(
      region.accounting,
      self,
      child,
      extent,
      access,
      limits,
      overhead_retained,
      overhead_execution,
      initial_window~,
    ) {
    Err(issue) => return Err(Accounting(issue))
    Ok(value) => value
  }
  let lend = if in_process {
    lend_region_in_process_ffi
  } else {
    lend_region_ffi
  }
  let physical = lend(
    self.backing,
    region.allocation.extent,
    extent.offset,
    extent.length,
    access == @resources.ExclusiveWrite,
  )
  let loan : NativeBackedExecutionLoan[T, C] = {
    region,
    child,
    accounting,
    physical,
    initial_window,
    physical_returned: false,
    settled: false,
    view: None,
    map_attempted: false,
    transport: None,
  }
  region.loans.push(loan)
  let status = region_status_ffi(physical)
  if status != 0 {
    return Ok(Pending(loan, Bootstrap(Physical(status))))
  }
  Ok(Lent(loan))
}

///|
pub fn[T, C] NativeHostBootstrap::report_backed_region(
  self : NativeHostBootstrap[T],
  original : T,
  loan : NativeBackedExecutionLoan[T, C],
  child : C,
  usage : @resources.LedgerUsage,
) -> Result[Unit, NativeBackedExecutionIssue] {
  match self.require_current(original) {
    Err(issue) => return Err(Bootstrap(issue))
    Ok(_) => ()
  }
  if !physical_equal(loan.region.owner, self) ||
    !physical_equal(loan.child, child) ||
    loan.physical_returned ||
    loan.settled {
    return Err(Bootstrap(ForeignOriginal))
  }
  match
    @resources.report_backed_execution_delegation(
      loan.region.accounting,
      self,
      child,
      loan.accounting,
      usage,
    ) {
    Err(issue) => Err(Accounting(issue))
    Ok(_) => Ok(())
  }
}

///|
/// Trusted existing physical caller only, after this child's scoped stop AND
/// mapped view/FD borrower cleanup. Neither this call, cancellation nor exit
/// supplies those observations. Parent's original FD remains independently owned.
/// Physical return precedes logical settlement; either failure retains this loan.
pub fn[T, C] NativeHostBootstrap::settle_backed_region_after_owner_ack(
  self : NativeHostBootstrap[T],
  original : T,
  loan : NativeBackedExecutionLoan[T, C],
  child : C,
  final_usage : @resources.LedgerUsage?,
) -> Result[Unit, NativeBackedExecutionIssue] {
  if !physical_equal(self.supplier.original, original) ||
    !physical_equal(loan.region.owner, self) ||
    !physical_equal(loan.child, child) {
    return Err(Bootstrap(ForeignOriginal))
  }
  if loan.settled {
    return Err(Bootstrap(AlreadyConsumed))
  }
  if loan.view is Some(view) && !view.closed {
    return Err(Bootstrap(ReadersPending))
  }
  if !loan.physical_returned {
    let status = return_region_ffi(
      self.backing,
      loan.region.allocation.extent,
      loan.physical,
    )
    if status != 0 {
      return Err(Bootstrap(Physical(status)))
    }
    loan.physical_returned = true
  }
  match
    @resources.settle_backed_execution_after_owner_ack(
      loan.region.accounting,
      self,
      child,
      loan.accounting,
      final_usage,
    ) {
    Err(issue) => Err(Accounting(issue))
    Ok(_) => {
      loan.settled = true
      loan.view = None
      Ok(())
    }
  }
}

///|
pub fn[T, C] NativeHostBootstrap::close_backed_region(
  self : NativeHostBootstrap[T],
  original : T,
  region : NativeBackedExecutionRegion[T, C],
) -> Result[Bool, NativeBackedExecutionIssue] {
  if !physical_equal(self.supplier.original, original) ||
    !physical_equal(region.owner, self) {
    return Err(Bootstrap(ForeignOriginal))
  }
  if region.closed {
    return Ok(true)
  }
  region.closing = true
  match @resources.close_backed_execution_region(region.accounting, self) {
    Err(issue) => Err(Accounting(issue))
    Ok(closed) => {
      if closed {
        region.closed = true
        region.loans.clear()
        // Native clear retains backing slots. Release the empty backing only
        // after this original region closes, breaking loan -> region custody
        // without changing a pending loan's settlement or physical ACK.
        region.loans.shrink_to_fit()
      }
      Ok(closed)
    }
  }
}
