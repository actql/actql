///|
/// One original child identity and its existing Owner handles. Partial stages
/// stay with this carrier; no parallel Run/Recovery/cleanup controller is added.
struct InstalledArenaDomain {
  host : InstalledArenaHost
  backing : @bootstrap.NativeHostBootstrap[InstalledArenaHost]
  mut allocation : @bootstrap.NativeBootstrapAllocation[InstalledArenaHost]?
  mut region : @bootstrap.NativeBackedExecutionRegion[
    InstalledArenaHost,
    InstalledArenaDomain,
  ]?
  mut loan : @bootstrap.NativeBackedExecutionLoan[
    InstalledArenaHost,
    InstalledArenaDomain,
  ]?
  mut view : @bootstrap.NativeBackedExecutionView[
    InstalledArenaHost,
    InstalledArenaDomain,
  ]?
  mut domain : @bootstrap.NativeBackedExecutionDomain[
    InstalledArenaHost,
    InstalledArenaDomain,
  ]?
  mut live_channel : @bootstrap.NativeBackedLiveChannel[
    InstalledArenaHost,
    InstalledArenaDomain,
  ]?
  mut crypto_component : InstalledArenaCryptoComponent?
  mut sqlite_library : InstalledArenaSqliteLibrary?
  mut original_read : InstalledArenaOriginalRead?
  mut retained_execution : InstalledArenaRetainedExecution?
  mut process : InstalledArenaProcess?
  mut closed : Bool
}

///|
pub(all) enum InstalledArenaDomainAcquisition {
  PreparedDomain(InstalledArenaDomain)
  PendingDomain(InstalledArenaDomain, @bootstrap.NativeBackedExecutionIssue)
}

///|
/// Trusted installed caller only. Its original scope and FD are borrowed;
/// scalar limits are declarations, not complete process/VM funding or authority.
/// Registration precedes any operation that can publish a partial Core loan.
pub fn InstalledArenaHost::prepare_domain(
  self : InstalledArenaHost,
  scope : InstalledArenaBackingBorrow,
  fd : Int,
  bytes : Int64,
  limits : @resources.LedgerLimits,
) -> Result[
  InstalledArenaDomainAcquisition,
  @bootstrap.NativeBackedExecutionIssue,
] {
  if fd < 0 {
    return Err(@bootstrap.Bootstrap(@bootstrap.Unavailable))
  }
  self.prepare_domain_original(scope, Some(fd), bytes, limits)
}

///|
/// Same anonymous parent allocation, loan and child Ledger. This local view is
/// non-exportable and never owns another mapping or an independent byte credit.
pub fn InstalledArenaHost::prepare_domain_in_process(
  self : InstalledArenaHost,
  scope : InstalledArenaBackingBorrow,
  bytes : Int64,
  limits : @resources.LedgerLimits,
  initial_window? : Int64? = None,
) -> Result[
  InstalledArenaDomainAcquisition,
  @bootstrap.NativeBackedExecutionIssue,
] {
  self.prepare_domain_original(scope, None, bytes, limits, initial_window~)
}

///|
fn InstalledArenaHost::prepare_domain_original(
  self : InstalledArenaHost,
  scope : InstalledArenaBackingBorrow,
  fd : Int?,
  bytes : Int64,
  limits : @resources.LedgerLimits,
  initial_window? : Int64? = None,
) -> Result[
  InstalledArenaDomainAcquisition,
  @bootstrap.NativeBackedExecutionIssue,
] {
  if bytes <= 0L || self.domains.length() >= self.domain_record_limit {
    return Err(@bootstrap.Bootstrap(@bootstrap.Unavailable))
  }
  match self.require_backing_borrow_current(scope) {
    Err(issue) => return Err(@bootstrap.Bootstrap(issue))
    Ok(_) => ()
  }
  let backing = match self.original_backing() {
    Err(issue) => return Err(@bootstrap.Bootstrap(issue))
    Ok(value) => value
  }
  let record : InstalledArenaDomain = {
    host: self,
    backing,
    allocation: None,
    region: None,
    loan: None,
    view: None,
    domain: None,
    live_channel: None,
    crypto_component: None,
    sqlite_library: None,
    original_read: None,
    retained_execution: None,
    process: None,
    closed: false,
  }
  self.domains.push(record)
  match record.prepare_original(scope, fd, bytes, limits, initial_window~) {
    Err(issue) => Ok(PendingDomain(record, issue))
    Ok(_) => Ok(PreparedDomain(record))
  }
}

///|
/// One first execution-only domain inside this same original backing. The
/// byte candidate comes from its already charged actual control allocation;
/// only the following ordinary physical acquire can establish an extent.
/// Retired/partial earlier domain records cannot select a new first attempt.
pub fn InstalledArenaHost::prepare_initial_domain(
  self : InstalledArenaHost,
  scope : InstalledArenaBackingBorrow,
  fd : Int,
  planning_work : Int,
  attempts : Int,
  holdings : Int,
  transfer_bytes : Int64,
) -> Result[
  InstalledArenaDomainAcquisition,
  @bootstrap.NativeBackedExecutionIssue,
] {
  match self.require_backing_borrow_current(scope) {
    Err(issue) => return Err(@bootstrap.Bootstrap(issue))
    Ok(_) => ()
  }
  if !self.domains.is_empty() {
    return Err(@bootstrap.Bootstrap(@bootstrap.AlreadyConsumed))
  }
  let backing = match self.original_backing() {
    Err(issue) => return Err(@bootstrap.Bootstrap(issue))
    Ok(backing) => backing
  }
  let bytes = match backing.initial_payload_capacity(self) {
    Err(issue) => return Err(@bootstrap.Bootstrap(issue))
    Ok(bytes) => bytes
  }
  self.prepare_domain(scope, fd, bytes, {
    planning_work,
    attempts,
    holdings,
    transfer_bytes,
    retained_bytes: 0L,
    execution_bytes: bytes,
  })
}

///|
fn InstalledArenaDomain::prepare_original(
  self : InstalledArenaDomain,
  scope : InstalledArenaBackingBorrow,
  fd : Int?,
  bytes : Int64,
  limits : @resources.LedgerLimits,
  initial_window? : Int64? = None,
) -> Result[Unit, @bootstrap.NativeBackedExecutionIssue] {
  let acquired = match fd {
    Some(_) => self.backing.allocate(self.host, bytes)
    None => self.backing.allocate_in_process_domain(self.host, bytes)
  }
  let allocation = match acquired {
    Err(issue) => return Err(@bootstrap.Bootstrap(issue))
    Ok(value) => value
  }
  self.allocation = Some(allocation)
  let region = match self.backing.issue_backed_region(self.host, allocation) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  self.region = Some(region)
  let extent : @resources.BackedExecutionExtent = {
    offset: 0L,
    length: bytes,
    payload_offset: 0L,
    payload_length: bytes,
  }
  let lent = match fd {
    Some(_) =>
      self.backing.lend_backed_region(
        self.host,
        region,
        scope.original,
        self,
        extent,
        @resources.ExclusiveWrite,
        limits,
        0L,
        0L,
      )
    None =>
      self.backing.lend_backed_region_in_process(
        self.host,
        region,
        scope.original,
        self,
        extent,
        @resources.ExclusiveWrite,
        limits,
        0L,
        0L,
        initial_window~,
      )
  }
  let loan = match lent {
    Err(issue) => return Err(issue)
    Ok(@bootstrap.Pending(value, issue)) => {
      self.loan = Some(value)
      return Err(issue)
    }
    Ok(@bootstrap.Lent(value)) => value
  }
  self.loan = Some(loan)
  let bound = match fd {
    Some(fd) => self.backing.map_backed_view(self.host, loan, self, fd)
    None => self.backing.view_backed_region_in_process(self.host, loan, self)
  }
  let view = match bound {
    Err(issue) => return Err(issue)
    Ok(@bootstrap.PendingView(value, issue)) => {
      self.view = Some(value)
      return Err(issue)
    }
    Ok(@bootstrap.Mapped(value)) => value
  }
  self.view = Some(view)
  let domain = match self.backing.acquire_backed_domain(self.host, view, self) {
    Err(issue) => return Err(issue)
    Ok(@bootstrap.DomainPending(value, issue)) => {
      self.domain = Some(value)
      return Err(issue)
    }
    Ok(@bootstrap.DomainReady(value)) => value
  }
  self.domain = Some(domain)
  Ok(())
}

///|
pub fn InstalledArenaHost::require_domain_current(
  self : InstalledArenaHost,
  record : InstalledArenaDomain,
) -> Result[Unit, @bootstrap.NativeBackedExecutionIssue] {
  if !physical_equal(record.host, self) ||
    record.closed ||
    record.process is Some(_) ||
    !self.domains.any(original => physical_equal(original, record)) {
    return Err(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))
  }
  if self.local_host_resources is Some(resources) &&
    resources.closing &&
    (
      physical_equal(resources.read.domain, record) ||
      physical_equal(resources.sqlite.domain, record)
    ) {
    return Err(@bootstrap.Bootstrap(@bootstrap.Closing))
  }
  match self.original_backing() {
    Err(issue) => return Err(@bootstrap.Bootstrap(issue))
    Ok(backing) =>
      if !physical_equal(backing, record.backing) {
        return Err(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))
      }
  }
  guard record.domain is Some(domain) else {
    return Err(@bootstrap.Bootstrap(@bootstrap.Unavailable))
  }
  record.backing.require_backed_domain_current(self, domain, record)
}

///|
pub fn InstalledArenaHost::transfer_domain(
  self : InstalledArenaHost,
  record : InstalledArenaDomain,
) -> Result[Unit, @bootstrap.NativeBackedExecutionIssue] {
  match self.require_domain_current(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  record.backing.transfer_backed_domain(self, record.domain.unwrap(), record)
}

///|
/// This checked DATA projection is not launch/Store/Run permission. The
/// installed transport keeps this exact record and its original backing loan.
pub fn InstalledArenaHost::project_prepared_domain(
  self : InstalledArenaHost,
  record : InstalledArenaDomain,
) -> Result[
  @bootstrap.NativePreparedDomainTransport,
  @bootstrap.NativeBackedExecutionIssue,
] {
  match self.require_domain_current(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  record.backing.project_prepared_domain(self, record.domain.unwrap(), record)
}

///|
pub fn InstalledArenaHost::enter_domain(
  self : InstalledArenaHost,
  record : InstalledArenaDomain,
) -> Result[Unit, @bootstrap.NativeBackedExecutionIssue] {
  match self.require_domain_current(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  record.backing.enter_backed_domain(self, record.domain.unwrap(), record)
}

///|
pub fn InstalledArenaHost::leave_domain(
  self : InstalledArenaHost,
  record : InstalledArenaDomain,
) -> Result[Unit, @bootstrap.NativeBackedExecutionIssue] {
  if !physical_equal(record.host, self) || record.closed {
    return Err(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))
  }
  guard record.domain is Some(domain) else {
    return Err(@bootstrap.Bootstrap(@bootstrap.Unavailable))
  }
  record.backing.leave_backed_domain(self, domain, record)
}

///|
/// Existing physical borrower calls only AFTER original scoped stop and any
/// independent FD/view uses retire. This method never supplies those facts.
/// Unknown final usage remains conservative in the original Common Owner.
pub fn InstalledArenaHost::close_domain_after_owner_ack(
  self : InstalledArenaHost,
  record : InstalledArenaDomain,
) -> Result[Unit, @bootstrap.NativeBackedExecutionIssue] {
  if !physical_equal(record.host, self) {
    return Err(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))
  }
  if record.closed {
    return Ok(())
  }
  if self.local_host_resources is Some(resources) &&
    !resources.closed &&
    (
      physical_equal(resources.read.domain, record) ||
      physical_equal(resources.sqlite.domain, record)
    ) {
    return Err(@bootstrap.Bootstrap(@bootstrap.ReadersPending))
  }
  if record.process is Some(process) && !process.closed {
    return Err(@bootstrap.Bootstrap(@bootstrap.ReadersPending))
  }
  if record.crypto_component is Some(component) && !component.closed {
    return Err(@bootstrap.Bootstrap(@bootstrap.ReadersPending))
  }
  if record.sqlite_library is Some(library) && !library.closed {
    return Err(@bootstrap.Bootstrap(@bootstrap.ReadersPending))
  }
  if record.original_read is Some(read) && !read.closed {
    return Err(@bootstrap.Bootstrap(@bootstrap.ReadersPending))
  }
  if record.retained_execution is Some(execution) && !execution.closed {
    return Err(@bootstrap.Bootstrap(@bootstrap.ReadersPending))
  }
  if record.domain is Some(domain) {
    match record.backing.close_backed_domain(self, domain, record) {
      Err(issue) => return Err(issue)
      Ok(_) => record.domain = None
    }
  }
  if record.view is Some(view) {
    match record.backing.close_backed_view(self, view, record) {
      Err(issue) => return Err(issue)
      Ok(_) => record.view = None
    }
  }
  if record.loan is Some(loan) {
    match
      record.backing.settle_backed_region_after_owner_ack(
        self,
        loan,
        record,
        None,
      ) {
      Err(issue) => return Err(issue)
      Ok(_) => record.loan = None
    }
  }
  if record.region is Some(region) {
    match record.backing.close_backed_region(self, region) {
      Err(issue) => return Err(issue)
      Ok(false) => return Err(@bootstrap.Bootstrap(@bootstrap.ReadersPending))
      Ok(true) => record.region = None
    }
  }
  if record.allocation is Some(allocation) {
    match record.backing.retire(self, allocation) {
      Err(issue) => return Err(@bootstrap.Bootstrap(issue))
      Ok(_) => record.allocation = None
    }
  }
  // The closed carrier keeps its original domain for nominal identity, so
  // break the reverse registration only after the full domain retirement ACK.
  // Until here it also prevents a second Library attempt in this live domain.
  record.crypto_component = None
  record.sqlite_library = None
  record.original_read = None
  record.retained_execution = None
  record.process = None
  record.closed = true
  Ok(())
}
