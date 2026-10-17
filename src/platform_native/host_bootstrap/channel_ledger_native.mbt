///|
// Identity-only access for original cleanup and immutable reply custody. A
// frame is never looked up by limits, descriptor numbers or a matching CID.
fn[T, C] NativeHostBootstrap::original_channel_ledger(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChannel[T, C],
  frame : @resources.ImportedChildLedger,
) -> Result[Unit, NativeBackedOriginalReadIssue] {
  match self.original_live_channel(original, record) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  if record.ledger_frame is Some(selected) && physical_equal(selected, frame) {
    Ok(())
  } else {
    Err(Domain(Bootstrap(ForeignOriginal)))
  }
}

///|
/// Same original partial frame, including after a lost prepare postcheck.
/// This observes custody only and grants no start, limits or VM authority.
pub fn[T, C] NativeHostBootstrap::original_backed_channel_ledger_frame(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChannel[T, C],
) -> Result[@resources.ImportedChildLedger?, NativeBackedOriginalReadIssue] {
  match self.original_live_channel(original, record) {
    Err(issue) => Err(Domain(issue))
    Ok(_) => Ok(record.ledger_frame)
  }
}

///|
fn[T, C] NativeHostBootstrap::require_original_channel_ledger_current(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChannel[T, C],
  frame : @resources.ImportedChildLedger,
) -> Result[Unit, NativeBackedOriginalReadIssue] {
  match self.original_channel_ledger(original, record, frame) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match self.require_live_channel_open(original, record) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  guard record.physical is Some(physical) else {
    return Err(Domain(Bootstrap(Unavailable)))
  }
  let status = live_channel_status_ffi(physical)
  if status != 0 {
    Err(Domain(Bootstrap(Physical(status))))
  } else {
    Ok(())
  }
}

///|
/// Existing imported-child start/take, not a scalar root or physical grant.
/// The Native record retains the taken original before its current postcheck.
pub fn[T, C] NativeHostBootstrap::start_backed_channel_ledger(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChannel[T, C],
  frame : @resources.ImportedChildLedger,
) -> Result[Unit, NativeBackedOriginalReadIssue] {
  match self.require_original_channel_ledger_current(original, record, frame) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match @resources.start_imported_child_ledger(frame) {
    Err(issue) => return Err(Child(issue))
    Ok(_) => ()
  }
  let ledger = match @resources.take_imported_original_child_ledger(frame) {
    Err(issue) => return Err(Child(issue))
    Ok(ledger) => ledger
  }
  record.original_ledger = Some(ledger)
  self.require_backed_channel_ledger_current(original, record, frame)
}

///|
/// Native physical/current checks and the same Common original resource fence.
/// This is not Account, launch, Source, Model, VM or publication permission.
pub fn[T, C] NativeHostBootstrap::require_backed_channel_ledger_current(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChannel[T, C],
  frame : @resources.ImportedChildLedger,
) -> Result[Unit, NativeBackedOriginalReadIssue] {
  match self.require_original_channel_ledger_current(original, record, frame) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard record.live is Some(live) else {
    return Err(Domain(Bootstrap(Unavailable)))
  }
  match self.backed_live_child_state(original, live, record) {
    Err(issue) => return Err(Domain(issue))
    Ok(@resources.LiveClosing) =>
      return Err(Child(@resources.Resource(@resources.ClosedReservation)))
    Ok(@resources.LiveOpen) => ()
  }
  guard record.original_ledger is Some(ledger) else {
    return Err(Child(@resources.Unavailable))
  }
  @resources.check_original_resources_mutable(ledger).map_err(issue => {
    Child(@resources.Resource(issue))
  })
}

///|
/// Immutable allowance DATA, not another resource issuer or numerical profile.
pub fn[T, C] NativeHostBootstrap::backed_channel_ledger_limits(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChannel[T, C],
  frame : @resources.ImportedChildLedger,
) -> Result[@resources.LedgerLimits, NativeBackedOriginalReadIssue] {
  match self.require_backed_channel_ledger_current(original, record, frame) {
    Err(issue) => Err(issue)
    Ok(_) => Ok(@resources.ledger_limits(record.original_ledger.unwrap()))
  }
}

///|
/// One selected bootstrap reservation inside the inherited original allowance.
/// Scalar amounts cannot issue the channel, frame, backing or parent Ledger.
/// The same original carrier retains the reservation before any postcheck.
pub fn[T, C] NativeHostBootstrap::reserve_backed_channel_bootstrap(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChannel[T, C],
  frame : @resources.ImportedChildLedger,
  retained : Int64,
  execution : Int64,
) -> Result[Unit, NativeBackedOriginalReadIssue] {
  match self.require_backed_channel_ledger_current(original, record, frame) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if retained < 0L || execution <= 0L {
    return Err(Child(@resources.Resource(@resources.InvalidCharge)))
  }
  if record.envelope_attempted {
    return Err(Child(@resources.AlreadyConsumed))
  }
  record.envelope_attempted = true
  let envelope = match
    @resources.reserve_capacity(
      record.original_ledger.unwrap(),
      retained,
      execution,
    ) {
    Err(issue) => return Err(Child(@resources.Resource(issue)))
    Ok(value) => value
  }
  record.envelope = Some(envelope)
  self.require_backed_channel_ledger_current(original, record, frame)
}

///|
/// Snapshot is produced by the same Common Ledger; no caller-supplied counters.
/// Cleanup retains its original pending-report/Unknown and no-resend rules.
pub fn[T, C] NativeHostBootstrap::report_backed_channel_ledger(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChannel[T, C],
  frame : @resources.ImportedChildLedger,
) -> Result[Unit, NativeBackedOriginalReadIssue] {
  match self.original_channel_ledger(original, record, frame) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  @resources.report_imported_child_ledger(frame).map_err(issue => Child(issue))
}

///|
/// Logical restriction only. It neither retires an allocation nor stops a
/// process or acknowledges FD, Store, VM, Mach/Rust lifetime or Run cleanup.
pub fn[T, C] NativeHostBootstrap::stop_backed_channel_ledger(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChannel[T, C],
  frame : @resources.ImportedChildLedger,
) -> Result[Unit, NativeBackedOriginalReadIssue] {
  match self.original_channel_ledger(original, record, frame) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  @resources.stop_imported_child_ledger(frame).map_err(issue => Child(issue))
}

///|
/// Trusted existing physical Owner only AFTER its separate original scoped
/// stop/alias/descriptor ACK. Engine close or PID/EOF observations alone cannot
/// call this boundary. Final channel/loan/parent retirement remains separate.
pub fn[T, C] NativeHostBootstrap::retire_backed_channel_bootstrap_after_owner_ack(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChannel[T, C],
  frame : @resources.ImportedChildLedger,
) -> Result[Unit, NativeBackedOriginalReadIssue] {
  match self.original_channel_ledger(original, record, frame) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if record.envelope_retired {
    return Err(Child(@resources.AlreadyConsumed))
  }
  match @resources.stop_imported_child_ledger(frame) {
    Err(issue) => return Err(Child(issue))
    Ok(_) => ()
  }
  if record.envelope is Some(envelope) {
    match
      @resources.settle_capacity(record.original_ledger.unwrap(), envelope) {
      Err(issue) => return Err(Child(@resources.Resource(issue)))
      Ok(_) => record.envelope = None
    }
  }
  record.envelope_retired = true
  Ok(())
}

///|
/// Coverage only for the SAME selected physical domain. This cannot fund a
/// separate process, FD, Python heap, copy, Store or VM/Account authority.
pub fn[T, C] NativeHostBootstrap::require_backed_channel_bootstrap_current(
  self : NativeHostBootstrap[T],
  original : T,
  record : NativeBackedLiveChannel[T, C],
  frame : @resources.ImportedChildLedger,
) -> Result[Unit, NativeBackedOriginalReadIssue] {
  match self.require_backed_channel_ledger_current(original, record, frame) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard record.original_ledger is Some(ledger) &&
    record.envelope is Some(envelope) else {
    return Err(Child(@resources.Unavailable))
  }
  let (payload, _) = match
    self.backed_domain_capacity(original, record.domain, record.child) {
    Err(issue) => return Err(Domain(issue))
    Ok(value) => value
  }
  if @resources.capacity_reservation_covers(ledger, envelope, 0L, payload) {
    Ok(())
  } else {
    Err(Child(@resources.Unavailable))
  }
}
