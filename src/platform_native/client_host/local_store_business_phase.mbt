///|
// Retain every attempted transition before returning to the borrowed parent.
// An interrupted original callback must return before cleanup can own it.
fn NativeLocalStoreOperationReceiver::interrupt_business(
  self : NativeLocalStoreOperationReceiver,
  original : NativeLocalJournalOriginalResources,
  issue : NativeLocalStoreOperationIssue,
) -> NativeLocalStoreOperationIssue {
  self.refuse(issue) |> ignore
  original.interrupted = true
  if self.capture.read_operation_issue is None {
    self.capture.read_operation_issue = Some(OriginalResourceScopePending)
  }
  self.primary.unwrap_or(issue)
}

///|
/// Suspend only this original borrowed Read before entering its already-admitted
/// business installation. No Ledger, capacity or Account permission is issued.
pub fn NativeLocalStoreOperation::enter_business_from_original_read(
  self : NativeLocalStoreOperation,
) -> Result[Unit, NativeLocalStoreOperationIssue] {
  let receiver = self.receiver
  guard receiver.domain is StoreBusinessDomain(execution) else {
    return Err(StoreOperationUnavailable)
  }
  guard self.bridge is Some(bridge) &&
    receiver.ready &&
    !receiver.closed &&
    !receiver.closing &&
    !receiver.borrowed_read &&
    receiver.capture.read_callback_active &&
    receiver.primary is None else {
    return Err(StoreOperationUnavailable)
  }
  match bridge.pending_scope() {
    Ok(false) => ()
    Ok(true) => return Err(StoreOperationUnavailable)
    Err(issue) => return Err(StoreOperationSqlite(issue))
  }
  let (_, original) = match receiver.originals(receiver.library, false) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if original.store_operation is Some(_) ||
    !(original.active_phase is Some(@arena.HostRead)) ||
    !(original.host.observe_domain_retained_execution_scope(execution)
    is Ok(@bootstrap.BackedReadUnentered)) {
    return Err(StoreOperationUnavailable)
  }
  match receiver.capture.check_current_in_original_read() {
    Err(issue) => return Err(StoreOperationCapture(issue))
    Ok(_) => ()
  }
  // The same receiver now owns return to its borrowed parent even when a later
  // leave/enter refuses. Neither an application exception nor a Bool drops it.
  receiver.return_acknowledged = false
  receiver.borrowed_read = true
  match original.host.leave_local_host_phase(original.pair) {
    Err(issue) =>
      return Err(
        receiver.interrupt_business(original, StoreOperationResources(issue)),
      )
    Ok(_) => original.active_phase = None
  }
  receiver.business_pending = true
  match original.host.enter_domain_retained_execution(execution) {
    Err(issue) =>
      Err(receiver.interrupt_business(original, StoreOperationExecution(issue)))
    Ok(_) => {
      receiver.business_pending = false
      Ok(())
    }
  }
}

///|
/// Return this same business scope to its original parent Read after child
/// operations settle. Failed/current/Unknown returns retain cleanup-only duty;
/// they do not enter a replacement Read or resume another business installation.
pub fn NativeLocalStoreOperation::return_business_to_original_read(
  self : NativeLocalStoreOperation,
) -> Result[Unit, NativeLocalStoreOperationIssue] {
  let receiver = self.receiver
  guard receiver.domain is StoreBusinessDomain(execution) else {
    return Err(StoreOperationUnavailable)
  }
  guard self.bridge is Some(bridge) &&
    receiver.borrowed_read &&
    receiver.capture.read_callback_active &&
    !receiver.closed &&
    !receiver.closing else {
    return Err(StoreOperationUnavailable)
  }
  let (_, original) = match receiver.originals(receiver.library, true) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match bridge.pending_scope() {
    Ok(false) => ()
    Ok(true) =>
      return Err(
        receiver.interrupt_business(original, StoreOperationUnavailable),
      )
    Err(issue) =>
      return Err(
        receiver.interrupt_business(original, StoreOperationSqlite(issue)),
      )
  }
  if original.store_operation is Some(_) ||
    original.active_phase is Some(_) ||
    receiver.primary is Some(_) {
    return Err(receiver.interrupt_business(original, StoreOperationUnavailable))
  }
  // This receiver attempted the original entry. An observation error cannot
  // infer inactivity; only the existing same-record leave can acknowledge it.
  let left = match
    original.host.observe_domain_retained_execution_scope(execution) {
    Ok(@bootstrap.BackedReadUnentered) => Ok(())
    Ok(@bootstrap.BackedReadEntered) | Err(_) =>
      original.host.leave_domain_retained_execution(execution)
  }
  match left {
    Err(issue) =>
      return Err(
        receiver.interrupt_business(original, StoreOperationExecution(issue)),
      )
    Ok(_) => receiver.business_pending = false
  }
  guard receiver.capture.opening is JournalAcquired(_) else {
    return Err(receiver.interrupt_business(original, StoreOperationUnavailable))
  }
  match receiver.capture.check_current_between_original_phases() {
    Err(issue) =>
      return Err(
        receiver.interrupt_business(original, StoreOperationCapture(issue)),
      )
    Ok(_) => ()
  }
  match original.host.enter_local_host_phase(original.pair, @arena.HostRead) {
    Err(issue) =>
      Err(receiver.interrupt_business(original, StoreOperationResources(issue)))
    Ok(_) => {
      original.active_phase = Some(@arena.HostRead)
      receiver.borrowed_read = false
      Ok(())
    }
  }
}
