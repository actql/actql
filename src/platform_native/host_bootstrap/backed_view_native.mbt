///|
priv type PhysicalRegionProjection

///|
priv type PhysicalRegionView

///|
#borrow(backing, extent, loan)
extern "C" fn project_region_ffi(
  backing : Backing,
  extent : Extent,
  loan : PhysicalRegionLoan,
) -> PhysicalRegionProjection = "actql_bootstrap_project_region"

///|
#borrow(projection)
extern "C" fn projection_status_ffi(
  projection : PhysicalRegionProjection,
) -> Int = "actql_bootstrap_projection_status"

///|
#borrow(projection)
extern "C" fn projection_scalar_ffi(
  projection : PhysicalRegionProjection,
  ordinal : Int,
) -> Int64 = "actql_bootstrap_projection_scalar"

///|
#borrow(projection)
extern "C" fn projection_recipe_ffi(
  projection : PhysicalRegionProjection,
) -> Bytes = "actql_bootstrap_projection_recipe"

///|
#borrow(backing, extent, loan)
extern "C" fn map_region_ffi(
  backing : Backing,
  extent : Extent,
  loan : PhysicalRegionLoan,
  fd : Int,
  payload_offset : Int64,
  payload_length : Int64,
) -> PhysicalRegionView = "actql_bootstrap_map_region"

///|
#borrow(backing, extent, loan)
extern "C" fn view_region_in_process_ffi(
  backing : Backing, extent : Extent, loan : PhysicalRegionLoan,
  payload_offset : Int64, payload_length : Int64,
) -> PhysicalRegionView = "actql_bootstrap_view_region_in_process"

///|
#borrow(view)
extern "C" fn view_status_ffi(view : PhysicalRegionView) -> Int = "actql_bootstrap_view_status"

///|
#borrow(backing, extent, loan, view)
extern "C" fn close_region_view_ffi(
  backing : Backing,
  extent : Extent,
  loan : PhysicalRegionLoan,
  view : PhysicalRegionView,
) -> Int = "actql_bootstrap_close_region_view"

///|
/// Immutable transport DATA only, not a nominal child, loan, FD or permission.
/// The mapping window comes from this provider's actual original extent; the
/// smaller payload remains the Common child declaration. No address is exposed.
pub(all) struct NativeBackedExtentTransport {
  source : String
  recipe : Bytes
  generation : Int64
  device : Int64
  inode : Int64
  capacity : Int64
  mapping_offset : Int64
  mapping_length : Int64
  payload_offset : Int64
  payload_length : Int64
  writable : Bool
} derive(Eq, Debug)

///|
struct NativeBackedExecutionView[T, C] {
  loan : NativeBackedExecutionLoan[T, C]
  physical : PhysicalRegionView
  mut closed : Bool
  mut domain : NativeBackedExecutionDomain[T, C]?
  mut domain_attempted : Bool
}

///|
pub(all) enum NativeBackedViewAcquisition[T, C] {
  Mapped(NativeBackedExecutionView[T, C])
  PendingView(NativeBackedExecutionView[T, C], NativeBackedExecutionIssue)
}

///|
fn[T, C] NativeHostBootstrap::require_region_child(
  self : NativeHostBootstrap[T],
  original : T,
  loan : NativeBackedExecutionLoan[T, C],
  child : C,
) -> Result[Unit, NativeBackedExecutionIssue] {
  match self.require_current(original) {
    Err(issue) => return Err(Bootstrap(issue))
    Ok(_) => ()
  }
  if !physical_equal(loan.region.owner, self) ||
    !physical_equal(loan.child, child) ||
    loan.region.closed ||
    loan.physical_returned ||
    loan.settled {
    return Err(Bootstrap(ForeignOriginal))
  }
  if loan.region.closing {
    return Err(Bootstrap(Closing))
  }
  let status = region_status_ffi(loan.physical)
  if status != 0 {
    return Err(Bootstrap(Physical(status)))
  }
  match
    @resources.check_backed_execution_delegation_current(
      loan.region.accounting,
      self,
      child,
      loan.accounting,
    ) {
    Err(issue) => Err(Accounting(issue))
    Ok(_) => Ok(())
  }
}

///|
pub fn[T, C] NativeHostBootstrap::project_backed_extent(
  self : NativeHostBootstrap[T],
  original : T,
  loan : NativeBackedExecutionLoan[T, C],
  child : C,
) -> Result[NativeBackedExtentTransport, NativeBackedExecutionIssue] {
  match self.require_region_child(original, loan, child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if loan.transport is Some(transport) {
    return Ok(transport)
  }
  let (extent, access, _) = match
    @resources.backed_execution_delegation_description(
      loan.region.accounting,
      self,
      child,
      loan.accounting,
    ) {
    Err(issue) => return Err(Accounting(issue))
    Ok(value) => value
  }
  let projection = project_region_ffi(
    self.backing,
    loan.region.allocation.extent,
    loan.physical,
  )
  let status = projection_status_ffi(projection)
  if status != 0 {
    return Err(Bootstrap(Physical(status)))
  }
  let recipe = projection_recipe_ffi(projection)
  let generation = projection_scalar_ffi(projection, 2)
  let capacity = projection_scalar_ffi(projection, 3)
  let offset = projection_scalar_ffi(projection, 4)
  let length = projection_scalar_ffi(projection, 5)
  let writable = projection_scalar_ffi(projection, 6)
  let allocation_offset = projection_scalar_ffi(projection, 7)
  if generation != self.supplier.generation ||
    recipe != self.supplier.recipe ||
    capacity != self.supplier.bytes ||
    allocation_offset < 0L ||
    offset < allocation_offset ||
    offset - allocation_offset != extent.offset ||
    length != extent.length ||
    writable != (if access == @resources.ExclusiveWrite { 1L } else { 0L }) {
    return Err(Bootstrap(ForeignOriginal))
  }
  let transport : NativeBackedExtentTransport = {
    source: self.supplier.source,
    recipe,
    generation,
    device: projection_scalar_ffi(projection, 0),
    inode: projection_scalar_ffi(projection, 1),
    capacity,
    mapping_offset: offset,
    mapping_length: length,
    payload_offset: extent.payload_offset,
    payload_length: extent.payload_length,
    writable: access == @resources.ExclusiveWrite,
  }
  loan.transport = Some(transport)
  Ok(transport)
}

///|
/// Private trusted physical port, not worker admission. The caller retains its
/// original FD; mapping/header checks use the exact existing provider loan.
/// A post-map failure returns this same partial view. No automatic second map.
pub fn[T, C] NativeHostBootstrap::map_backed_view(
  self : NativeHostBootstrap[T], original : T,
  loan : NativeBackedExecutionLoan[T, C], child : C, fd : Int,
) -> Result[NativeBackedViewAcquisition[T, C], NativeBackedExecutionIssue] {
  if fd < 0 { return Err(Bootstrap(Unavailable)) }
  self.bind_original_view(original, loan, child, Some(fd))
}

///|
/// Bind the same original local loan without mapping or projecting transport.
pub fn[T, C] NativeHostBootstrap::view_backed_region_in_process(
  self : NativeHostBootstrap[T], original : T,
  loan : NativeBackedExecutionLoan[T, C], child : C,
) -> Result[NativeBackedViewAcquisition[T, C], NativeBackedExecutionIssue] {
  self.bind_original_view(original, loan, child, None)
}

///|
fn[T, C] NativeHostBootstrap::bind_original_view(
  self : NativeHostBootstrap[T], original : T,
  loan : NativeBackedExecutionLoan[T, C], child : C, fd : Int?,
) -> Result[NativeBackedViewAcquisition[T, C], NativeBackedExecutionIssue] {
  match self.require_region_child(original, loan, child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if loan.map_attempted {
    return Err(Bootstrap(AlreadyConsumed))
  }
  let (extent, _, _) = match
    @resources.backed_execution_delegation_description(
      loan.region.accounting,
      self,
      child,
      loan.accounting,
    ) {
    Err(issue) => return Err(Accounting(issue))
    Ok(value) => value
  }
  loan.map_attempted = true
  let physical = match fd {
    Some(fd) => map_region_ffi(self.backing, loan.region.allocation.extent,
      loan.physical, fd, extent.payload_offset, extent.payload_length)
    None => view_region_in_process_ffi(self.backing, loan.region.allocation.extent,
      loan.physical, extent.payload_offset, extent.payload_length)
  }
  let view : NativeBackedExecutionView[T, C] = {
    loan,
    physical,
    closed: false,
    domain: None,
    domain_attempted: false,
  }
  loan.view = Some(view)
  let status = view_status_ffi(physical)
  if status != 0 {
    return Ok(PendingView(view, Bootstrap(Physical(status))))
  }
  Ok(Mapped(view))
}

///|
/// Same view cleanup is allowed after closing/stop. Success retires only this
/// mapping; it never closes the caller FD, returns the range or settles a child.
pub fn[T, C] NativeHostBootstrap::close_backed_view(
  self : NativeHostBootstrap[T],
  original : T,
  view : NativeBackedExecutionView[T, C],
  child : C,
) -> Result[Unit, NativeBackedExecutionIssue] {
  if !physical_equal(self.supplier.original, original) ||
    !physical_equal(view.loan.region.owner, self) ||
    !physical_equal(view.loan.child, child) {
    return Err(Bootstrap(ForeignOriginal))
  }
  if view.closed {
    return Ok(())
  }
  if !(view.loan.view is Some(selected) && physical_equal(selected, view)) {
    return Err(Bootstrap(ForeignOriginal))
  }
  if view.domain is Some(domain) && !domain.closed {
    return Err(Bootstrap(ReadersPending))
  }
  let status = close_region_view_ffi(
    self.backing,
    view.loan.region.allocation.extent,
    view.loan.physical,
    view.physical,
  )
  if status != 0 {
    return Err(Bootstrap(Physical(status)))
  }
  view.closed = true
  Ok(())
}
