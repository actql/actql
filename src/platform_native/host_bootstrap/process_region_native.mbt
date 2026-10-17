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
  mut physical : PhysicalProcessRegion?
  mut stop : @executor.NativeScopedExecutorStop?
  mut physical_retired : Bool
  mut retired : Bool
}

///|
pub(all) enum NativeBackedProcessRegionIssue {
  Domain(NativeBackedExecutionIssue)
  Process(@executor.NativeExecutorSlotIssue)
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
  let record : NativeBackedProcessRegion[T, C] = {
    owner: self,
    domain,
    child,
    holder,
    physical: None,
    stop: None,
    physical_retired: false,
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
  record.retired = true
  record.domain.closed = true
  record.domain.view.closed = true
  record.domain.process_region = None
  Ok(())
}
