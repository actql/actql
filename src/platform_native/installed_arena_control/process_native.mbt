///|
/// Physical lifetime projection in the same installed Host/domain. The
/// original process Owner retains the slot, endpoints, child and stop; the
/// backing Owner retains its region. This wrapper issues no funding or launch
/// permission and cannot supply the missing ordinary worker profile.
struct InstalledArenaProcess {
  domain : InstalledArenaDomain
  mut slot : @executor.NativeExecutorSlot?
  mut holder : @executor.NativeScopedExecutorHolder?
  mut transport : @executor.NativeScopedDuplexBorrow?
  mut channel : @bootstrap.NativeBackedLiveChannel[
    InstalledArenaHost,
    InstalledArenaDomain,
  ]?
  mut frame : @resources.ImportedChildLedger?
  mut region : @bootstrap.NativeBackedProcessRegion[
    InstalledArenaHost,
    InstalledArenaDomain,
  ]?
  mut envelope_retired : Bool
  mut channel_retired : Bool
  mut holder_closed : Bool
  mut stop : @executor.NativeScopedExecutorStop?
  mut slot_close_unknown : Bool
  mut closing : Bool
  mut closed : Bool
}

///|
pub(all) enum InstalledArenaProcessAcquisition {
  PreparedProcess(InstalledArenaProcess)
  PendingProcess(
    InstalledArenaProcess,
    @bootstrap.NativeBackedProcessRegionIssue
  )
}

///|
fn process_frame_issue(
  issue : @bootstrap.NativeBackedOriginalReadIssue,
) -> @bootstrap.NativeBackedProcessRegionIssue {
  match issue {
    @bootstrap.Domain(issue) => @bootstrap.Domain(issue)
    @bootstrap.Child(issue) => @bootstrap.OriginalChild(issue)
  }
}

///|
/// Trusted physical assembly only, after its separate original process/FD/
/// control envelope is funded. The same domain's Common capacity covers only
/// that domain, not these independent costs. Registration precedes open/pipe/
/// capture operations; every partial original remains in the same carrier.
pub fn InstalledArenaHost::prepare_process(
  self : InstalledArenaHost,
  domain : InstalledArenaDomain,
  slot_path : String,
  descriptor : Int,
  nonce : Int64,
  retained : Int64,
  execution : Int64,
) -> Result[
  InstalledArenaProcessAcquisition,
  @bootstrap.NativeBackedProcessRegionIssue,
] {
  match self.require_domain_current(domain) {
    Err(issue) => return Err(@bootstrap.Domain(issue))
    Ok(_) => ()
  }
  if domain.live_channel is Some(_) ||
    domain.sqlite_library is Some(_) ||
    domain.original_read is Some(_) ||
    domain.retained_execution is Some(_) ||
    retained < 0L ||
    execution <= 0L ||
    nonce <= 0L {
    return Err(@bootstrap.Domain(@bootstrap.Bootstrap(@bootstrap.Unavailable)))
  }
  let process : InstalledArenaProcess = {
    domain,
    slot: None,
    holder: None,
    transport: None,
    channel: None,
    frame: None,
    region: None,
    envelope_retired: false,
    channel_retired: false,
    holder_closed: false,
    stop: None,
    slot_close_unknown: false,
    closing: false,
    closed: false,
  }
  domain.process = Some(process)
  match
    process.prepare_original(slot_path, descriptor, nonce, retained, execution) {
    Err(issue) => Ok(PendingProcess(process, issue))
    Ok(_) => Ok(PreparedProcess(process))
  }
}

///|
fn InstalledArenaProcess::prepare_original(
  self : InstalledArenaProcess,
  slot_path : String,
  descriptor : Int,
  nonce : Int64,
  retained : Int64,
  execution : Int64,
) -> Result[Unit, @bootstrap.NativeBackedProcessRegionIssue] {
  let host = self.domain.host
  let domain = self.domain
  let backing = domain.backing
  let native_domain = domain.domain.unwrap()
  let slot = match @executor.open_native_executor_slot(slot_path) {
    Err(issue) => return Err(@bootstrap.Process(issue))
    Ok(slot) => slot
  }
  self.slot = Some(slot)
  match slot.try_acquire() {
    Err(issue) => return Err(@bootstrap.Process(issue))
    Ok(false) => return Err(@bootstrap.Process(@executor.Busy))
    Ok(true) => ()
  }
  let holder = match slot.prepare_scoped_holder() {
    @executor.Ready(holder) => holder
    @executor.Refused(holder, issue) => {
      self.holder = Some(holder)
      return Err(@bootstrap.Process(issue))
    }
  }
  self.holder = Some(holder)
  let transport = match holder.prepare_duplex() {
    Err(issue) => return Err(@bootstrap.Process(issue))
    Ok(transport) => transport
  }
  let borrowed = match transport.borrow_transport(holder) {
    Err(issue) => return Err(@bootstrap.Process(issue))
    Ok(borrowed) => borrowed
  }
  self.transport = Some(borrowed)
  let (writer, reader) = match borrowed.parent_descriptors(holder) {
    Err(issue) => return Err(@bootstrap.Process(issue))
    Ok(value) => value
  }
  let channel = match
    backing.prepare_backed_live_channel_before_spawn(
      host, native_domain, domain, reader, writer, nonce,
    ) {
    Err(issue) => return Err(@bootstrap.Domain(issue))
    Ok(@bootstrap.PendingLiveChannel(channel, issue)) => {
      domain.live_channel = Some(channel)
      self.channel = Some(channel)
      return Err(@bootstrap.Domain(issue))
    }
    Ok(@bootstrap.PreparedLiveChannel(channel)) => channel
  }
  self.channel = Some(channel)
  domain.live_channel = Some(channel)
  let frame = match
    backing.prepare_backed_original_channel_ledger(host, channel) {
    Err(issue) => {
      self.frame = backing
        .original_backed_channel_ledger_frame(host, channel)
        .unwrap_or(None)
      return Err(process_frame_issue(issue))
    }
    Ok(frame) => frame
  }
  self.frame = Some(frame)
  match backing.start_backed_channel_ledger(host, channel, frame) {
    Err(issue) => return Err(process_frame_issue(issue))
    Ok(_) => ()
  }
  match
    backing.reserve_backed_channel_bootstrap(
      host, channel, frame, retained, execution,
    ) {
    Err(issue) => return Err(process_frame_issue(issue))
    Ok(_) => ()
  }
  match backing.require_backed_channel_bootstrap_current(host, channel, frame) {
    Err(issue) => return Err(process_frame_issue(issue))
    Ok(_) => ()
  }
  match
    backing.bind_prepared_process_channel_region(
      host, channel, holder, borrowed, descriptor,
    ) {
    Err(issue) => Err(issue)
    Ok(@bootstrap.ProcessRegionPending(region, issue)) => {
      self.region = Some(region)
      Err(issue)
    }
    Ok(@bootstrap.ProcessRegionReady(region)) => {
      self.region = Some(region)
      Ok(())
    }
  }
}

///|
fn InstalledArenaHost::original_process(
  self : InstalledArenaHost,
  domain : InstalledArenaDomain,
  process : InstalledArenaProcess,
) -> Result[Unit, @bootstrap.NativeBackedProcessRegionIssue] {
  if !physical_equal(process.domain, domain) ||
    !(domain.process is Some(original) && physical_equal(original, process)) {
    return Err(
      @bootstrap.Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal)),
    )
  }
  self
  .original_read_domain(domain)
  .map(_ => ())
  .map_err(issue => @bootstrap.Domain(issue))
}

///|
pub fn InstalledArenaHost::require_process_current(
  self : InstalledArenaHost,
  domain : InstalledArenaDomain,
  process : InstalledArenaProcess,
) -> Result[Unit, @bootstrap.NativeBackedProcessRegionIssue] {
  match self.original_process(domain, process) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if self.closing || process.closing || process.closed || process.region is None {
    return Err(@bootstrap.Domain(@bootstrap.Bootstrap(@bootstrap.Closing)))
  }
  guard process.channel is Some(channel) && process.frame is Some(frame) else {
    return Err(@bootstrap.Domain(@bootstrap.Bootstrap(@bootstrap.Unavailable)))
  }
  domain.backing
  .require_backed_channel_bootstrap_current(self, channel, frame)
  .map_err(issue => process_frame_issue(issue))
}

///|
/// Borrowed endpoint facts, never a descriptor close/child/launch/Run grant.
pub fn InstalledArenaHost::process_descriptors(
  self : InstalledArenaHost,
  domain : InstalledArenaDomain,
  process : InstalledArenaProcess,
) -> Result[(Int, Int), @bootstrap.NativeBackedProcessRegionIssue] {
  match self.require_process_current(domain, process) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard process.holder is Some(holder) && process.transport is Some(transport) else {
    return Err(@bootstrap.Domain(@bootstrap.Bootstrap(@bootstrap.Unavailable)))
  }
  transport
  .parent_descriptors(holder)
  .map_err(issue => @bootstrap.Process(issue))
}

///|
/// Borrowed original backing, before the same process Owner prepares spawn.
/// The recipient must retain its own duplicate; this is not a close or grant.
pub fn InstalledArenaHost::process_backing_descriptor(
  self : InstalledArenaHost,
  domain : InstalledArenaDomain,
  process : InstalledArenaProcess,
) -> Result[Int, @bootstrap.NativeBackedProcessRegionIssue] {
  match self.require_process_current(domain, process) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard process.region is Some(region) else {
    return Err(@bootstrap.Domain(@bootstrap.Bootstrap(@bootstrap.Unavailable)))
  }
  domain.backing.prepared_process_region_descriptor(self, region)
}

///|
/// Logical restriction precedes return of the exact original endpoint borrow.
/// An imported-child Unknown stays distinct from physical stop/cleanup.
pub fn InstalledArenaHost::restrict_process_transport(
  self : InstalledArenaHost,
  domain : InstalledArenaDomain,
  process : InstalledArenaProcess,
) -> Result[Unit, @bootstrap.NativeBackedProcessRegionIssue] {
  match self.original_process(domain, process) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard process.channel is Some(channel) else {
    return Err(@bootstrap.Domain(@bootstrap.Bootstrap(@bootstrap.Unavailable)))
  }
  domain.backing
  .stop_backed_live_channel_transport_use(self, channel)
  .map_err(issue => process_frame_issue(issue))
}

///|
/// Trusted serialized physical caller only, after actual in-flight I/O ends.
/// The original channel Owner checks its restriction; no Boolean replaces it.
pub fn InstalledArenaHost::return_process_transport(
  self : InstalledArenaHost,
  domain : InstalledArenaDomain,
  process : InstalledArenaProcess,
) -> Result[Unit, @bootstrap.NativeBackedProcessRegionIssue] {
  match self.original_process(domain, process) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if process.region is Some(region) {
    return domain.backing.return_process_channel_transport(self, region)
  }
  // No process was admitted by an incomplete preparation. Its retained
  // endpoint view can be withdrawn for the same never-started Holder only.
  if process.closed {
    return Err(
      @bootstrap.Domain(@bootstrap.Bootstrap(@bootstrap.AlreadyConsumed)),
    )
  }
  guard process.holder is Some(holder) && process.transport is Some(transport) else {
    return Err(@bootstrap.Domain(@bootstrap.Bootstrap(@bootstrap.Unavailable)))
  }
  match holder.require_prepared() {
    Err(issue) => return Err(@bootstrap.Process(issue))
    Ok(_) => ()
  }
  if process.channel is Some(channel) {
    match domain.backing.stop_backed_live_channel_transport_use(self, channel) {
      Err(issue) => return Err(process_frame_issue(issue))
      Ok(_) => ()
    }
  }
  transport.return_transport(holder).map_err(issue => @bootstrap.Process(issue))
}

///|
/// Never-started preparation only. Successful physical phases remain with the
/// same Owner; a failed/unknown descriptor close is not repeated or ignored.
pub fn InstalledArenaHost::close_prepared_process(
  self : InstalledArenaHost,
  domain : InstalledArenaDomain,
  process : InstalledArenaProcess,
) -> Result[Unit, @bootstrap.NativeBackedProcessRegionIssue] {
  match self.original_process(domain, process) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if process.closed {
    return Ok(())
  }
  process.closing = true
  if process.stop is Some(_) {
    return Err(
      @bootstrap.Domain(@bootstrap.Bootstrap(@bootstrap.AlreadyConsumed)),
    )
  }
  if process.slot_close_unknown {
    return Err(@bootstrap.Process(@executor.LockFailed))
  }
  if process.region is Some(region) {
    match domain.backing.abandon_prepared_process_region(self, region) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    process.envelope_retired = true
    process.channel_retired = true
    domain.live_channel = None
  } else {
    if !process.holder_closed {
      if process.transport is Some(_) {
        match self.return_process_transport(domain, process) {
          Err(issue) => return Err(issue)
          Ok(_) => ()
        }
      }
      if process.holder is Some(holder) && !holder.cleanup() {
        return Err(
          @bootstrap.Domain(@bootstrap.Bootstrap(@bootstrap.ReadersPending)),
        )
      }
      process.holder_closed = true
    }
    if process.channel is Some(channel) && !process.channel_retired {
      if process.frame is Some(frame) {
        if !process.envelope_retired {
          match
            domain.backing.retire_backed_channel_bootstrap_after_owner_ack(
              self, channel, frame,
            ) {
            Err(issue) => return Err(process_frame_issue(issue))
            Ok(_) => process.envelope_retired = true
          }
        }
        match
          domain.backing.report_backed_channel_ledger(self, channel, frame) {
          Err(issue) => return Err(process_frame_issue(issue))
          Ok(_) => ()
        }
      }
      match self.retire_live_channel_after_owner_ack(domain, channel) {
        Err(issue) => return Err(@bootstrap.Domain(issue))
        Ok(_) => process.channel_retired = true
      }
    }
  }
  if process.slot is Some(slot) && slot.is_open() {
    process.slot_close_unknown = true
    if !slot.close() {
      return Err(@bootstrap.Process(@executor.LockFailed))
    }
    process.slot_close_unknown = false
  }
  process.closed = true
  Ok(())
}

///|
/// Observe only the same Holder's typed stop. A pending observation, an error,
/// EOF or an absent PID never creates a stop or releases the region.
pub fn InstalledArenaHost::poll_process_stop(
  self : InstalledArenaHost,
  domain : InstalledArenaDomain,
  process : InstalledArenaProcess,
) -> Result[Bool, @bootstrap.NativeBackedProcessRegionIssue] {
  match self.original_process(domain, process) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if process.closed || process.region is None {
    return Err(
      @bootstrap.Domain(@bootstrap.Bootstrap(@bootstrap.AlreadyConsumed)),
    )
  }
  guard process.holder is Some(holder) else {
    return Err(@bootstrap.Domain(@bootstrap.Bootstrap(@bootstrap.Unavailable)))
  }
  match holder.poll_stop() {
    Err(issue) => Err(@bootstrap.Process(issue))
    Ok(None) => Ok(false)
    Ok(Some(stop)) => {
      process.stop = Some(stop)
      Ok(true)
    }
  }
}

///|
/// Separate original process/IPC stop and real region/FD retirement. This is
/// not final quota reconciliation, a never-sent proof or a Run/Store outcome.
pub fn InstalledArenaHost::retire_stopped_process(
  self : InstalledArenaHost,
  domain : InstalledArenaDomain,
  process : InstalledArenaProcess,
) -> Result[Unit, @bootstrap.NativeBackedProcessRegionIssue] {
  match self.original_process(domain, process) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if process.closed {
    return if process.stop is Some(_) {
      Ok(())
    } else {
      Err(@bootstrap.Domain(@bootstrap.Bootstrap(@bootstrap.AlreadyConsumed)))
    }
  }
  process.closing = true
  guard process.region is Some(region) && process.stop is Some(stop) else {
    return Err(
      @bootstrap.Domain(@bootstrap.Bootstrap(@bootstrap.ReadersPending)),
    )
  }
  match domain.backing.retire_stopped_process_region(self, region, stop) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  process.envelope_retired = true
  process.channel_retired = true
  process.holder_closed = true
  domain.live_channel = None
  process.closed = true
  Ok(())
}
