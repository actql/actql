///|
/// A demand-sized view of one allocation on the SAME original VM capacity.
/// This is not a Request admission, a new Ledger or a physical Store owner.
struct PlatformVMWorkingCapacity {
  mut original : PlatformVMWorkingCapacity?
  vm : PlatformVMCapacity
  allocation : SharedAllocation
  mut retained : Int64
  mut execution : Int64
  mut closing : Bool
  mut region_issued : Bool
}

///|
fn platform_vm_working_original(
  owner : PlatformVMWorkingCapacity,
) -> Result[Unit, ImportedChildLedgerIssue] {
  guard owner.original is Some(original) &&
    physical_equal(owner, original) &&
    physical_equal(owner.vm.capacity, owner.allocation.owner) else {
    return Err(ForeignOriginal)
  }
  if owner.allocation.released {
    return Err(Unavailable)
  }
  Ok(())
}

///|
/// Claim complete retained+scratch coexistence before constructing it. Policy
/// maxima are not preallocated. Controller/entry construction needs its own
/// previously backed prefix; this allocator does not supply its own caller.
pub fn reserve_platform_vm_working_capacity(
  vm : PlatformVMCapacity,
  retained : Int64,
  execution : Int64,
) -> Result[PlatformVMWorkingCapacity, ImportedChildLedgerIssue] {
  match require_platform_vm_capacity(vm, vm.ledger, vm.capacity) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if retained < 0L ||
    execution < 0L ||
    retained > vm.capacity.capacity ||
    execution > vm.capacity.capacity - retained {
    return Err(Resource(InvalidCharge))
  }
  let allocation = match
    allocate_shared_capacity(vm.capacity, retained + execution) {
    Err(issue) => return Err(Resource(issue))
    Ok(value) => value
  }
  let owner : PlatformVMWorkingCapacity = {
    original: None,
    vm,
    allocation,
    retained,
    execution,
    closing: false,
    region_issued: false,
  }
  owner.original = Some(owner)
  Ok(owner)
}

///|
/// Grow this SAME claim before the next constructor. Earlier peaks stay held
/// until original borrower retirement; lowering a later quote returns no bytes.
/// No callback intervenes between the final state check and atomic byte update.
pub fn grow_platform_vm_working_capacity(
  owner : PlatformVMWorkingCapacity,
  retained : Int64,
  execution : Int64,
) -> Result[Unit, ImportedChildLedgerIssue] {
  match platform_vm_working_original(owner) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match
    require_platform_vm_capacity(owner.vm, owner.vm.ledger, owner.vm.capacity) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match platform_vm_working_original(owner) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  grow_platform_vm_working_capacity_current(owner, retained, execution)
}

///|
// Only this Resource owner's fixed original-current cut calls this helper.
// It observes no external callback and exposes no reusable current proof.
fn grow_platform_vm_working_capacity_current(
  owner : PlatformVMWorkingCapacity,
  retained : Int64,
  execution : Int64,
) -> Result[Unit, ImportedChildLedgerIssue] {
  match platform_vm_working_original(owner) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if owner.vm.closing || owner.vm.failure is Some(_) {
    return Err(Unavailable)
  }
  match check_original_resources_mutable_current(owner.vm.ledger) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  let capacity = owner.vm.capacity
  let allocation = owner.allocation
  if owner.closing ||
    capacity.closing ||
    capacity.growth is Some(_) ||
    allocation.retiring ||
    !reservation_open(capacity.reservation) {
    return Err(Unavailable)
  }
  if retained < 0L || execution < 0L {
    return Err(Resource(InvalidCharge))
  }
  let next_retained = Int64::max(owner.retained, retained)
  let next_execution = Int64::max(owner.execution, execution)
  if next_retained > capacity.capacity ||
    next_execution > capacity.capacity - next_retained {
    return Err(Resource(RetentionLimit))
  }
  let next = next_retained + next_execution
  let additional = next - allocation.bytes
  if additional > capacity.capacity - capacity.allocated {
    return Err(Resource(RetentionLimit))
  }
  capacity.allocated += additional
  allocation.bytes = next
  owner.retained = next_retained
  owner.execution = next_execution
  Ok(())
}

///|
/// Retain the existing original borrower before entering a constructor or
/// exporting its result. Returning this same token remains a separate duty.
pub fn borrow_platform_vm_working_capacity(
  owner : PlatformVMWorkingCapacity,
) -> Result[SharedBorrow, ImportedChildLedgerIssue] {
  match platform_vm_working_original(owner) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match
    require_platform_vm_capacity(owner.vm, owner.vm.ledger, owner.vm.capacity) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match platform_vm_working_original(owner) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if owner.closing {
    return Err(Unavailable)
  }
  borrow_shared_capacity(owner.vm.capacity, owner.allocation).map_err(issue => {
    Resource(issue)
  })
}

///|
/// Called by the same enclosing owner after actual construction/body cleanup.
/// Live borrowers keep the complete peak charged. This returns only this VM
/// suballocation, never the whole VM reservation or a physical Store ACK.
pub fn close_platform_vm_working_capacity_after_cleanup(
  owner : PlatformVMWorkingCapacity,
) -> Result[Unit, ImportedChildLedgerIssue] {
  match platform_vm_working_original(owner) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  owner.closing = true
  match retire_shared_capacity(owner.allocation) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  release_shared_capacity(owner.allocation).map_err(issue => Resource(issue))
}
