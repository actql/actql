///|
/// One actual Native installed arena Host, not the test anchor or a wire value.
/// The initial trusted installer/control envelope owns this object. Preparing
/// its selection issues no grant; usable arena custody comes from real acquire.
struct InstalledArenaHost {
  source : String
  recipe : Bytes
  generation : Int64
  mut supplier : @bootstrap.NativeInstalledArenaSupplier[InstalledArenaHost]?
  mut backing : @bootstrap.NativeHostBootstrap[InstalledArenaHost]?
  mut acquisition_started : Bool
  mut acquisition_issue : @bootstrap.NativeBootstrapIssue?
  mut closing : Bool
  mut closed : Bool
  domain_record_limit : Int
  domains : Array[InstalledArenaDomain]
  mut local_host_resources : InstalledArenaLocalHostResources?
}

///|
/// Trusted installed entry only; SDK metadata and numeric limits do not supply
/// installation authority or coverage of another allocation domain. No current
/// product profile or worker/VM capability is selected by this private entry.
pub fn prepare_installed_arena_host(
  source : String,
  recipe : Bytes,
  generation : Int64,
  bytes : Int64,
  limits : @resources.LedgerLimits,
  control_envelope_bytes : Int64,
) -> Result[InstalledArenaHost, @bootstrap.NativeBootstrapIssue] {
  let host : InstalledArenaHost = {
    source,
    recipe,
    generation,
    supplier: None,
    backing: None,
    acquisition_started: false,
    acquisition_issue: None,
    closing: false,
    closed: false,
    domain_record_limit: limits.attempts,
    domains: [],
    local_host_resources: None,
  }
  match
    @bootstrap.prepare_installed_arena_supplier(
      host, source, recipe, generation, bytes, limits, control_envelope_bytes,
    ) {
    Err(issue) => Err(issue)
    Ok(supplier) => {
      host.supplier = Some(supplier)
      Ok(host)
    }
  }
}

///|
/// Store the actual original carrier before evaluating success/claim. Failure
/// cannot replace it, reacquire, reset quotas or anonymously discard cleanup.
pub fn InstalledArenaHost::acquire(
  self : InstalledArenaHost,
) -> Result[Unit, @bootstrap.NativeBootstrapIssue] {
  self.acquire_original(None)
}

///|
/// Trusted installed caller's borrowed FD only. Equal FD metadata is not
/// installation authority; its separate lifetime/funding remains with caller.
pub fn InstalledArenaHost::acquire_fd(
  self : InstalledArenaHost,
  fd : Int,
) -> Result[Unit, @bootstrap.NativeBootstrapIssue] {
  if fd < 0 {
    return Err(@bootstrap.Unavailable)
  }
  self.acquire_original(Some(fd))
}

///|
fn InstalledArenaHost::acquire_original(
  self : InstalledArenaHost,
  fd : Int?,
) -> Result[Unit, @bootstrap.NativeBootstrapIssue] {
  if self.closing || self.closed {
    return Err(@bootstrap.Closing)
  }
  if self.acquisition_started {
    return Err(@bootstrap.AlreadyConsumed)
  }
  guard self.supplier is Some(supplier) else {
    return Err(@bootstrap.Unavailable)
  }
  self.acquisition_started = true
  let acquired = match fd {
    None => supplier.acquire(self)
    Some(fd) => supplier.acquire_fd(self, fd)
  }
  match acquired {
    Err(issue) => {
      self.acquisition_issue = Some(issue)
      Err(issue)
    }
    Ok(@bootstrap.Pending(backing, issue)) => {
      self.backing = Some(backing)
      self.acquisition_issue = Some(issue)
      Err(issue)
    }
    Ok(@bootstrap.Acquired(backing)) => {
      self.backing = Some(backing)
      match backing.claim(self, self.source, self.recipe, self.generation) {
        Err(issue) => {
          self.acquisition_issue = Some(issue)
          Err(issue)
        }
        Ok(_) => Ok(())
      }
    }
  }
}

///|
fn InstalledArenaHost::original_backing(
  self : InstalledArenaHost,
) -> Result[
  @bootstrap.NativeHostBootstrap[InstalledArenaHost],
  @bootstrap.NativeBootstrapIssue,
] {
  if self.closing || self.closed {
    return Err(@bootstrap.Closing)
  }
  if self.acquisition_issue is Some(issue) {
    return Err(issue)
  }
  guard self.backing is Some(backing) else {
    return Err(@bootstrap.Unavailable)
  }
  match backing.require_current(self) {
    Err(issue) => Err(issue)
    Ok(_) => Ok(backing)
  }
}

///|
pub fn InstalledArenaHost::require_current(
  self : InstalledArenaHost,
) -> Result[Unit, @bootstrap.NativeBootstrapIssue] {
  match self.original_backing() {
    Err(issue) => Err(issue)
    Ok(_) => Ok(())
  }
}

///|
struct InstalledArenaAllocation {
  host : InstalledArenaHost
  original : @bootstrap.NativeBootstrapAllocation[InstalledArenaHost]
}

///|
pub fn InstalledArenaHost::allocate(
  self : InstalledArenaHost,
  bytes : Int64,
) -> Result[InstalledArenaAllocation, @bootstrap.NativeBootstrapIssue] {
  let backing = match self.original_backing() {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  match backing.allocate(self, bytes) {
    Err(issue) => Err(issue)
    Ok(original) => Ok({ host: self, original, })
  }
}

///|
struct InstalledArenaBorrow {
  host : InstalledArenaHost
  original : @bootstrap.NativeBootstrapBorrow[InstalledArenaHost]
}

///|
/// Opaque original backing loan for a trusted physical adapter. It is not a
/// transferable raw lease, another supplier or a VM/Run permission.
struct InstalledArenaBackingBorrow {
  host : InstalledArenaHost
  original : @bootstrap.NativeBootstrapBorrow[InstalledArenaHost]
}

///|
pub fn InstalledArenaHost::borrow_backing(
  self : InstalledArenaHost,
) -> Result[InstalledArenaBackingBorrow, @bootstrap.NativeBootstrapIssue] {
  let backing = match self.original_backing() {
    Err(issue) => return Err(issue)
    Ok(backing) => backing
  }
  match backing.borrow_backing(self) {
    Err(issue) => Err(issue)
    Ok(original) => Ok({ host: self, original, })
  }
}

///|
pub fn InstalledArenaHost::require_backing_borrow_current(
  self : InstalledArenaHost,
  borrow : InstalledArenaBackingBorrow,
) -> Result[Unit, @bootstrap.NativeBootstrapIssue] {
  if !physical_equal(borrow.host, self) {
    return Err(@bootstrap.ForeignOriginal)
  }
  let backing = match self.original_backing() {
    Err(issue) => return Err(issue)
    Ok(backing) => backing
  }
  backing.require_borrow_current(self, borrow.original)
}

///|
pub fn InstalledArenaHost::enter_backing_borrow_scope(
  self : InstalledArenaHost,
  borrow : InstalledArenaBackingBorrow,
) -> Result[Unit, @bootstrap.NativeBootstrapIssue] {
  if !physical_equal(borrow.host, self) {
    return Err(@bootstrap.ForeignOriginal)
  }
  let backing = match self.original_backing() {
    Err(issue) => return Err(issue)
    Ok(backing) => backing
  }
  backing.enter_borrow_scope(self, borrow.original)
}

///|
pub fn InstalledArenaHost::leave_backing_borrow_scope(
  self : InstalledArenaHost,
  borrow : InstalledArenaBackingBorrow,
) -> Result[Unit, @bootstrap.NativeBootstrapIssue] {
  if !physical_equal(borrow.host, self) {
    return Err(@bootstrap.ForeignOriginal)
  }
  guard self.backing is Some(backing) else { return Err(@bootstrap.Closing) }
  backing.leave_borrow_scope(self, borrow.original)
}

///|
/// The same physical borrower must have stopped. Closing permits this original
/// return but no new borrow/current execution, transfer or cleanup inference.
pub fn InstalledArenaHost::return_backing_borrow(
  self : InstalledArenaHost,
  borrow : InstalledArenaBackingBorrow,
) -> Result[Unit, @bootstrap.NativeBootstrapIssue] {
  if !physical_equal(borrow.host, self) {
    return Err(@bootstrap.ForeignOriginal)
  }
  guard self.backing is Some(backing) else { return Err(@bootstrap.Closing) }
  backing.return_borrow(self, borrow.original)
}

///|
pub fn InstalledArenaHost::borrow(
  self : InstalledArenaHost,
  allocation : InstalledArenaAllocation,
) -> Result[InstalledArenaBorrow, @bootstrap.NativeBootstrapIssue] {
  if !physical_equal(allocation.host, self) {
    return Err(@bootstrap.ForeignOriginal)
  }
  let backing = match self.original_backing() {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  match backing.borrow(self, allocation.original) {
    Err(issue) => Err(issue)
    Ok(original) => Ok({ host: self, original, })
  }
}

///|
/// Physical caller only, after this same reader stops. Closing keeps the backing
/// available for this return; it cannot resume acquisition or other operations.
pub fn InstalledArenaHost::return_borrow(
  self : InstalledArenaHost,
  borrow : InstalledArenaBorrow,
) -> Result[Unit, @bootstrap.NativeBootstrapIssue] {
  if !physical_equal(borrow.host, self) {
    return Err(@bootstrap.ForeignOriginal)
  }
  guard self.backing is Some(backing) else { return Err(@bootstrap.Closing) }
  backing.return_borrow(self, borrow.original)
}

///|
pub fn InstalledArenaHost::retire(
  self : InstalledArenaHost,
  allocation : InstalledArenaAllocation,
) -> Result[Unit, @bootstrap.NativeBootstrapIssue] {
  if !physical_equal(allocation.host, self) {
    return Err(@bootstrap.ForeignOriginal)
  }
  guard self.backing is Some(backing) else { return Err(@bootstrap.Closing) }
  backing.retire(self, allocation.original)
}

///|
struct InstalledArenaDelegation {
  host : InstalledArenaHost
  original : @bootstrap.NativeBootstrapDelegation[InstalledArenaHost]
}

///|
/// The underlying Owner refuses unrelated worker/VM byte-domain delegation.
pub fn InstalledArenaHost::delegate(
  self : InstalledArenaHost,
  limits : @resources.LedgerLimits,
) -> Result[InstalledArenaDelegation, @bootstrap.NativeBootstrapIssue] {
  let backing = match self.original_backing() {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  match backing.delegate(self, limits) {
    Err(issue) => Err(issue)
    Ok(original) => Ok({ host: self, original, })
  }
}

///|
pub fn InstalledArenaHost::report(
  self : InstalledArenaHost,
  delegation : InstalledArenaDelegation,
  usage : @resources.LedgerUsage,
) -> Result[Unit, @bootstrap.NativeBootstrapIssue] {
  if !physical_equal(delegation.host, self) {
    return Err(@bootstrap.ForeignOriginal)
  }
  let backing = match self.original_backing() {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  backing.report(self, delegation.original, usage)
}

///|
/// Do not break original references until the full same-backing cleanup ACK.
/// Failures retain exactly this Host; no new Root, lease or close queue exists.
pub fn InstalledArenaHost::try_close(
  self : InstalledArenaHost,
) -> Result[Unit, @bootstrap.NativeBootstrapIssue] {
  if self.closed {
    return Ok(())
  }
  self.closing = true
  if self.local_host_resources is Some(resources) && !resources.closed {
    return Err(@bootstrap.ReadersPending)
  }
  if self.domains.any(domain => !domain.closed) {
    return Err(@bootstrap.ReadersPending)
  }
  if self.backing is Some(backing) {
    match backing.try_close(self) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  self.backing = None
  self.supplier = None
  self.closed = true
  self.domains.clear()
  self.local_host_resources = None
  Ok(())
}

///|
/// Preserved primary acquisition issue; not a permission or retry conclusion.
pub fn InstalledArenaHost::acquisition_issue(
  self : InstalledArenaHost,
) -> @bootstrap.NativeBootstrapIssue? {
  self.acquisition_issue
}

///|
/// Existing installed assembly only. Acquire this same Root's selected physical
/// facility at its actual phase; declarations alone never grant child use.
pub fn InstalledArenaHost::ensure_backing_capacity(
  self : InstalledArenaHost,
  scope : InstalledArenaBackingBorrow,
  bytes : Int64,
) -> Result[Unit, @bootstrap.NativeBootstrapIssue] {
  match self.require_backing_borrow_current(scope) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let backing = match self.original_backing() {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  backing.ensure_backing_capacity(self, scope.original, bytes)
}

///|
/// Same installed Root, at the actual selected child-allocation boundary.
/// Bytes describe its C payload geometry, never a maximum-policy reservation.
pub fn InstalledArenaHost::grow_backing_for_allocation(
  self : InstalledArenaHost,
  scope : InstalledArenaBackingBorrow,
  payload_bytes : Int64,
) -> Result[Unit, @bootstrap.NativeBootstrapIssue] {
  match self.require_backing_borrow_current(scope) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let backing = match self.original_backing() {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  backing.grow_backing_for_allocation(self, scope.original, payload_bytes)
}
