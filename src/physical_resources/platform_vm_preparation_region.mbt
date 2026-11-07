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
      return Err(RetentionLimit)
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
