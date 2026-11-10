///|
/// A pre-owned byte reservation on this exact existing execution, not a Run,
/// Model census, scope owner or physical retirement acknowledgement. All fields
/// and the token are allocated in the same original Host Read preparation.
struct InstalledArenaNonModelWorkEntry {
  original : Ref[InstalledArenaNonModelWorkEntry?]
  host : InstalledArenaHost
  pair : InstalledArenaLocalHostResources
  read : InstalledArenaOriginalRead
  execution : InstalledArenaRetainedExecution
  ledger : @resources.Ledger
  control : @resources.CapacityReservation
  ledger_view : @resources.Ledger?
  retained_bytes : Int64
  execution_bytes : Int64
  mut claimed : Bool
  mut finished : Bool
  mut settled : Bool
  mut closed : Bool
}

///|
pub(all) enum InstalledArenaNonModelWorkEntryIssue {
  Unavailable
  Resource(@resources.LedgerIssue)
}

///|
pub(all) enum InstalledArenaNonModelWorkEntryAcquisition {
  ReadyNonModelWorkEntry(InstalledArenaNonModelWorkEntry)
  PendingNonModelWorkEntry(InstalledArenaNonModelWorkEntry)
}

///|
// No callback, Result, tuple, snapshot or capturing collection iterator. This
// observes the retained enclosing Read cut; it does not issue another current
// proof. The canonical reservation still checks its imported original owner.
fn InstalledArenaHost::nonmodel_entry_scopes_match(
  self : InstalledArenaHost,
  pair : InstalledArenaLocalHostResources,
  read : InstalledArenaOriginalRead,
  execution : InstalledArenaRetainedExecution,
  business : Bool,
  cleanup : Bool,
) -> Bool {
  let domain = execution.domain
  if !physical_equal(pair.host, self) ||
    !physical_equal(pair.read, read) ||
    !physical_equal(read.domain.host, self) ||
    !physical_equal(domain.host, self) ||
    physical_equal(read.domain, domain) ||
    !(self.local_host_resources is Some(original) &&
    physical_equal(original, pair)) ||
    !(domain.retained_execution is Some(original) &&
    physical_equal(original, execution)) ||
    !(read.domain.original_read is Some(original) &&
    physical_equal(original, read)) ||
    pair.closed ||
    read.closed ||
    domain.closed ||
    read.domain.closed ||
    execution.closed ||
    execution.physical_retired ||
    !execution.owns_read ||
    execution.active != business {
    return false
  }
  guard read.consumer is Some(consumer) &&
    read.workspace is Some(workspace) &&
    physical_equal(consumer.workspace, workspace) &&
    physical_equal(consumer.host, self) &&
    physical_equal(consumer.read, read) &&
    read.domain.domain is Some(read_domain) &&
    domain.domain is Some(business_domain) else {
    return false
  }
  if !cleanup &&
    (
      pair.closing ||
      read.closing ||
      !read.ready ||
      execution.closing ||
      execution.scope_failed ||
      !execution.ready ||
      consumer.scope !=
      (if business { ConsumerScopeLeft } else { ConsumerScopeOpen })
    ) {
    return false
  }
  if (business && pair.active is Some(_)) ||
    (!business && !(pair.active is Some(HostRead))) {
    return false
  }
  read.domain.backing.original_backed_read_scope_matches(
    self,
    read_domain,
    read.domain,
    !business,
  ) &&
  domain.backing.original_backed_read_scope_matches(
    self, business_domain, domain, business,
  )
}

///|
/// Primitive observation of the enclosing original Read cut only. It grants
/// no current/admission, Ledger, scope entry or capacity.
pub fn InstalledArenaHost::matches_nonmodel_work_entry_read_scope(
  self : InstalledArenaHost,
  pair : InstalledArenaLocalHostResources,
  read : InstalledArenaOriginalRead,
  execution : InstalledArenaRetainedExecution,
) -> Bool {
  self.nonmodel_entry_scopes_match(pair, read, execution, false, false)
}

///|
fn nonmodel_entry_pristine(ledger : @resources.Ledger) -> Bool {
  let usage = @resources.ledger_usage(ledger)
  usage.planning_work == 0 &&
  usage.attempts == 0 &&
  usage.reserved_attempts == 0 &&
  usage.holdings == 0 &&
  usage.live_reservations == 0 &&
  usage.live_delegations == 0 &&
  usage.transferred_bytes == 0L &&
  usage.uncertain_transfer_bytes == 0L &&
  usage.reserved_transfer_bytes == 0L &&
  usage.held_bytes == 0L &&
  usage.reserved_retention_bytes == 0L &&
  usage.reserved_execution_bytes == 0L
}

///|
/// Trusted original-Read preparation only. Its previously admitted complete
/// consumer envelope must include the named entry preparation inventory. The
/// existing business Ledger is never returned in this scope. A post-reserve
/// refusal retains the same token in Pending; it cannot silently refund it.
pub fn InstalledArenaHost::prepare_domain_nonmodel_work_entry(
  self : InstalledArenaHost,
  pair : InstalledArenaLocalHostResources,
  read : InstalledArenaOriginalRead,
  execution : InstalledArenaRetainedExecution,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[
  InstalledArenaNonModelWorkEntryAcquisition,
  InstalledArenaNonModelWorkEntryIssue,
]? {
  if !self.nonmodel_entry_scopes_match(pair, read, execution, false, false) {
    return None
  }
  if retained_bytes <= 0L || execution_bytes <= 0L {
    return Some(Err(Unavailable))
  }
  guard execution.ledger is Some(ledger) && nonmodel_entry_pristine(ledger) else {
    return Some(Err(Unavailable))
  }
  let control = match
    @resources.reserve_capacity(ledger, retained_bytes, execution_bytes) {
    Err(issue) => return Some(Err(Resource(issue)))
    Ok(value) => value
  }
  let entry : InstalledArenaNonModelWorkEntry = {
    original: Ref(None),
    host: self,
    pair,
    read,
    execution,
    ledger,
    control,
    ledger_view: Some(ledger),
    retained_bytes,
    execution_bytes,
    claimed: false,
    finished: false,
    settled: false,
    closed: false,
  }
  entry.original.val = Some(entry)
  if self.nonmodel_entry_scopes_match(pair, read, execution, false, false) &&
    @resources.capacity_reservation_matches(
      ledger, control, retained_bytes, execution_bytes,
    ) {
    Some(Ok(ReadyNonModelWorkEntry(entry)))
  } else {
    // Failed normal entry remains cleanup-only on this exact token.
    entry.finished = true
    Some(Ok(PendingNonModelWorkEntry(entry)))
  }
}

///|
/// Return a preallocated view only in the exact funded business scope. Invalid
/// and reused calls return inline None before any allocating current observer.
/// This never weakens the ordinary entered-only Ledger-borrow API.
pub fn InstalledArenaNonModelWorkEntry::take_entered_ledger(
  self : InstalledArenaNonModelWorkEntry,
  execution : InstalledArenaRetainedExecution,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> @resources.Ledger? {
  if !self.is_original() ||
    self.closed ||
    self.claimed ||
    self.finished ||
    !physical_equal(self.execution, execution) ||
    self.retained_bytes != retained_bytes ||
    self.execution_bytes != execution_bytes ||
    !@resources.capacity_reservation_matches(
      self.ledger,
      self.control,
      retained_bytes,
      execution_bytes,
    ) ||
    !self.host.nonmodel_entry_scopes_match(
      self.pair,
      self.read,
      execution,
      true,
      false,
    ) {
    return None
  }
  self.claimed = true
  self.ledger_view
}

///|
/// The exact opaque byte token, not a count-only or equal-size impostor.
pub fn InstalledArenaNonModelWorkEntry::owns_only_control(
  self : InstalledArenaNonModelWorkEntry,
) -> Bool {
  if !self.is_original() ||
    self.closed ||
    !@resources.capacity_reservation_matches(
      self.ledger,
      self.control,
      self.retained_bytes,
      self.execution_bytes,
    ) {
    return false
  }
  let usage = @resources.ledger_usage(self.ledger)
  usage.planning_work == 0 &&
  usage.attempts == 0 &&
  usage.reserved_attempts == 0 &&
  usage.holdings == 0 &&
  usage.live_reservations == 1 &&
  usage.live_delegations == 0 &&
  usage.transferred_bytes == 0L &&
  usage.uncertain_transfer_bytes == 0L &&
  usage.reserved_transfer_bytes == 0L &&
  usage.held_bytes == 0L &&
  usage.reserved_retention_bytes == self.retained_bytes &&
  usage.reserved_execution_bytes == self.execution_bytes
}

///|
/// Observe only this original token's already-entered business scope. No
/// callback, allocation, admission, scope transition or cleanup ACK occurs.
pub fn InstalledArenaNonModelWorkEntry::matches_business_scope(
  self : InstalledArenaNonModelWorkEntry,
  cleanup : Bool,
) -> Bool {
  self.is_original() &&
  !self.closed &&
  !self.settled &&
  self.claimed &&
  (cleanup || !self.finished) &&
  @resources.capacity_reservation_matches(
    self.ledger,
    self.control,
    self.retained_bytes,
    self.execution_bytes,
  ) &&
  self.host.nonmodel_entry_scopes_match(
    self.pair,
    self.read,
    self.execution,
    true,
    cleanup,
  )
}

///|
/// Record only completion of this borrower's logical children. It does not
/// settle capacity, leave a scope, retire aliases or acknowledge a C context.
pub fn InstalledArenaNonModelWorkEntry::finish_business_cleanup(
  self : InstalledArenaNonModelWorkEntry,
) -> Bool {
  if !self.is_original() ||
    self.closed ||
    !self.claimed ||
    !self.host.nonmodel_entry_scopes_match(
      self.pair,
      self.read,
      self.execution,
      true,
      true,
    ) {
    return false
  }
  self.finished = true
  true
}

///|
/// Abandon only a never-entered entry. Its entire constructor/token inventory
/// belongs to the original Read, and no business allocation has borrowed it.
pub fn InstalledArenaNonModelWorkEntry::cancel_unclaimed_in_original_read(
  self : InstalledArenaNonModelWorkEntry,
) -> Bool {
  if self.closed {
    return true
  }
  if !self.is_original() ||
    self.claimed ||
    !self.host.nonmodel_entry_scopes_match(
      self.pair,
      self.read,
      self.execution,
      false,
      true,
    ) {
    return false
  }
  match @resources.settle_capacity(self.ledger, self.control) {
    Err(_) => false
    Ok(_) => {
      self.closed = true
      self.original.val = None
      true
    }
  }
}

///|
/// Existing outer cleanup boundary only. A never-claimed entry has no
/// borrower children; it still requires the SAME actual C retirement below.
/// Actual C retirement refuses escaped
/// closed Work/export aliases while this exact debit remains live. Only after
/// that original ACK may settlement precede the existing report/parent return.
pub fn InstalledArenaNonModelWorkEntry::close_after_original_return(
  self : InstalledArenaNonModelWorkEntry,
) -> Bool {
  if self.closed {
    return true
  }
  if !self.is_original() ||
    retained_execution_control_scope_clear_ffi() != 1 ||
    (self.claimed && !self.finished) ||
    self.execution.active ||
    !self.finalization_owns_report() {
    return false
  }
  match self.host.retire_retained_execution_context(self.execution) {
    Err(_) => return false
    Ok(_) => ()
  }
  if !self.execution.physical_retired {
    return false
  }
  if !self.settled {
    match @resources.settle_capacity(self.ledger, self.control) {
      Err(_) => return false
      Ok(_) => self.settled = true
    }
  }
  match self.host.close_domain_retained_execution(self.execution) {
    Err(_) => false
    Ok(_) => {
      self.closed = true
      self.original.val = None
      true
    }
  }
}

///|
fn InstalledArenaNonModelWorkEntry::is_original(
  self : InstalledArenaNonModelWorkEntry,
) -> Bool {
  self.original.val is Some(original) && physical_equal(original, self)
}

///|
/// This is only the recorded child cleanup fact, never physical retirement.
pub fn InstalledArenaNonModelWorkEntry::business_cleanup_complete(
  self : InstalledArenaNonModelWorkEntry,
) -> Bool {
  self.is_original() && self.claimed && self.finished
}

///|
/// Immutable original accounting DATA, with no new Ledger borrowing grant.
pub fn InstalledArenaNonModelWorkEntry::usage(
  self : InstalledArenaNonModelWorkEntry,
) -> @resources.LedgerUsage {
  @resources.ledger_usage(self.ledger)
}

///|
fn InstalledArenaNonModelWorkEntry::finalization_owns_report(
  self : InstalledArenaNonModelWorkEntry,
) -> Bool {
  !self.execution.reported || self.settled
}
