///|
priv type PhysicalLiveChannel

///|
#borrow(domain)
extern "C" fn capture_live_channel_ffi(
  domain : PhysicalExtentDomain,
  child : Int,
  read_fd : Int,
  write_fd : Int,
  nonce : Int64,
) -> PhysicalLiveChannel = "actql_bootstrap_capture_live_channel"

///|
#borrow(channel)
extern "C" fn live_channel_status_ffi(channel : PhysicalLiveChannel) -> Int = "actql_bootstrap_live_channel_status"

///|
#borrow(channel)
extern "C" fn bind_live_span_ffi(
  channel : PhysicalLiveChannel,
  nonce : Int64,
  offset : Int64,
  bytes : Int64,
) -> Int = "actql_bootstrap_bind_live_span"

///|
#borrow(channel)
extern "C" fn live_vm_current_ffi(channel : PhysicalLiveChannel) -> Int = "actql_bootstrap_live_vm_current"

///|
#borrow(channel)
extern "C" fn retire_live_channel_metadata_ffi(
  channel : PhysicalLiveChannel,
) -> Int = "actql_bootstrap_retire_live_channel_metadata"

///|
/// The original physical caller retains its process/descriptor/frame custody.
/// This record binds it to the existing domain/access; it is not another Owner.
struct NativeBackedLiveChannel[T, C] {
  owner : NativeHostBootstrap[T]
  domain : NativeBackedExecutionDomain[T, C]
  child : C
  nonce : Int64
  mut physical : PhysicalLiveChannel?
  mut live : NativeBackedLiveChild[T, C, NativeBackedLiveChannel[T, C]]?
  mut binding_attempted : Bool
  mut bound : Bool
  mut retired : Bool
}

///|
pub(all) enum NativeBackedLiveChannelAcquisition[T, C] {
  PreparedLiveChannel(NativeBackedLiveChannel[T, C])
  PendingLiveChannel(NativeBackedLiveChannel[T, C], NativeBackedExecutionIssue)
}

///|
/// Trusted installed caller AFTER complete original process/FD/control funding.
/// The caller supplies its actual already-spawned child and borrowed pipe pair;
/// PID/FD/nonce DATA alone cannot construct the original Host/domain/ticket.
/// Capture creates no descriptors and supplies neither launch nor VM permission.
pub fn[T, C] NativeHostBootstrap::prepare_backed_live_channel(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
  child_pid : Int,
  read_fd : Int,
  write_fd : Int,
  nonce : Int64,
) -> Result[
  NativeBackedLiveChannelAcquisition[T, C],
  NativeBackedExecutionIssue,
] {
  match self.require_domain_current(original, domain, child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !domain.transferred {
    return Err(Bootstrap(Unavailable))
  }
  if domain.live_channel_attempted ||
    domain.live_channel is Some(_) ||
    domain.read_use is Some(_) {
    return Err(Bootstrap(AlreadyConsumed))
  }
  let record : NativeBackedLiveChannel[T, C] = {
    owner: self,
    domain,
    child,
    nonce,
    physical: None,
    live: None,
    binding_attempted: false,
    bound: false,
    retired: false,
  }
  // Existing domain custody precedes any fallible physical or access capture.
  domain.live_channel_attempted = true
  domain.live_channel = Some(record)
  let physical = capture_live_channel_ffi(
    domain.physical,
    child_pid,
    read_fd,
    write_fd,
    nonce,
  )
  record.physical = Some(physical)
  let status = live_channel_status_ffi(physical)
  if status != 0 {
    return Ok(PendingLiveChannel(record, Bootstrap(Physical(status))))
  }
  match self.prepare_backed_live_child(original, domain, child, record) {
    Err(issue) => Ok(PendingLiveChannel(record, issue))
    Ok(LiveChildPending(live, issue)) => {
      record.live = Some(live)
      Ok(PendingLiveChannel(record, issue))
    }
    Ok(LiveChildReady(live)) => {
      record.live = Some(live)
      Ok(PreparedLiveChannel(record))
    }
  }
}

///|
fn[T, C] NativeHostBootstrap::original_live_channel(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChannel[T, C],
) -> Result[Unit, NativeBackedExecutionIssue] {
  if !physical_equal(record.owner, self) ||
    record.retired ||
    !(record.domain.live_channel is Some(selected) &&
    physical_equal(selected, record)) {
    return Err(Bootstrap(ForeignOriginal))
  }
  self.original_domain_carrier(original, record.domain, record.child)
}

///|
/// Same private channel only, after validating the original child's Memory
/// observation. Relative DATA is not a public VM/admission constructor. The
/// same caller must check its original channel and physical custody again.
pub fn[T, C] NativeHostBootstrap::bind_backed_live_channel_vm(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChannel[T, C],
  nonce : Int64,
  offset : Int64,
  bytes : Int64,
) -> Result[Unit, NativeBackedExecutionIssue] {
  match self.original_live_channel(original, record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if record.binding_attempted {
    return Err(Bootstrap(AlreadyConsumed))
  }
  match self.require_domain_current(original, record.domain, record.child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  record.binding_attempted = true
  guard record.physical is Some(physical) else {
    return Err(Bootstrap(Unavailable))
  }
  if nonce != record.nonce || bytes != 16777216L {
    return Err(Bootstrap(Unavailable))
  }
  let status = bind_live_span_ffi(physical, nonce, offset, bytes)
  if status != 0 {
    return Err(Bootstrap(Physical(status)))
  }
  record.bound = true
  self.require_domain_current(original, record.domain, record.child)
}

///|
pub fn[T, C] NativeHostBootstrap::admit_backed_live_channel(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChannel[T, C],
) -> Result[Unit, NativeBackedExecutionIssue] {
  match self.original_live_channel(original, record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard record.bound &&
    record.physical is Some(physical) &&
    record.live is Some(live) else {
    return Err(Bootstrap(Unavailable))
  }
  let status = live_vm_current_ffi(physical)
  if status != 0 {
    return Err(Bootstrap(Physical(status)))
  }
  match self.admit_backed_live_child(original, live, record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let status = live_vm_current_ffi(physical)
  if status != 0 {
    Err(Bootstrap(Physical(status)))
  } else {
    Ok(())
  }
}

///|
pub fn[T, C] NativeHostBootstrap::backed_live_channel_state(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChannel[T, C],
) -> Result[@resources.BackedExecutionLiveState, NativeBackedExecutionIssue] {
  match self.original_live_channel(original, record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard record.physical is Some(physical) && record.live is Some(live) else {
    return Err(Bootstrap(Unavailable))
  }
  let status = live_vm_current_ffi(physical)
  if status != 0 {
    return Err(Bootstrap(Physical(status)))
  }
  let state = match self.backed_live_child_state(original, live, record) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let status = live_vm_current_ffi(physical)
  if status != 0 {
    Err(Bootstrap(Physical(status)))
  } else {
    Ok(state)
  }
}

///|
pub fn[T, C] NativeHostBootstrap::backed_live_channel_limits(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChannel[T, C],
) -> Result[@resources.LedgerLimits, NativeBackedExecutionIssue] {
  match self.backed_live_channel_state(original, record) {
    Err(issue) => return Err(issue)
    Ok(@resources.LiveClosing) => return Err(Bootstrap(Closing))
    Ok(@resources.LiveOpen) => ()
  }
  self.backed_live_child_limits(original, record.live.unwrap(), record)
}

///|
/// Original cleanup reporting checks the retained channel lifetime, not new
/// VM admission. Unknown snapshots and all cumulative laws stay in Common.
pub fn[T, C] NativeHostBootstrap::report_backed_live_channel(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChannel[T, C],
  usage : @resources.LedgerUsage,
) -> Result[Unit, NativeBackedExecutionIssue] {
  match self.original_live_channel(original, record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard record.physical is Some(physical) && record.live is Some(live) else {
    return Err(Bootstrap(Unavailable))
  }
  let status = live_channel_status_ffi(physical)
  if status != 0 {
    return Err(Bootstrap(Physical(status)))
  }
  match self.report_backed_live_child(original, live, record, usage) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let status = live_channel_status_ffi(physical)
  if status != 0 {
    Err(Bootstrap(Physical(status)))
  } else {
    Ok(())
  }
}

///|
pub fn[T, C] NativeHostBootstrap::stop_backed_live_channel(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChannel[T, C],
) -> Result[Unit, NativeBackedExecutionIssue] {
  match self.original_live_channel(original, record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard record.live is Some(live) else { return Err(Bootstrap(Unavailable)) }
  self.stop_backed_live_child(original, live, record)
}

///|
/// Existing trusted physical Owner only after same runtime/channel/Store/FD
/// custody retires. This retires references, never returns the original loan.
pub fn[T, C] NativeHostBootstrap::retire_backed_live_channel_after_owner_ack(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChannel[T, C],
) -> Result[Unit, NativeBackedExecutionIssue] {
  match self.original_live_channel(original, record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if record.live is Some(live) {
    match
      self.retire_backed_live_child_after_owner_ack(original, live, record) {
      Err(issue) => return Err(issue)
      Ok(_) => record.live = None
    }
  }
  if record.physical is Some(physical) {
    let status = retire_live_channel_metadata_ffi(physical)
    if status != 0 {
      return Err(Bootstrap(Physical(status)))
    }
    record.physical = None
  }
  record.retired = true
  record.domain.live_channel = None
  Ok(())
}
