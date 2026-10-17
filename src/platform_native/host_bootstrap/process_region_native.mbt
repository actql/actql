///|
priv type PhysicalProcessRegion

///|
#borrow(view, domain)
extern "C" fn capture_process_region_ffi(
  view : PhysicalRegionView,
  domain : PhysicalExtentDomain,
  descriptor : Int,
) -> PhysicalProcessRegion = "actql_bootstrap_capture_process_region"

///|
#borrow(record)
extern "C" fn process_region_status_ffi(record : PhysicalProcessRegion) -> Int = "actql_bootstrap_process_region_status"

///|
#borrow(record)
extern "C" fn abandon_process_region_ffi(record : PhysicalProcessRegion) -> Int = "actql_bootstrap_abandon_prepared_process_region"

///|
#borrow(record)
extern "C" fn retire_process_region_ffi(
  record : PhysicalProcessRegion,
  child : Int,
) -> Int = "actql_bootstrap_retire_stopped_process_region"

///|
/// Same Host/domain/child, bound to the original process holder before spawn.
/// This is cleanup custody, not process/VM funding or permission to launch.
struct NativeBackedProcessRegion[T, C] {
  owner : NativeHostBootstrap[T]
  domain : NativeBackedExecutionDomain[T, C]
  child : C
  holder : @executor.NativeScopedExecutorHolder
  mut channel : NativeBackedLiveChannel[T, C]?
  mut transport : @executor.NativeScopedDuplexBorrow?
  mut physical : PhysicalProcessRegion?
  mut stop : @executor.NativeScopedExecutorStop?
  mut physical_retired : Bool
  mut pin_closed : Bool
  mut retired : Bool
}

///|
pub(all) enum NativeBackedProcessRegionIssue {
  Domain(NativeBackedExecutionIssue)
  Process(@executor.NativeExecutorSlotIssue)
  OriginalChild(@resources.ImportedChildLedgerIssue)
} derive(Eq, Debug)

///|
pub(all) enum NativeBackedProcessRegionAcquisition[T, C] {
  ProcessRegionReady(NativeBackedProcessRegion[T, C])
  ProcessRegionPending(
    NativeBackedProcessRegion[T, C],
    NativeBackedProcessRegionIssue
  )
}

///|
/// Trusted physical assembly after separate process/control/FD funding. The
/// duplicated descriptor belongs to that original finite control envelope.
/// The same prepared holder is retained before fallible physical capture; no
/// arbitrary PID, scalar capacity or caller Boolean can construct a stop proof.
pub fn[T, C] NativeHostBootstrap::bind_prepared_process_region(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
  holder : @executor.NativeScopedExecutorHolder,
  descriptor : Int,
) -> Result[
  NativeBackedProcessRegionAcquisition[T, C],
  NativeBackedProcessRegionIssue,
] {
  match self.require_domain_current(original, domain, child) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  match holder.require_prepared() {
    Err(issue) => return Err(Process(issue))
    Ok(_) => ()
  }
  if !domain.transferred ||
    domain.read_use is Some(_) ||
    domain.live_channel is Some(_) {
    return Err(Domain(Bootstrap(ReadersPending)))
  }
  self.capture_original_process_region(
    domain, child, holder, descriptor, None, None,
  )
}

///|
fn[T, C] NativeHostBootstrap::capture_original_process_region(
  self : NativeHostBootstrap[T],
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
  holder : @executor.NativeScopedExecutorHolder,
  descriptor : Int,
  channel : NativeBackedLiveChannel[T, C]?,
  transport : @executor.NativeScopedDuplexBorrow?,
) -> Result[
  NativeBackedProcessRegionAcquisition[T, C],
  NativeBackedProcessRegionIssue,
] {
  let record : NativeBackedProcessRegion[T, C] = {
    owner: self,
    domain,
    child,
    holder,
    channel,
    transport,
    physical: None,
    stop: None,
    physical_retired: false,
    pin_closed: false,
    retired: false,
  }
  domain.process_region = Some(record)
  let physical = capture_process_region_ffi(
    domain.view.physical,
    domain.physical,
    descriptor,
  )
  record.physical = Some(physical)
  let status = process_region_status_ffi(physical)
  if status == 0 {
    Ok(ProcessRegionReady(record))
  } else {
    Ok(ProcessRegionPending(record, Domain(Bootstrap(Physical(status)))))
  }
}

///|
/// Same original channel/frame and the same process Owner's endpoint borrow.
/// This couples existing custody before spawn; it issues no launch, VM, Core
/// funding or Account permission. A parent Root/Reader context is excluded.
pub fn[T, C] NativeHostBootstrap::bind_prepared_process_channel_region(
  self : NativeHostBootstrap[T],
  original : T,
  channel : NativeBackedLiveChannel[T, C],
  holder : @executor.NativeScopedExecutorHolder,
  transport : @executor.NativeScopedDuplexBorrow,
  descriptor : Int,
) -> Result[
  NativeBackedProcessRegionAcquisition[T, C],
  NativeBackedProcessRegionIssue,
] {
  match self.require_live_channel_open(original, channel) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  let domain = channel.domain
  guard channel.live is Some(live) && channel.ledger_frame is Some(frame) else {
    return Err(Domain(Bootstrap(Unavailable)))
  }
  match self.original_live_child(original, live, channel) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  match self.original_channel_ledger(original, channel, frame) {
    Err(Domain(issue)) => return Err(Domain(issue))
    Err(Child(issue)) => return Err(OriginalChild(issue))
    Ok(_) => ()
  }
  if !domain.transferred || domain.read_attempted || domain.read_retired ||
    domain.read_use is None || domain.process_region is Some(_) ||
    channel.child_binding_attempted || channel.binding_attempted || channel.admitted {
    return Err(Domain(Bootstrap(ReadersPending)))
  }
  match holder.require_prepared() {
    Err(issue) => return Err(Process(issue))
    Ok(_) => ()
  }
  let (writer, reader) = match transport.parent_descriptors(holder) {
    Err(issue) => return Err(Process(issue))
    Ok(value) => value
  }
  guard channel.physical is Some(physical) else {
    return Err(Domain(Bootstrap(Unavailable)))
  }
  let status = match_live_channel_descriptors_ffi(physical, reader, writer)
  if status != 0 {
    return Err(Domain(Bootstrap(Physical(status))))
  }
  self.capture_original_process_region(
    domain, channel.child, holder, descriptor, Some(channel), Some(transport),
  )
}

///|
// Only this exact process/channel association may observe its live domain.
// Generic domain access remains refused while a process region is registered.
fn[T, C] NativeHostBootstrap::require_process_channel_current(
  self : NativeHostBootstrap[T],
  original : T,
  channel : NativeBackedLiveChannel[T, C],
  process : NativeBackedProcessRegion[T, C],
) -> Result[Unit, NativeBackedExecutionIssue] {
  match self.require_region_child(original, channel.domain.view.loan, channel.child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match self.original_process_region(original, process) {
    Err(Domain(issue)) => return Err(issue)
    Err(Process(_)) => return Err(Bootstrap(ReadersPending))
    Err(OriginalChild(_)) => return Err(Bootstrap(ReadersPending))
    Ok(_) => ()
  }
  if !(process.channel is Some(selected) && physical_equal(selected, channel)) ||
    !physical_equal(process.domain, channel.domain) ||
    !physical_equal(process.child, channel.child) {
    return Err(Bootstrap(ForeignOriginal))
  }
  if process.retired || process.physical_retired || process.pin_closed {
    return Err(Bootstrap(Closing))
  }
  guard process.transport is Some(transport) && process.physical is Some(physical) else {
    return Err(Bootstrap(Unavailable))
  }
  if transport.require_current(process.holder) is Err(_) {
    // This refuses a new observation. The original process Owner retains its
    // actual current/close Unknown; this is not a physical cleanup result.
    return Err(Bootstrap(ReadersPending))
  }
  let status = process_region_status_ffi(physical)
  if status != 0 {
    return Err(Bootstrap(Physical(status)))
  }
  let status = domain_status_ffi(process.domain.physical)
  if status != 0 {
    Err(Bootstrap(Physical(status)))
  } else {
    Ok(())
  }
}

///|
/// Use the original process Owner's child, never a caller-supplied PID.
pub fn[T, C] NativeHostBootstrap::bind_process_channel_child(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedProcessRegion[T, C],
) -> Result[Unit, NativeBackedProcessRegionIssue] {
  match self.original_process_region(original, record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard record.channel is Some(channel) else {
    return Err(Domain(Bootstrap(Unavailable)))
  }
  let child = match record.holder.child() {
    Err(issue) => return Err(Process(issue))
    Ok(value) => value
  }
  self.bind_backed_live_channel_child(original, channel, child.pid()).map_err(issue => Domain(issue))
}

///|
/// The serialized caller has ended actual in-flight use after its logical
/// restriction. Return only this same endpoint view, not FD/stop/loan ACKs.
pub fn[T, C] NativeHostBootstrap::return_process_channel_transport(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedProcessRegion[T, C],
) -> Result[Unit, NativeBackedProcessRegionIssue] {
  match self.original_process_region(original, record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard record.channel is Some(channel) && record.transport is Some(transport) else {
    return Err(Domain(Bootstrap(Unavailable)))
  }
  if !channel.transport_stopped {
    return Err(Domain(Bootstrap(ReadersPending)))
  }
  transport.return_transport(record.holder).map_err(issue => Process(issue))
}

///|
// Same physical process/FD/pin ACK already confirmed. Keep logical reporting,
// reservation and alias failures in the original carrier; never re-unmap or
// re-close a completed physical phase to retry this distinct cleanup.
fn[T, C] NativeHostBootstrap::retire_process_channel_metadata(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedProcessRegion[T, C],
) -> Result[Unit, NativeBackedProcessRegionIssue] {
  if record.channel is Some(channel) {
    if !channel.transport_stopped {
      return Err(Domain(Bootstrap(ReadersPending)))
    }
    if channel.ledger_frame is Some(frame) && !channel.envelope_retired {
      match self.retire_backed_channel_bootstrap_after_owner_ack(original, channel, frame) {
        Err(Domain(issue)) => return Err(Domain(issue))
        Err(Child(issue)) => return Err(OriginalChild(issue))
        Ok(_) => ()
      }
    }
    if channel.ledger_frame is Some(frame) && !channel.retired {
      match self.report_backed_channel_ledger(original, channel, frame) {
        Err(Domain(issue)) => return Err(Domain(issue))
        Err(Child(issue)) => return Err(OriginalChild(issue))
        Ok(_) => ()
      }
    }
    if !channel.retired {
      match self.retire_backed_live_channel_after_owner_ack(original, channel) {
        Err(issue) => return Err(Domain(issue))
        Ok(_) => ()
      }
    }
    if record.domain.read_use is Some(_) {
      // This worker entry excluded parent C read-context acquisition before
      // capture. It returns the original Common borrow after actual stop only.
      match self.close_backed_read_context(original, record.domain, record.child) {
        Err(issue) => return Err(Domain(issue))
        Ok(_) => ()
      }
    }
    record.channel = None
    record.transport = None
  }
  Ok(())
}

///|
fn[T, C] NativeHostBootstrap::original_process_region(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedProcessRegion[T, C],
) -> Result[Unit, NativeBackedProcessRegionIssue] {
  if !physical_equal(self.supplier.original, original) ||
    !physical_equal(record.owner, self) ||
    !physical_equal(record.domain.view.loan.region.owner, self) ||
    !physical_equal(record.domain.view.loan.child, record.child) {
    return Err(Domain(Bootstrap(ForeignOriginal)))
  }
  if record.retired {
    return Ok(())
  }
  if !(record.domain.process_region is Some(selected) &&
    physical_equal(selected, record)) {
    return Err(Domain(Bootstrap(ForeignOriginal)))
  }
  Ok(())
}

///|
/// Only the same never-started holder can abandon preparation. Partial capture
/// or close uncertainty stays in the registered original carrier.
pub fn[T, C] NativeHostBootstrap::abandon_prepared_process_region(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedProcessRegion[T, C],
) -> Result[Unit, NativeBackedProcessRegionIssue] {
  match self.original_process_region(original, record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if record.retired {
    return if record.stop is None {
      Ok(())
    } else {
      Err(Domain(Bootstrap(AlreadyConsumed)))
    }
  }
  if record.stop is Some(_) {
    return Err(Domain(Bootstrap(AlreadyConsumed)))
  }
  if !record.pin_closed {
    match record.holder.require_prepared() {
      Err(issue) => return Err(Process(issue))
      Ok(_) => ()
    }
    guard record.physical is Some(physical) else {
      return Err(Domain(Bootstrap(ReadersPending)))
    }
    let status = abandon_process_region_ffi(physical)
    if status != 0 {
      return Err(Domain(Bootstrap(Physical(status))))
    }
    if !record.holder.cleanup() {
      return Err(Domain(Bootstrap(ReadersPending)))
    }
    record.pin_closed = true
  }
  match self.retire_process_channel_metadata(original, record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  record.retired = true
  record.domain.process_region = None
  Ok(())
}

///|
/// The original process Owner confirms execution and IPC stop. Only then may
/// the same provider unmap its exclusively lent region and close its own FD.
/// This does not free each allocation, clear borrower PID or settle quota.
pub fn[T, C] NativeHostBootstrap::retire_stopped_process_region(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedProcessRegion[T, C],
  stop : @executor.NativeScopedExecutorStop,
) -> Result[Unit, NativeBackedProcessRegionIssue] {
  match self.original_process_region(original, record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if record.stop is Some(selected) && !physical_equal(selected, stop) {
    return Err(Domain(Bootstrap(ForeignOriginal)))
  }
  if record.retired {
    return if record.stop is Some(_) {
      Ok(())
    } else {
      Err(Domain(Bootstrap(AlreadyConsumed)))
    }
  }
  if record.pin_closed && record.stop is None {
    return Err(Domain(Bootstrap(AlreadyConsumed)))
  }
  if record.channel is Some(channel) && !channel.transport_stopped {
    return Err(Domain(Bootstrap(ReadersPending)))
  }
  if !record.pin_closed {
    match stop.require_current(record.holder) {
      Err(issue) => return Err(Process(issue))
      Ok(_) => ()
    }
    let process = match record.holder.child() {
      Err(issue) => return Err(Process(issue))
      Ok(value) => value
    }
    record.stop = Some(stop)
    guard record.physical is Some(physical) else {
      return Err(Domain(Bootstrap(ReadersPending)))
    }
    if !record.physical_retired {
      let status = retire_process_region_ffi(physical, process.pid())
      if status != 0 {
        return Err(Domain(Bootstrap(Physical(status))))
      }
      record.physical_retired = true
    }
    // Keep the same process pin through actual view and descriptor cleanup.
    // A failed/unknown pin close still blocks outer domain/view/loan retirement.
    if !stop.close() {
      return Err(Domain(Bootstrap(ReadersPending)))
    }
    record.pin_closed = true
  }
  match self.retire_process_channel_metadata(original, record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  record.retired = true
  record.domain.closed = true
  record.domain.view.closed = true
  record.domain.view.domain = None
  record.domain.process_region = None
  Ok(())
}
