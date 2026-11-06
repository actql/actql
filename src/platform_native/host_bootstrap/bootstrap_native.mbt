///|
priv type Backing

///|
priv type Extent

///|
extern "C" fn command_backing_control_necessary_bytes_ffi(
  bytes : Int64,
) -> Int64 = "actql_bootstrap_command_backing_control_necessary_bytes"

///|
/// Read-only selected provider layout; neither backing nor shared capacity.
pub fn command_backing_control_necessary_bytes(bytes : Int64) -> Int64? {
  let control = command_backing_control_necessary_bytes_ffi(bytes)
  if control > 0L {
    Some(control)
  } else {
    None
  }
}

///|
#borrow(recipe)
extern "C" fn acquire_ffi(
  bytes : Int64,
  generation : Int64,
  recipe : Bytes,
) -> Backing = "actql_bootstrap_acquire"

///|
#borrow(recipe)
extern "C" fn acquire_fd_ffi(
  fd : Int,
  bytes : Int64,
  generation : Int64,
  recipe : Bytes,
) -> Backing = "actql_bootstrap_acquire_fd"

///|
#borrow(backing)
extern "C" fn status_ffi(backing : Backing) -> Int = "actql_bootstrap_status"

///|
#borrow(backing)
extern "C" fn control_bytes_ffi(backing : Backing) -> Int64 = "actql_bootstrap_control_bytes"

///|
#borrow(backing)
extern "C" fn rounded_bytes_ffi(backing : Backing, bytes : Int64) -> Int64 = "actql_bootstrap_rounded_bytes"

///|
#borrow(backing, recipe)
extern "C" fn claim_ffi(
  backing : Backing,
  generation : Int64,
  recipe : Bytes,
) -> Int = "actql_bootstrap_claim"

///|
#borrow(backing)
extern "C" fn allocate_ffi(backing : Backing, bytes : Int64) -> Extent = "actql_bootstrap_allocate"

///|
#borrow(backing)
extern "C" fn allocate_in_process_domain_ffi(
  backing : Backing,
  bytes : Int64,
) -> Extent = "actql_bootstrap_allocate_in_process_domain"

///|
#borrow(extent)
extern "C" fn extent_status_ffi(extent : Extent) -> Int = "actql_bootstrap_extent_status"

///|
#borrow(backing, extent)
extern "C" fn retire_ffi(backing : Backing, extent : Extent) -> Int = "actql_bootstrap_retire"

///|
#borrow(backing)
extern "C" fn close_ffi(backing : Backing) -> Int = "actql_bootstrap_close"

///|
#borrow(backing)
extern "C" fn enter_scope_ffi(backing : Backing) -> Int = "actql_bootstrap_enter_scope"

///|
#borrow(backing)
extern "C" fn leave_scope_ffi(backing : Backing) -> Int = "actql_bootstrap_leave_scope"

///|
pub(all) enum NativeBootstrapIssue {
  Unavailable
  ForeignOriginal
  AlreadyConsumed
  Closing
  ReadersPending
  Physical(Int)
  Resource(@resources.LedgerIssue)
} derive(Eq, Debug)

///|
/// Trusted installation entry, not an SDK profile or an authority issuer.
/// Only the selected arena domain is backed here. The initial control runtime
/// and fixed wrapper records belong to the installer's declared finite envelope.
struct NativeInstalledArenaSupplier[T] {
  original : T
  source : String
  recipe : Bytes
  generation : Int64
  bytes : Int64
  limits : @resources.LedgerLimits
  control_envelope_bytes : Int64
  mut consumed : Bool
}

///|
/// The caller is the trusted installed physical supplier. Data validation does
/// not authenticate installation, grant Run/publish permission or cover a VM.
/// The only backend in this first slice is Darwin arm64's original C arena.
pub fn[T] prepare_installed_arena_supplier(
  original : T,
  source : String,
  recipe : Bytes,
  generation : Int64,
  bytes : Int64,
  limits : @resources.LedgerLimits,
  control_envelope_bytes : Int64,
) -> Result[NativeInstalledArenaSupplier[T], NativeBootstrapIssue] {
  if source.length() != 40 ||
    recipe.length() != 32 ||
    generation <= 0L ||
    bytes <= 0L ||
    limits.execution_bytes < bytes ||
    limits.retained_bytes != 0L ||
    limits.attempts < 1 ||
    control_envelope_bytes <= 0L {
    return Err(Unavailable)
  }
  Ok({
    original,
    source,
    recipe,
    generation,
    bytes,
    limits,
    control_envelope_bytes,
    consumed: false,
  })
}

///|
struct NativeHostBootstrap[T] {
  supplier : NativeInstalledArenaSupplier[T]
  ledger : @resources.Ledger
  capacity : @resources.SharedCapacity
  backing : Backing
  mut control : @resources.SharedAllocation?
  mut growth : @resources.SharedCapacityGrowth?
  children : Array[NativeBootstrapAllocation[T]]
  delegations : Array[NativeBootstrapDelegation[T]]
  mut claimed : Bool
  mut closing : Bool
  mut physical_closed : Bool
  mut closed : Bool
}

///|
pub(all) enum NativeBootstrapAcquisition[T] {
  Acquired(NativeHostBootstrap[T])
  Pending(NativeHostBootstrap[T], NativeBootstrapIssue)
}

///|
/// Reserve the original capacity before mmap. After physical acquisition begins,
/// every failure returns the same partial carrier, primary issue and reservation.
/// No image, Config, Engine, child process or future Run is used for bootstrap.
pub fn[T] NativeInstalledArenaSupplier::acquire(
  self : NativeInstalledArenaSupplier[T],
  original : T,
) -> Result[NativeBootstrapAcquisition[T], NativeBootstrapIssue] {
  self.acquire_original(original, None)
}

///|
/// Trusted supplier's borrowed physical FD, not a byte/identity grant. Its
/// descriptor lifetime and overhead remain with that original physical caller;
/// Host cleanup acknowledges this mapping only, never FD close or worker stop.
pub fn[T] NativeInstalledArenaSupplier::acquire_fd(
  self : NativeInstalledArenaSupplier[T],
  original : T,
  fd : Int,
) -> Result[NativeBootstrapAcquisition[T], NativeBootstrapIssue] {
  if fd < 0 {
    return Err(Unavailable)
  }
  self.acquire_original(original, Some(fd))
}

///|
fn[T] NativeInstalledArenaSupplier::acquire_original(
  self : NativeInstalledArenaSupplier[T],
  original : T,
  fd : Int?,
) -> Result[NativeBootstrapAcquisition[T], NativeBootstrapIssue] {
  if !physical_equal(original, self.original) {
    return Err(ForeignOriginal)
  }
  if self.consumed {
    return Err(AlreadyConsumed)
  }
  // Keep the installer's original finite control precondition at acquisition.
  // This declaration does not fund the independent loader, VM or read domains.
  if self.control_envelope_bytes <= 0L {
    return Err(Unavailable)
  }
  self.consumed = true
  let ledger = match @resources.create_ledger(self.limits) {
    Err(issue) => return Err(Resource(issue))
    Ok(value) => value
  }
  let capacity = match @resources.reserve_shared_capacity(ledger, self.bytes) {
    Err(issue) => return Err(Resource(issue))
    Ok(value) => value
  }
  let backing = match fd {
    None => acquire_ffi(self.bytes, self.generation, self.recipe)
    Some(fd) => acquire_fd_ffi(fd, self.bytes, self.generation, self.recipe)
  }
  let host : NativeHostBootstrap[T] = {
    supplier: self,
    ledger,
    capacity,
    backing,
    control: None,
    growth: None,
    children: [],
    delegations: [],
    claimed: false,
    closing: false,
    physical_closed: false,
    closed: false,
  }
  let status = status_ffi(backing)
  if status != 0 {
    return Ok(Pending(host, Physical(status)))
  }
  let control_bytes = control_bytes_ffi(backing)
  match @resources.allocate_shared_capacity(capacity, control_bytes) {
    Err(issue) => Ok(Pending(host, Resource(issue)))
    Ok(control) => {
      host.control = Some(control)
      Ok(Acquired(host))
    }
  }
}

///|
fn[T] NativeHostBootstrap::check_original(
  self : NativeHostBootstrap[T],
  original : T,
) -> Result[Unit, NativeBootstrapIssue] {
  if !physical_equal(self.supplier.original, original) {
    return Err(ForeignOriginal)
  }
  if self.closing || self.closed || self.physical_closed {
    return Err(Closing)
  }
  match @resources.check_original_resources_mutable(self.ledger) {
    Err(issue) => Err(Resource(issue))
    Ok(_) => Ok(())
  }
}

///|
/// Original arena availability only. This is not a VM/Run/publisher permission.
/// An installed non-test wrapper keeps this exact Host and its original anchor.
pub fn[T] NativeHostBootstrap::require_current(
  self : NativeHostBootstrap[T],
  original : T,
) -> Result[Unit, NativeBootstrapIssue] {
  match self.check_original(original) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !self.claimed || self.growth is Some(_) {
    return Err(Unavailable)
  }
  Ok(())
}

///|
/// One transfer to this original installed Host. A copied reference shares this
/// consumed state; matching source/recipe data cannot create another supplier.
pub fn[T] NativeHostBootstrap::claim(
  self : NativeHostBootstrap[T],
  original : T,
  source : String,
  recipe : Bytes,
  generation : Int64,
) -> Result[Unit, NativeBootstrapIssue] {
  match self.check_original(original) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if source != self.supplier.source ||
    recipe != self.supplier.recipe ||
    generation != self.supplier.generation {
    return Err(ForeignOriginal)
  }
  if self.claimed {
    return Err(AlreadyConsumed)
  }
  if status_ffi(self.backing) != 0 || self.control is None {
    return Err(Unavailable)
  }
  let status = claim_ffi(self.backing, generation, recipe)
  if status != 0 {
    return Err(Physical(status))
  }
  self.claimed = true
  Ok(())
}

///|
struct NativeBootstrapAllocation[T] {
  owner : NativeHostBootstrap[T]
  allocation : @resources.SharedAllocation
  extent : Extent
  mut physical_retired : Bool
  mut released : Bool
}

///|
/// Rounded physical pages are reserved before allocation. Register custody before
/// examining physical success; a failed acquire remains in this Host's cleanup.
pub fn[T] NativeHostBootstrap::allocate(
  self : NativeHostBootstrap[T],
  original : T,
  bytes : Int64,
) -> Result[NativeBootstrapAllocation[T], NativeBootstrapIssue] {
  self.allocate_original(original, bytes, false)
}

///|
/// Private registration storage for the same in-process child domain. Its
/// payload cannot be used as a generic span; actual child allocations retain
/// their complete clearing guarantee. This reserves the same rounded capacity.
pub fn[T] NativeHostBootstrap::allocate_in_process_domain(
  self : NativeHostBootstrap[T],
  original : T,
  bytes : Int64,
) -> Result[NativeBootstrapAllocation[T], NativeBootstrapIssue] {
  self.allocate_original(original, bytes, true)
}

///|
fn[T] NativeHostBootstrap::allocate_original(
  self : NativeHostBootstrap[T],
  original : T,
  bytes : Int64,
  domain_storage : Bool,
) -> Result[NativeBootstrapAllocation[T], NativeBootstrapIssue] {
  match self.check_original(original) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !self.claimed {
    return Err(Unavailable)
  }
  // Fixed wrapper records are bounded by the selected control envelope's
  // existing attempt count; failed records are not anonymously discarded.
  if self.children.length() >= self.supplier.limits.attempts {
    return Err(Unavailable)
  }
  let rounded = rounded_bytes_ffi(self.backing, bytes)
  if rounded <= 0L {
    return Err(Unavailable)
  }
  let allocation = match
    @resources.allocate_shared_capacity(self.capacity, rounded) {
    Err(issue) => return Err(Resource(issue))
    Ok(value) => value
  }
  let extent = if domain_storage {
    allocate_in_process_domain_ffi(self.backing, rounded)
  } else {
    allocate_ffi(self.backing, rounded)
  }
  let child : NativeBootstrapAllocation[T] = {
    owner: self,
    allocation,
    extent,
    physical_retired: false,
    released: false,
  }
  self.children.push(child)
  let status = extent_status_ffi(extent)
  if status != 0 {
    return Err(Physical(status))
  }
  Ok(child)
}

///|
/// Physical retirement must precede the existing Owner's capacity release.
/// Failure keeps this same extent and allocation, even after Host close begins.
pub fn[T] NativeHostBootstrap::retire(
  self : NativeHostBootstrap[T],
  original : T,
  child : NativeBootstrapAllocation[T],
) -> Result[Unit, NativeBootstrapIssue] {
  if !physical_equal(self.supplier.original, original) ||
    !physical_equal(child.owner, self) {
    return Err(ForeignOriginal)
  }
  if child.released {
    return Ok(())
  }
  // A backing borrower can be using this extent even without a child-specific
  // reader. Do not physically retire it behind that original caller.
  if self.control is Some(control) {
    if @resources.shared_allocation_usage(control).readers != 0 {
      return Err(ReadersPending)
    }
  }
  match @resources.retire_shared_capacity(child.allocation) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  if @resources.shared_allocation_usage(child.allocation).readers != 0 {
    return Err(ReadersPending)
  }
  if !child.physical_retired {
    let status = retire_ffi(self.backing, child.extent)
    if status != 0 {
      return Err(Physical(status))
    }
    child.physical_retired = true
  }
  match @resources.release_shared_capacity(child.allocation) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => child.released = true
  }
  Ok(())
}

///|
struct NativeBootstrapBorrow[T] {
  owner : NativeHostBootstrap[T]
  borrow : @resources.SharedBorrow
  mut scopes : Int64
  mut returned : Bool
}

///|
/// Lend the original control allocation while a physical caller uses this same
/// backing. This creates no extent, second transfer or VM execution grant.
pub fn[T] NativeHostBootstrap::borrow_backing(
  self : NativeHostBootstrap[T],
  original : T,
) -> Result[NativeBootstrapBorrow[T], NativeBootstrapIssue] {
  match self.require_current(original) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard self.control is Some(control) else { return Err(Unavailable) }
  match @resources.borrow_shared_capacity(self.capacity, control) {
    Err(issue) => Err(Resource(issue))
    Ok(borrow) => Ok({ owner: self, borrow, scopes: 0L, returned: false, })
  }
}

///|
/// Current execution use is refused once closing starts. Returning the original
/// borrow for cleanup still uses return_borrow, including after close refusal.
pub fn[T] NativeHostBootstrap::require_borrow_current(
  self : NativeHostBootstrap[T],
  original : T,
  borrow : NativeBootstrapBorrow[T],
) -> Result[Unit, NativeBootstrapIssue] {
  if !physical_equal(borrow.owner, self) {
    return Err(ForeignOriginal)
  }
  if borrow.returned {
    return Err(AlreadyConsumed)
  }
  self.require_current(original)
}

///|
/// Enter the one original physical allocator through this current Owner loan.
/// The scope carries no raw pointer, VM permission or second capacity claim.
pub fn[T] NativeHostBootstrap::enter_borrow_scope(
  self : NativeHostBootstrap[T],
  original : T,
  borrow : NativeBootstrapBorrow[T],
) -> Result[Unit, NativeBootstrapIssue] {
  match self.require_borrow_current(original, borrow) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if borrow.scopes == 9223372036854775807L {
    return Err(Unavailable)
  }
  let status = enter_scope_ffi(self.backing)
  if status != 0 {
    return Err(Physical(status))
  }
  borrow.scopes = borrow.scopes + 1L
  Ok(())
}

///|
/// Cleanup may leave after closing begins. Failed physical leave keeps the
/// original loan/use count; it cannot be replaced by a logical return ACK.
pub fn[T] NativeHostBootstrap::leave_borrow_scope(
  self : NativeHostBootstrap[T],
  original : T,
  borrow : NativeBootstrapBorrow[T],
) -> Result[Unit, NativeBootstrapIssue] {
  if !physical_equal(self.supplier.original, original) ||
    !physical_equal(borrow.owner, self) {
    return Err(ForeignOriginal)
  }
  if borrow.returned || borrow.scopes == 0L {
    return Err(AlreadyConsumed)
  }
  let status = leave_scope_ffi(self.backing)
  if status != 0 {
    return Err(Physical(status))
  }
  borrow.scopes = borrow.scopes - 1L
  Ok(())
}

///|
pub fn[T] NativeHostBootstrap::borrow(
  self : NativeHostBootstrap[T],
  original : T,
  child : NativeBootstrapAllocation[T],
) -> Result[NativeBootstrapBorrow[T], NativeBootstrapIssue] {
  match self.check_original(original) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !physical_equal(child.owner, self) || child.released {
    return Err(ForeignOriginal)
  }
  match @resources.borrow_shared_capacity(self.capacity, child.allocation) {
    Err(issue) => Err(Resource(issue))
    Ok(borrow) => Ok({ owner: self, borrow, scopes: 0L, returned: false, })
  }
}

///|
/// The trusted physical caller supplies this only after its exact reader stops.
/// Returning a borrow is not process stop, Run cancellation or Store ACK.
pub fn[T] NativeHostBootstrap::return_borrow(
  self : NativeHostBootstrap[T],
  original : T,
  borrow : NativeBootstrapBorrow[T],
) -> Result[Unit, NativeBootstrapIssue] {
  if !physical_equal(self.supplier.original, original) ||
    !physical_equal(borrow.owner, self) {
    return Err(ForeignOriginal)
  }
  if borrow.returned {
    return Err(AlreadyConsumed)
  }
  if borrow.scopes != 0L {
    return Err(ReadersPending)
  }
  match @resources.return_shared_capacity(borrow.borrow) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => borrow.returned = true
  }
  Ok(())
}

///|
struct NativeBootstrapDelegation[T] {
  owner : NativeHostBootstrap[T]
  delegation : @resources.ExecutionDelegation
  mut settled : Bool
}

///|
/// Logical counters/transfer within this same physical domain only. Byte
/// envelopes for another worker/VM are unavailable, not paid by this arena.
pub fn[T] NativeHostBootstrap::delegate(
  self : NativeHostBootstrap[T],
  original : T,
  limits : @resources.LedgerLimits,
) -> Result[NativeBootstrapDelegation[T], NativeBootstrapIssue] {
  match self.check_original(original) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !self.claimed ||
    limits.retained_bytes != 0L ||
    limits.execution_bytes != 0L {
    return Err(Unavailable)
  }
  match @resources.reserve_execution_delegation(self.ledger, limits, 0L, 0L) {
    Err(issue) => Err(Resource(issue))
    Ok(delegation) => {
      let child : NativeBootstrapDelegation[T] = {
        owner: self,
        delegation,
        settled: false,
      }
      self.delegations.push(child)
      Ok(child)
    }
  }
}

///|
pub fn[T] NativeHostBootstrap::report(
  self : NativeHostBootstrap[T],
  original : T,
  child : NativeBootstrapDelegation[T],
  usage : @resources.LedgerUsage,
) -> Result[Unit, NativeBootstrapIssue] {
  match self.check_original(original) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !physical_equal(child.owner, self) || child.settled {
    return Err(ForeignOriginal)
  }
  match
    @resources.report_execution_delegation(self.ledger, child.delegation, usage) {
    Err(issue) => Err(Resource(issue))
    Ok(_) => Ok(())
  }
}

///|
/// Exact physical munmap covers this arena only. Keep the original reservation
/// until all children/readers retire and every physical close acknowledges.
/// Lost final usage consumes the original delegation conservatively in Common.
pub fn[T] NativeHostBootstrap::try_close(
  self : NativeHostBootstrap[T],
  original : T,
) -> Result[Unit, NativeBootstrapIssue] {
  if !physical_equal(self.supplier.original, original) {
    return Err(ForeignOriginal)
  }
  if self.closed {
    return Ok(())
  }
  if !self.closing {
    match @resources.close_shared_capacity(self.capacity) {
      Err(issue) => return Err(Resource(issue))
      Ok(_) => self.closing = true
    }
  }
  // A caller borrowing the backing can still be using its child extents.
  // Preserve all original physical custody until it returns the same loan.
  if self.control is Some(control) {
    if @resources.shared_allocation_usage(control).readers != 0 {
      return Err(ReadersPending)
    }
  }
  for child in self.children {
    match self.retire(original, child) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  if !self.physical_closed {
    let status = close_ffi(self.backing)
    if status != 0 {
      return Err(Physical(status))
    }
    self.physical_closed = true
  }
  if self.growth is Some(growth) {
    match @resources.abort_shared_capacity_growth_after_cleanup(growth) {
      Err(issue) => return Err(Resource(issue))
      Ok(_) => self.growth = None
    }
  }
  if self.control is Some(control) {
    match @resources.retire_shared_capacity(control) {
      Err(issue) => return Err(Resource(issue))
      Ok(_) => ()
    }
    match @resources.release_shared_capacity(control) {
      Err(issue) => return Err(Resource(issue))
      Ok(_) => self.control = None
    }
  }
  for child in self.delegations {
    if !child.settled {
      match
        @resources.settle_execution_delegation(
          self.ledger,
          child.delegation,
          None,
        ) {
        Err(issue) => return Err(Resource(issue))
        Ok(_) => child.settled = true
      }
    }
  }
  match @resources.settle_shared_capacity(self.capacity) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => self.closed = true
  }
  self.children.clear()
  self.delegations.clear()
  Ok(())
}

///|
pub fn[T] NativeHostBootstrap::usage(
  self : NativeHostBootstrap[T],
) -> @resources.LedgerUsage {
  @resources.ledger_usage(self.ledger)
}

///|
pub fn[T] NativeHostBootstrap::capacity_usage(
  self : NativeHostBootstrap[T],
) -> @resources.SharedCapacityUsage {
  @resources.shared_capacity_usage(self.capacity)
}

///|
/// Accounting candidate for the first payload only, never a physical maximum
/// or allocation grant. The caller must still use the same allocator's actual
/// acquisition and retain its partial/refused result. Hidden physical use or
/// fragmentation is not inferred absent from these logical observations.
pub fn[T] NativeHostBootstrap::initial_payload_capacity(
  self : NativeHostBootstrap[T],
  original : T,
) -> Result[Int64, NativeBootstrapIssue] {
  match self.require_current(original) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !self.children.is_empty() || !self.delegations.is_empty() {
    return Err(AlreadyConsumed)
  }
  guard self.control is Some(control) else { return Err(Unavailable) }
  let actual = control_bytes_ffi(self.backing)
  let allocation = @resources.shared_allocation_usage(control)
  let usage = self.capacity_usage()
  if actual <= 0L ||
    allocation.bytes != actual ||
    allocation.retiring ||
    allocation.released ||
    usage.closing ||
    usage.allocated != actual ||
    usage.capacity <= actual {
    return Err(Unavailable)
  }
  Ok(usage.capacity - actual)
}
