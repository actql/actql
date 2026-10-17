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
#borrow(domain)
extern "C" fn prepare_live_channel_ffi(
  domain : PhysicalExtentDomain,
  read_fd : Int,
  write_fd : Int,
  nonce : Int64,
) -> PhysicalLiveChannel = "actql_bootstrap_prepare_live_channel"

///|
#borrow(channel)
extern "C" fn bind_live_child_ffi(
  channel : PhysicalLiveChannel,
  child : Int,
) -> Int = "actql_bootstrap_bind_live_child"

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
extern "C" fn live_baseline_bytes_ffi(
  channel : PhysicalLiveChannel,
  ordinal : Int,
) -> Int64 = "actql_bootstrap_live_baseline_bytes"

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
  mut child_binding_attempted : Bool
  mut binding_attempted : Bool
  mut bound : Bool
  // Resource projection and actual VM admission are separate original steps.
  mut admitted : Bool
  mut ledger_attempted : Bool
  mut ledger_frame : @resources.ImportedChildLedger?
  mut original_ledger : @resources.Ledger?
  mut envelope_attempted : Bool
  mut envelope : @resources.CapacityReservation?
  mut envelope_retired : Bool
  // Ending parent transport use is distinct from child/process or metadata
  // retirement. Keep the original frame and all cleanup responsibility.
  mut transport_stopped : Bool
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
  self.capture_backed_live_channel(
    original,
    domain,
    child,
    Some(child_pid),
    read_fd,
    write_fd,
    nonce,
  )
}

///|
/// Retain the same original domain/ticket and actual borrowed pipes BEFORE
/// spawn. Complete process/FD/control funding remains a separate requirement.
/// Preparation issues no child/VM/launch/Source/Model authority. Missing pipes
/// refuse with the same pending carrier; no descriptor is opened or duplicated.
pub fn[T, C] NativeHostBootstrap::prepare_backed_live_channel_before_spawn(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
  read_fd : Int,
  write_fd : Int,
  nonce : Int64,
) -> Result[
  NativeBackedLiveChannelAcquisition[T, C],
  NativeBackedExecutionIssue,
] {
  self.capture_backed_live_channel(
    original,
    domain,
    child,
    None,
    read_fd,
    write_fd,
    nonce,
  )
}

///|
fn[T, C] NativeHostBootstrap::capture_backed_live_channel(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
  child_pid : Int?,
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
    child_binding_attempted: child_pid is Some(_),
    binding_attempted: false,
    bound: false,
    admitted: false,
    ledger_attempted: false,
    ledger_frame: None,
    original_ledger: None,
    envelope_attempted: false,
    envelope: None,
    envelope_retired: false,
    transport_stopped: false,
    retired: false,
  }
  // Existing domain custody precedes any fallible physical or access capture.
  domain.live_channel_attempted = true
  domain.live_channel = Some(record)
  let physical = match child_pid {
    Some(pid) =>
      capture_live_channel_ffi(domain.physical, pid, read_fd, write_fd, nonce)
    None => prepare_live_channel_ffi(domain.physical, read_fd, write_fd, nonce)
  }
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
fn[T, C] NativeHostBootstrap::require_live_channel_open(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChannel[T, C],
) -> Result[Unit, NativeBackedExecutionIssue] {
  match self.original_live_channel(original, record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if record.transport_stopped {
    return Err(Bootstrap(Closing))
  }
  self.require_domain_current(original, record.domain, record.child)
}

///|
/// Restrict fresh transport work before the existing FD Owner takes back its
/// borrowed endpoints. The serialized caller must separately finish actual
/// in-flight I/O and return its original endpoint borrow. This does not close
/// any FD, prove child stop, retire metadata, return backing or settle quota.
/// Failed logical stop keeps this same restriction and original frame outcome.
pub fn[T, C] NativeHostBootstrap::stop_backed_live_channel_transport_use(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChannel[T, C],
) -> Result[Unit, NativeBackedOriginalReadIssue] {
  match self.original_live_channel(original, record) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  record.transport_stopped = true
  match record.ledger_frame {
    Some(frame) =>
      @resources.stop_imported_child_ledger(frame).map_err(issue => Child(issue))
    None =>
      match record.live {
        None => Ok(())
        Some(_) =>
          self
          .stop_backed_live_channel(original, record)
          .map_err(issue => Domain(issue))
      }
  }
}

///|
/// The same process Owner binds its actual spawned child once. PID DATA does
/// not prove inherited memory, VM admission, stop or descriptor retirement.
/// Retain the original channel on response loss; never retry with another PID.
pub fn[T, C] NativeHostBootstrap::bind_backed_live_channel_child(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChannel[T, C],
  child_pid : Int,
) -> Result[Unit, NativeBackedExecutionIssue] {
  match self.original_live_channel(original, record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match self.require_live_channel_open(original, record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if record.child_binding_attempted {
    return Err(Bootstrap(AlreadyConsumed))
  }
  record.child_binding_attempted = true
  guard record.physical is Some(physical) else {
    return Err(Bootstrap(Unavailable))
  }
  let status = bind_live_child_ffi(physical, child_pid)
  if status != 0 {
    return Err(Bootstrap(Physical(status)))
  }
  self.require_live_channel_open(original, record)
}

///|
/// Trusted same-parent resource assembly before bootstrap, with the original
/// transferred domain/ticket and actual prepared pipes. No scalar limits,
/// callbacks, VM/Host baseline or launch permission enter this issuer. The
/// same channel retains a partial frame on lost reply/current postcheck.
pub fn[T, C] NativeHostBootstrap::prepare_backed_original_channel_ledger(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChannel[T, C],
) -> Result[@resources.ImportedChildLedger, NativeBackedOriginalReadIssue] {
  match self.original_live_channel(original, record) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  match self.require_live_channel_open(original, record) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  if record.ledger_attempted || record.admitted {
    return Err(Domain(Bootstrap(AlreadyConsumed)))
  }
  guard record.physical is Some(physical) && record.live is Some(live) else {
    return Err(Domain(Bootstrap(Unavailable)))
  }
  let status = live_channel_status_ffi(physical)
  if status != 0 {
    return Err(Domain(Bootstrap(Physical(status))))
  }
  record.ledger_attempted = true
  let frame = match
    self.prepare_backed_original_live_ledger(original, live, record) {
    Err(issue) => return Err(issue)
    Ok(frame) => frame
  }
  // Original custody precedes postchecks and the foreign reply boundary.
  record.ledger_frame = Some(frame)
  match self.require_live_channel_open(original, record) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  let status = live_channel_status_ffi(physical)
  if status != 0 {
    Err(Domain(Bootstrap(Physical(status))))
  } else {
    Ok(frame)
  }
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
  match self.require_live_channel_open(original, record) {
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
  self.require_live_channel_open(original, record)
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
  match self.require_live_channel_open(original, record) {
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
  if record.admitted {
    return Err(Accounting(@resources.LiveChildAlreadyAdmitted))
  }
  if record.ledger_frame is Some(_) {
    // Its resource projection already exists; this step still requires the
    // actual original child/VM observation above and cannot readmit Common.
    match self.backed_live_child_state(original, live, record) {
      Err(issue) => return Err(issue)
      Ok(@resources.LiveClosing) => return Err(Bootstrap(Closing))
      Ok(@resources.LiveOpen) => ()
    }
  } else {
    match self.admit_backed_live_child(original, live, record) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  record.admitted = true
  match self.require_live_channel_open(original, record) {
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
  match self.require_live_channel_open(original, record) {
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
  if !record.admitted {
    return Err(Bootstrap(Unavailable))
  }
  let state = match self.backed_live_child_state(original, live, record) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  match self.require_live_channel_open(original, record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
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
/// Coverage of the same already funded holding, after admission. Host is the
/// existing Native baseline (including its control prefix), not unused arena
/// space or an allowance for unrelated Python/process/FD/Store domains. These
/// fixed capacities stay retained until the original parent physical ACKs.
pub fn[T, C] NativeHostBootstrap::backed_live_channel_capacities(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChannel[T, C],
) -> Result[(Int64, Int64), NativeBackedExecutionIssue] {
  let limits = match self.backed_live_channel_limits(original, record) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  guard record.physical is Some(physical) else {
    return Err(Bootstrap(Unavailable))
  }
  let vm = live_baseline_bytes_ffi(physical, 0)
  let host = live_baseline_bytes_ffi(physical, 1)
  if vm != 16777216L ||
    host <= 0L ||
    vm > limits.execution_bytes ||
    host > limits.execution_bytes - vm {
    return Err(Bootstrap(Unavailable))
  }
  match self.backed_live_channel_limits(original, record) {
    Err(issue) => Err(issue)
    Ok(current) =>
      if current == limits {
        Ok((vm, host))
      } else {
        Err(Bootstrap(Unavailable))
      }
  }
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
  if record.envelope is Some(_) {
    return Err(Accounting(@resources.CleanupPending))
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
  // Common's same-owner ACK retirement invalidates escaped original frames
  // and breaks their callbacks. Dropping this reference alone is never an ACK.
  record.ledger_frame = None
  record.original_ledger = None
  record.retired = true
  record.domain.live_channel = None
  Ok(())
}
