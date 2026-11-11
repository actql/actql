///|
// Closed installed assembly: the prepared branch borrows the exact existing
// body debit. Its private predicate captures original admission/Prepared/Ledger,
// never a caller-supplied callback, amount-only proof or second byte token.
priv enum NonModelWorkEntryCapacity {
  DedicatedNonModelWorkCapacity(@resources.CapacityReservation)
  PreparedNonModelWorkCapacity((Int64, Int64) -> Bool)
  RetiredPreparedNonModelWorkCapacity
}

///|
/// A pre-owned byte reservation or prepared-body view on this exact execution,
/// not a Run,
/// Model census, scope owner or physical retirement acknowledgement. All fields
/// and the view are allocated in the same original Host Read preparation.
struct InstalledArenaNonModelWorkEntry {
  original : Ref[InstalledArenaNonModelWorkEntry?]
  host : InstalledArenaHost
  pair : InstalledArenaLocalHostResources
  read : InstalledArenaOriginalRead
  execution : InstalledArenaRetainedExecution
  ledger : @resources.Ledger
  mut control : NonModelWorkEntryCapacity
  ledger_view : @resources.Ledger?
  mut retained_bytes : Int64
  mut execution_bytes : Int64
  mut growing : Bool
  mut constructor_entered : Bool
  mut claimed : Bool
  mut finished : Bool
  mut settled : Bool
  mut closed : Bool
}

///|
pub(all) enum InstalledArenaNonModelWorkEntryIssue {
  Unavailable
  Resource(@resources.LedgerIssue)
  Domain(@bootstrap.NativeBackedExecutionIssue)
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
    control: DedicatedNonModelWorkCapacity(control),
    ledger_view: Some(ledger),
    retained_bytes,
    execution_bytes,
    growing: false,
    constructor_entered: false,
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
/// Borrow the SAME prepared body's reservation for one fixed Native Work.
/// The complete additional Work envelope is supplied before its constructor.
/// No second reservation, admission, attempt or physical cleanup owner exists.
/// A failed resize retains this entry as cleanup-only, never silently retries.
pub fn[P] InstalledArenaHost::prepare_domain_nonmodel_prepared_work_entry(
  self : InstalledArenaHost,
  pair : InstalledArenaLocalHostResources,
  read : InstalledArenaOriginalRead,
  execution : InstalledArenaRetainedExecution,
  admission : @resources.PreparedRunAdmission[P],
  prepared : P,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[
  InstalledArenaNonModelWorkEntryAcquisition,
  InstalledArenaNonModelWorkEntryIssue,
]? {
  if !self.nonmodel_entry_scopes_match(pair, read, execution, false, false) {
    return None
  }
  guard !execution.nonmodel_prepared_work_selected &&
    retained_bytes > 0L &&
    execution_bytes > 0L &&
    execution.ledger is Some(ledger) else {
    return Some(Err(Unavailable))
  }
  let (base_r, base_e) = match
    @resources.prepared_run_native_capacity(admission, prepared, ledger) {
    Err(_) => return Some(Err(Unavailable))
    Ok(value) => value
  }
  // The original grow below owns isolation and current exactly once. Do not
  // precede it with the callbackful admission/usage observer.
  if retained_bytes > 9223372036854775807L - base_r ||
    execution_bytes > 9223372036854775807L - base_e {
    return Some(Err(Unavailable))
  }
  let target_r = base_r + retained_bytes
  let target_e = base_e + execution_bytes
  // Retain the original binding before the only callbackful grow. This view
  // can be dropped only after its own logical children close; it cannot ACK C.
  let entry : InstalledArenaNonModelWorkEntry = {
    original: Ref(None),
    host: self,
    pair,
    read,
    execution,
    ledger,
    control: PreparedNonModelWorkCapacity((r, e) => {
      if r != retained_bytes || e != execution_bytes {
        return false
      }
      match
        @resources.prepared_run_native_capacity(admission, prepared, ledger) {
        Err(_) => false
        Ok((actual_r, actual_e)) => actual_r >= target_r && actual_e >= target_e
      }
    }),
    ledger_view: Some(ledger),
    retained_bytes,
    execution_bytes,
    growing: true,
    constructor_entered: false,
    claimed: false,
    finished: false,
    settled: false,
    closed: false,
  }
  entry.original.val = Some(entry)
  execution.nonmodel_prepared_work_selected = true
  let grown = @resources.reserve_prepared_run_native_work_capacity(
    admission, prepared, ledger, target_r, target_e,
  )
  entry.growing = false
  if grown is Ok(_) &&
    self.nonmodel_entry_scopes_match(pair, read, execution, false, false) &&
    entry.capacity_original_matches() {
    Some(Ok(ReadyNonModelWorkEntry(entry)))
  } else {
    entry.finished = true
    entry.control = RetiredPreparedNonModelWorkCapacity
    Some(Ok(PendingNonModelWorkEntry(entry)))
  }
}

///|
// Dedicated tokens use their original nominal check. Prepared views execute
// only the private pure original-extent getter inside their funded boundary;
// no external current callback or mutable Ledger borrower is introduced.
fn InstalledArenaNonModelWorkEntry::capacity_original_matches(
  self : Self,
) -> Bool {
  match self.control {
    DedicatedNonModelWorkCapacity(control) =>
      @resources.capacity_reservation_matches(
        self.ledger,
        control,
        self.retained_bytes,
        self.execution_bytes,
      )
    PreparedNonModelWorkCapacity(matches) =>
      matches(self.retained_bytes, self.execution_bytes)
    RetiredPreparedNonModelWorkCapacity => false
  }
}

///|
/// Grow the SAME unclaimed constructor reservation before the next original
/// phase. No second Ledger, reservation, attempt or borrower view is issued.
/// Constructor payload already returned from the business scope remains held;
/// only byte demand grows. A failed/current/reentrant return keeps the original
/// token and physical cleanup responsibility, never a refund or replacement.
pub fn InstalledArenaNonModelWorkEntry::grow_in_original_read(
  self : InstalledArenaNonModelWorkEntry,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[Unit, InstalledArenaNonModelWorkEntryIssue] {
  guard self.is_original() &&
    !self.closed &&
    !self.growing &&
    !self.claimed &&
    !self.finished &&
    !self.settled &&
    retained_bytes >= self.retained_bytes &&
    execution_bytes >= self.execution_bytes &&
    self.host.nonmodel_entry_scopes_match(
      self.pair,
      self.read,
      self.execution,
      false,
      false,
    ) &&
    self.owns_only_control() else {
    return Err(Unavailable)
  }
  guard self.control is DedicatedNonModelWorkCapacity(control) else {
    return Err(Unavailable)
  }
  self.growing = true
  defer {
    self.growing = false
  }
  match
    @resources.grow_capacity_reservation(
      self.ledger,
      control,
      retained_bytes,
      execution_bytes,
    ) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  // Preserve the actual successful debit even if the original callback spent
  // this enclosing scope. Later cleanup settles this exact grown token.
  self.retained_bytes = retained_bytes
  self.execution_bytes = execution_bytes
  if !self.is_original() ||
    self.closed ||
    self.claimed ||
    self.finished ||
    self.settled ||
    !self.host.nonmodel_entry_scopes_match(
      self.pair,
      self.read,
      self.execution,
      false,
      false,
    ) ||
    !self.owns_only_control() {
    return Err(Unavailable)
  }
  Ok(())
}

///|
// The default constructor keeps its pristine, unclaimed contract. A physical
// response continuation can supply ONLY this original entry's already issued
// Ledger view in the same entered business scope. Capacity growth still spends
// the same reservation and preserves every attempt/transfer/holding counter.
fn InstalledArenaNonModelWorkEntry::constructor_capacity_original(
  self : Self,
  ledger : @resources.Ledger?,
) -> Bool {
  match ledger {
    None => !self.claimed && self.owns_only_control()
    Some(original) =>
      self.claimed &&
      self.ledger_view is Some(view) &&
      physical_equal(original, view) &&
      physical_equal(original, self.ledger) &&
      self.capacity_original_matches()
  }
}

///|
/// Fund a constructor inside this SAME original business scope before its
/// first allocation. Actual contiguous placement is independent of the R/E
/// envelope. The existing backing owner checks policy/current, acquires and
/// publishes real storage; only then does the SAME byte token grow.
/// No Ledger view, new reservation, attempt or original Read is issued.
pub fn InstalledArenaNonModelWorkEntry::prepare_constructor_in_entered_scope(
  self : InstalledArenaNonModelWorkEntry,
  retained_bytes : Int64,
  execution_bytes : Int64,
  contiguous_bytes : Int64,
  entered_ledger? : @resources.Ledger? = None,
) -> Result[Unit, InstalledArenaNonModelWorkEntryIssue] {
  guard self.is_original() &&
    !self.closed &&
    !self.growing &&
    !self.finished &&
    !self.settled &&
    retained_bytes >= self.retained_bytes &&
    execution_bytes >= self.execution_bytes &&
    contiguous_bytes > 0L &&
    self.constructor_capacity_original(entered_ledger) &&
    self.execution.live is Some(live) &&
    self.host.nonmodel_entry_scopes_match(
      self.pair,
      self.read,
      self.execution,
      true,
      false,
    ) else {
    return Err(Unavailable)
  }
  guard self.control is DedicatedNonModelWorkCapacity(control) else {
    return Err(Unavailable)
  }
  self.growing = true
  defer {
    self.growing = false
  }
  // Keep the attempted constructor/physical growth even if a current callback
  // refuses. A later unclaimed cancellation must not refund retained payload.
  self.constructor_entered = true
  match
    self.execution.domain.backing.prepare_backed_original_read_working(
      self.host,
      live,
      self.execution,
      retained_bytes,
      execution_bytes,
      contiguous_bytes,
    ) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  match
    @resources.grow_capacity_reservation(
      self.ledger,
      control,
      retained_bytes,
      execution_bytes,
    ) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  self.retained_bytes = retained_bytes
  self.execution_bytes = execution_bytes
  if !self.is_original() ||
    self.closed ||
    self.finished ||
    self.settled ||
    !self.constructor_capacity_original(entered_ledger) ||
    !self.host.nonmodel_entry_scopes_match(
      self.pair,
      self.read,
      self.execution,
      true,
      false,
    ) {
    return Err(Unavailable)
  }
  Ok(())
}

///|
/// Match the original Host/Read tuple only inside this already retained
/// constructor's business scope. No callback or new admission is performed.
/// A copied token, other Read or later IO/Ledger borrower cannot use this view.
pub fn InstalledArenaNonModelWorkEntry::constructor_scope_for(
  self : InstalledArenaNonModelWorkEntry,
  host : InstalledArenaHost,
  pair : InstalledArenaLocalHostResources,
  read : InstalledArenaOriginalRead,
) -> Bool {
  self.is_original() &&
  self.constructor_entered &&
  !self.growing &&
  !self.claimed &&
  !self.finished &&
  !self.settled &&
  !self.closed &&
  physical_equal(self.host, host) &&
  physical_equal(self.pair, pair) &&
  physical_equal(self.read, read) &&
  self.owns_only_control() &&
  self.host.nonmodel_entry_scopes_match(
    self.pair,
    self.read,
    self.execution,
    true,
    false,
  )
}

///|
/// Return the preallocated Ledger view only in the exact funded business scope.
/// Invalid/copy/reused calls refuse before the private prepared-extent getter.
/// That getter allocates bounded DATA but never observes external current.
/// This never weakens the ordinary entered-only Ledger-borrow API.
pub fn InstalledArenaNonModelWorkEntry::take_entered_ledger(
  self : InstalledArenaNonModelWorkEntry,
  execution : InstalledArenaRetainedExecution,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> @resources.Ledger? {
  if !self.is_original() ||
    self.closed ||
    self.growing ||
    self.claimed ||
    self.finished ||
    !physical_equal(self.execution, execution) ||
    self.retained_bytes != retained_bytes ||
    self.execution_bytes != execution_bytes ||
    !self.host.nonmodel_entry_scopes_match(
      self.pair,
      self.read,
      execution,
      true,
      false,
    ) ||
    !self.capacity_original_matches() {
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
    !(self.control is DedicatedNonModelWorkCapacity(_)) ||
    !self.capacity_original_matches() {
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
/// external current callback, admission, scope transition or cleanup ACK occurs.
pub fn InstalledArenaNonModelWorkEntry::matches_business_scope(
  self : InstalledArenaNonModelWorkEntry,
  cleanup : Bool,
) -> Bool {
  self.is_original() &&
  !self.closed &&
  !self.settled &&
  self.claimed &&
  (cleanup || !self.finished) &&
  self.host.nonmodel_entry_scopes_match(
    self.pair,
    self.read,
    self.execution,
    true,
    cleanup,
  ) &&
  (
    (
      cleanup &&
      self.finished &&
      self.control is RetiredPreparedNonModelWorkCapacity
    ) ||
    self.capacity_original_matches()
  )
}

///|
/// Publication observes this same claimed entry; execution and constructors
/// retain their separate business-only gate. This grants no current or entry.
pub fn InstalledArenaNonModelWorkEntry::matches_publication_scope(
  self : InstalledArenaNonModelWorkEntry,
) -> Bool {
  self.matches_business_scope(false) ||
  (
    self.is_original() &&
    !self.closed &&
    !self.settled &&
    !self.growing &&
    self.claimed &&
    !self.finished &&
    self.host.nonmodel_entry_scopes_match(
      self.pair,
      self.read,
      self.execution,
      false,
      false,
    ) &&
    self.capacity_original_matches()
  )
}

///|
/// Record only completion of this borrower's logical children. It does not
/// settle capacity, leave a scope or acknowledge a C context. A prepared-body
/// view drops its heavy original binding here before parent retirement.
pub fn InstalledArenaNonModelWorkEntry::finish_business_cleanup(
  self : InstalledArenaNonModelWorkEntry,
) -> Bool {
  if !self.is_original() ||
    self.closed ||
    self.growing ||
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
  if self.control is PreparedNonModelWorkCapacity(_) {
    self.control = RetiredPreparedNonModelWorkCapacity
  }
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
    self.growing ||
    self.constructor_entered ||
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
  guard self.control is DedicatedNonModelWorkCapacity(control) else {
    self.control = RetiredPreparedNonModelWorkCapacity
    self.closed = true
    self.original.val = None
    return true
  }
  match @resources.settle_capacity(self.ledger, control) {
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
  if self.control is PreparedNonModelWorkCapacity(_) {
    return false
  }
  if self.control is RetiredPreparedNonModelWorkCapacity {
    if !self.is_original() ||
      self.growing ||
      (self.claimed && !self.finished) ||
      !self.execution.physical_retired ||
      !self.execution.reported ||
      !self.execution.closed {
      return false
    }
    self.closed = true
    self.original.val = None
    return true
  }
  guard self.control is DedicatedNonModelWorkCapacity(control) else {
    return false
  }
  if !self.is_original() ||
    self.growing ||
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
    match @resources.settle_capacity(self.ledger, control) {
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
