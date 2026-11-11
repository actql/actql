///|
/// Connect the SAME already backed VM entry prefix to the existing region,
/// child ticket and Request admission. No new Root, callback or Ledger is
/// supplied here. The same installing owner retains all partial originals.
pub fn[P, C] issue_platform_vm_preparation_region(
  working : PlatformVMWorkingCapacity,
  provider : P,
) -> Result[BackedExecutionRegion[P, C], BackedExecutionIssue] {
  match platform_vm_working_original(working) {
    Err(_) => return Err(ForeignOriginal)
    Ok(_) => ()
  }
  if working.region_issued {
    return Err(DuplicateChild)
  }
  if working.allocation.bytes <= 0L {
    return Err(InvalidExtent)
  }
  // Latch before the original current callback. A failed/reentrant start
  // retains the same working claim; it never retries as a different region.
  working.region_issued = true
  let borrow = match borrow_platform_vm_working_capacity(working) {
    Err(_) => return Err(Resource(ChildFundingUnavailable))
    Ok(value) => value
  }
  Ok({
    capacity: Some(working.vm.capacity),
    allocation: Some(working.allocation),
    provider: Some(provider),
    owner_borrow: Some(borrow),
    children: [],
    closing: false,
    working: Some((working, working.retained, working.execution)),
  })
}

///|
// Fixed Resource-current cut only. The original child ledger and its actual
// canonical reservation/resize supply these simultaneous demands. Policy
// ceilings, reports and observed Memory length cannot enter this path.
fn grow_imported_platform_working_current(
  ledger : Ledger,
  retained : Int64,
  execution : Int64,
) -> Result[Unit, LedgerIssue] {
  if ledger.imported_child is Some(origin) &&
    origin.current_window is Some(window) {
    let backed_bytes = window.val
    guard origin.ledger is Some(original) && physical_equal(original, ledger) else {
      return Err(ForeignOwner)
    }
    if retained > backed_bytes || execution > backed_bytes - retained {
      match
        acquire_imported_child_window_current(
          ledger, origin, window, retained, execution,
        ) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
    }
  }
  guard ledger.imported_child is Some(origin) &&
    origin.working is Some((working, prefix_retained, prefix_execution)) else {
    return Ok(())
  }
  guard origin.ledger is Some(original) && physical_equal(original, ledger) else {
    return Err(ForeignOwner)
  }
  // Disposal may proceed on a stopping child, but cannot admit more backing.
  if retained < 0L ||
    execution < 0L ||
    retained > working.vm.capacity.capacity - prefix_retained ||
    execution > working.vm.capacity.capacity - prefix_execution {
    return Err(RetentionLimit)
  }
  // An earlier admitted peak still covers disposal while logical stop is
  // pending. No growth/current proof or physical acknowledgement is invented.
  if prefix_retained + retained <= working.retained &&
    prefix_execution + execution <= working.execution {
    return Ok(())
  }
  grow_platform_vm_working_capacity_current(
    working,
    prefix_retained + retained,
    prefix_execution + execution,
  ).map_err(issue => {
    match issue {
      Resource(issue) => issue
      _ => ChildFundingUnavailable
    }
  })
}

///|
// Only this nominal original's installed physical owner may acquire backing.
// Its successful callback is not a grant: the same current/window/policy cut
// must still cover the exact canonical simultaneous demand before mutation.
fn acquire_imported_child_window_current(
  ledger : Ledger,
  origin : ImportedChildLedgerOrigin,
  window : Ref[Int64],
  retained : Int64,
  execution : Int64,
) -> Result[Unit, LedgerIssue] {
  if origin.unavailable || origin.acquiring_window {
    return Err(ChildFundingUnavailable)
  }
  if origin.stopping {
    return Err(ClosedReservation)
  }
  if retained < 0L || execution < 0L {
    return Err(InvalidCharge)
  }
  if retained > ledger.limits.retained_bytes {
    return Err(RetentionLimit)
  }
  if execution > ledger.limits.execution_bytes {
    return Err(ExecutionLimit)
  }
  guard origin.acquire_window is Some(acquire) else {
    return Err(RetentionLimit)
  }
  let before = ledger.usage
  origin.acquiring_window = true
  let result = match acquire(retained, execution) {
    Err(issue) => Err(issue)
    Ok(_) =>
      match refresh_imported_child_current(origin) {
        Err(issue) => Err(issue)
        Ok(_) =>
          if origin.stopping {
            Err(ClosedReservation)
          } else if !(ledger.imported_child is Some(original_origin) &&
            physical_equal(original_origin, origin) &&
            origin.ledger is Some(original_ledger) &&
            physical_equal(original_ledger, ledger) &&
            origin.current_window is Some(original_window) &&
            physical_equal(original_window, window)) ||
            ledger.usage != before {
            Err(ForeignOwner)
          } else if retained > ledger.limits.retained_bytes {
            Err(RetentionLimit)
          } else if execution > ledger.limits.execution_bytes {
            Err(ExecutionLimit)
          } else if retained > window.val || execution > window.val - retained {
            Err(RetentionLimit)
          } else {
            Ok(())
          }
      }
  }
  origin.acquiring_window = false
  result
}

///|
// A cumulative report preserves the existing full child usage. Its bytes
// must already be backed before construction; reporting cannot grow a claim.
fn[P, C] platform_vm_backed_usage_fits(
  region : BackedExecutionRegion[P, C],
  usage : LedgerUsage,
) -> Bool {
  guard region.working is Some((working, retained, execution)) else {
    return true
  }
  usage.held_bytes <= working.retained - retained &&
  usage.reserved_retention_bytes <=
  working.retained - retained - usage.held_bytes &&
  usage.peak_retention_bytes <= working.retained - retained &&
  usage.reserved_execution_bytes <= working.execution - execution
}
