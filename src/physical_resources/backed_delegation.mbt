///|
/// Mapping extent and logical payload are different domains. The trusted
/// physical supplier provides its actual rounded mapping window; Core does
/// not infer OS pages, FD identity or physical adequacy from these numbers.
pub(all) struct BackedExecutionExtent {
  offset : Int64
  length : Int64
  payload_offset : Int64
  payload_length : Int64
} derive(Eq, Debug)

///|
pub(all) enum BackedExecutionAccess {
  ReadOnly
  ExclusiveWrite
} derive(Eq, Debug)

///|
/// Existing Resource-owner connection, not another allocator or Ledger.
/// P/C are the trusted provider and child execution originals, not IDs/FDs.
/// Control/record/list/report/callback overhead requires separate funding.
pub struct BackedExecutionRegion[P, C] {
  mut capacity : SharedCapacity?
  mut allocation : SharedAllocation?
  mut provider : P?
  mut owner_borrow : SharedBorrow?
  children : Array[BackedExecutionDelegation[P, C]]
  mut closing : Bool
  mut working : (PlatformVMWorkingCapacity, Int64, Int64)?
}

///|
pub struct BackedExecutionDelegation[P, C] {
  mut owner : BackedExecutionRegion[P, C]?
  mut child : C?
  mut borrow : SharedBorrow?
  mut logical : ExecutionDelegation?
  extent : BackedExecutionExtent
  access : BackedExecutionAccess
  limits : LedgerLimits
  mut peak_retention : Int64
  // The original logical reservation's open flag is the settlement state.
  // None remains unknown final usage; it never means zero usage or unsent.
  mut final_usage : LedgerUsage?
  // Sticky successful nonzero usage, including transient reservation-only reports.
  // Admission must not erase that history when a later report returns to zero.
  priv mut live_usage_reported : Bool
  // One original read/workspace lifetime, not another byte reservation.
  mut read_use_issued : Bool
  mut read_use : BackedExecutionReadUse[P, C]?
}

///|
pub(all) enum BackedExecutionIssue {
  ForeignOriginal
  InvalidExtent
  ExtentConflict
  DuplicateChild
  RegionClosing
  Retired
  CleanupPending
  ChangedFinalUsage
  ReadUseAlreadyIssued
  LiveAccessAlreadyIssued
  LiveChildAlreadyAdmitted
  Resource(LedgerIssue)
} derive(Eq, Debug)

///|
/// One-shot selection of an otherwise unborrowed allocation. Retain its
/// ORIGINAL borrow and retire new ordinary borrowing before issuing this
/// region. Retirement is not physical release, and is never reset. Existing
/// APIs/SharedAllocation fields are unchanged. No physical stop is observed.
pub fn[P, C] issue_backed_execution_region(
  capacity : SharedCapacity,
  allocation : SharedAllocation,
  provider : P,
) -> Result[BackedExecutionRegion[P, C], BackedExecutionIssue] {
  if !physical_equal(capacity, allocation.owner) {
    return Err(ForeignOriginal)
  }
  if allocation.readers != 0 || allocation.retiring || allocation.released {
    return Err(CleanupPending)
  }
  let borrow = match borrow_shared_capacity(capacity, allocation) {
    Ok(value) => value
    Err(issue) => return Err(Resource(issue))
  }
  // The same synchronous Resource Owner has already checked the mutation
  // fence in borrow_shared_capacity. This is its existing retirement flag;
  // no callback/await can intervene or orphan the just-issued original loan.
  allocation.retiring = true
  Ok({
    capacity: Some(capacity),
    allocation: Some(allocation),
    provider: Some(provider),
    owner_borrow: Some(borrow),
    children: [],
    closing: false,
    working: None,
  })
}

///|
fn[P, C] check_backed_region_current(
  region : BackedExecutionRegion[P, C],
  provider : P,
) -> Result[Unit, BackedExecutionIssue] {
  guard region.provider is Some(original) && physical_equal(original, provider) else {
    return Err(ForeignOriginal)
  }
  guard region.capacity is Some(capacity) &&
    region.allocation is Some(allocation) &&
    region.owner_borrow is Some(borrow) else {
    return Err(Retired)
  }
  if !physical_equal(capacity, allocation.owner) ||
    !physical_equal(borrow.allocation, allocation) ||
    borrow.returned ||
    allocation.released ||
    (region.working is None && !allocation.retiring) ||
    !capacity.reservation.open {
    return Err(Retired)
  }
  match check_original_resources_mutable(capacity.ledger) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  if region.working is Some((working, _, _)) {
    match require_platform_vm_capacity(working.vm, capacity.ledger, capacity) {
      Err(_) => return Err(Resource(ChildFundingUnavailable))
      Ok(_) => ()
    }
    if !physical_equal(working.allocation, allocation) {
      return Err(ForeignOriginal)
    }
  }
  Ok(())
}

///|
fn[P, C] backed_region_current(
  region : BackedExecutionRegion[P, C],
  provider : P,
) -> Result[(SharedCapacity, SharedAllocation), BackedExecutionIssue] {
  match check_backed_region_current(region, provider) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard region.capacity is Some(capacity) &&
    region.allocation is Some(allocation) else {
    return Err(Retired)
  }
  Ok((capacity, allocation))
}

///|
fn backed_extent_valid(extent : BackedExecutionExtent, bytes : Int64) -> Bool {
  extent.offset >= 0L &&
  extent.length > 0L &&
  extent.offset <= bytes &&
  extent.length <= bytes - extent.offset &&
  extent.payload_offset >= 0L &&
  extent.payload_length > 0L &&
  extent.payload_offset <= extent.length &&
  extent.payload_length <= extent.length - extent.payload_offset
}

///|
/// Claim before worker allocation/I/O. The actual physical mapping window
/// participates in writer exclusion, not merely the smaller logical payload.
/// Byte allowances within it are suballocations of the original capacity;
/// independent overhead is charged to the SAME Ledger provisioning reserve.
pub fn[P, C] reserve_backed_execution_delegation(
  region : BackedExecutionRegion[P, C],
  provider : P,
  child : C,
  extent : BackedExecutionExtent,
  access : BackedExecutionAccess,
  limits : LedgerLimits,
  overhead_retained : Int64,
  overhead_execution : Int64,
) -> Result[BackedExecutionDelegation[P, C], BackedExecutionIssue] {
  let (capacity, allocation) = match backed_region_current(region, provider) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if region.closing ||
    capacity.closing ||
    (region.working is Some((working, _, _)) && working.closing) {
    return Err(RegionClosing)
  }
  if !backed_extent_valid(extent, allocation.bytes) ||
    limits.retained_bytes < 0L ||
    limits.execution_bytes < 0L ||
    (
      region.working is None &&
      (
        limits.retained_bytes > extent.payload_length ||
        limits.execution_bytes > extent.payload_length - limits.retained_bytes
      )
    ) {
    return Err(InvalidExtent)
  }
  // This closed VM binding delegates one original child and grows only that
  // child's actual claim. It is not a mapped window or shared read region.
  if region.working is Some(_) &&
    (
      access != ExclusiveWrite ||
      !region.children.is_empty() ||
      extent.offset != 0L ||
      extent.payload_offset != 0L ||
      extent.length != allocation.bytes ||
      extent.payload_length != allocation.bytes
    ) {
    return Err(InvalidExtent)
  }
  for other in region.children {
    if other.child is Some(original) && physical_equal(original, child) {
      return Err(DuplicateChild)
    }
    if extent.offset < other.extent.offset + other.extent.length &&
      other.extent.offset < extent.offset + extent.length &&
      (access == ExclusiveWrite || other.access == ExclusiveWrite) {
      return Err(ExtentConflict)
    }
  }
  if allocation.readers == 2147483647 {
    return Err(Resource(InvalidCharge))
  }
  let logical = match
    reserve_execution_delegation(
      capacity.ledger,
      { ..limits, retained_bytes: 0L, execution_bytes: 0L, },
      overhead_retained,
      overhead_execution,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Resource(issue))
  }
  // Only this same region issues child borrows after ordinary borrowing was
  // retired. This remains the original SharedBorrow reader/return mechanism.
  allocation.readers += 1
  let borrow : SharedBorrow = { allocation, returned: false, }
  let ticket : BackedExecutionDelegation[P, C] = {
    owner: Some(region),
    child: Some(child),
    borrow: Some(borrow),
    logical: Some(logical),
    extent,
    access,
    limits,
    peak_retention: 0L,
    final_usage: None,
    live_usage_reported: false,
    read_use_issued: false,
    read_use: None,
  }
  region.children.push(ticket)
  Ok(ticket)
}

///|
/// Check the same original region, child and ticket without constructing a
/// description or intermediate projection tuples. This is a current predicate,
/// not a new reservation, physical stop acknowledgement or a launch grant.
pub fn[P, C] check_backed_execution_delegation_current(
  region : BackedExecutionRegion[P, C],
  provider : P,
  child : C,
  ticket : BackedExecutionDelegation[P, C],
) -> Result[Unit, BackedExecutionIssue] {
  match check_backed_region_current(region, provider) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard region.capacity is Some(capacity) &&
    region.allocation is Some(allocation) else {
    return Err(Retired)
  }
  guard ticket.owner is Some(owner) &&
    physical_equal(owner, region) &&
    ticket.child is Some(original) &&
    physical_equal(original, child) &&
    ticket.borrow is Some(borrow) &&
    ticket.logical is Some(logical) else {
    return Err(ForeignOriginal)
  }
  // Avoid a new capturing callback merely to check this exact membership.
  let mut found = false
  for original in region.children {
    if physical_equal(original, ticket) {
      found = true
      break
    }
  }
  if !found {
    return Err(ForeignOriginal)
  }
  if !physical_equal(borrow.allocation, allocation) ||
    borrow.returned ||
    !physical_equal(logical.owner, capacity.ledger) ||
    allocation.readers < 2 {
    return Err(Retired)
  }
  Ok(())
}

///|
fn[P, C] backed_child_current(
  region : BackedExecutionRegion[P, C],
  provider : P,
  child : C,
  ticket : BackedExecutionDelegation[P, C],
) -> Result[
  (SharedCapacity, SharedBorrow, ExecutionDelegation),
  BackedExecutionIssue,
] {
  match
    check_backed_execution_delegation_current(region, provider, child, ticket) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard region.capacity is Some(capacity) &&
    ticket.borrow is Some(borrow) &&
    ticket.logical is Some(logical) else {
    return Err(Retired)
  }
  Ok((capacity, borrow, logical))
}

///|
/// Pure original quota/extent DATA; not worker startup, physical ACK or a grant.
pub fn[P, C] backed_execution_delegation_description(
  region : BackedExecutionRegion[P, C],
  provider : P,
  child : C,
  ticket : BackedExecutionDelegation[P, C],
) -> Result[
  (BackedExecutionExtent, BackedExecutionAccess, LedgerLimits),
  BackedExecutionIssue,
] {
  match
    check_backed_execution_delegation_current(region, provider, child, ticket) {
    Err(issue) => Err(issue)
    Ok(_) => {
      let extent = if region.working is Some(_) {
        let bytes = region.allocation.unwrap().bytes
        {
          offset: 0L,
          length: bytes,
          payload_offset: 0L,
          payload_length: bytes,
        }
      } else {
        ticket.extent
      }
      Ok((extent, ticket.access, ticket.limits))
    }
  }
}

///|
fn[P, C] backed_usage_valid(
  ticket : BackedExecutionDelegation[P, C],
  usage : LedgerUsage,
) -> Bool {
  let limits = ticket.limits
  usage.held_bytes >= 0L &&
  usage.held_bytes <= limits.retained_bytes &&
  usage.reserved_retention_bytes >= 0L &&
  usage.reserved_retention_bytes <= limits.retained_bytes - usage.held_bytes &&
  usage.reserved_execution_bytes >= 0L &&
  usage.reserved_execution_bytes <= limits.execution_bytes &&
  usage.peak_retention_bytes >=
  usage.held_bytes + usage.reserved_retention_bytes &&
  usage.peak_retention_bytes >= ticket.peak_retention &&
  usage.peak_retention_bytes <= limits.retained_bytes
}

///|
fn backed_logical_usage(usage : LedgerUsage) -> LedgerUsage {
  // These byte facts were validated against the original shared extent; they
  // are not erased from the ticket's bounds/peak. The parent already reserves
  // that backing once, and independent overhead stays reserved separately.
  {
    ..usage,
    held_bytes: 0L,
    reserved_retention_bytes: 0L,
    reserved_execution_bytes: 0L,
    peak_retention_bytes: 0L,
  }
}

///|
pub fn[P, C] report_backed_execution_delegation(
  region : BackedExecutionRegion[P, C],
  provider : P,
  child : C,
  ticket : BackedExecutionDelegation[P, C],
  usage : LedgerUsage,
) -> Result[Unit, BackedExecutionIssue] {
  let (capacity, _, logical) = match
    backed_child_current(region, provider, child, ticket) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !logical.reservation.open {
    return Err(Retired)
  }
  if !backed_usage_valid(ticket, usage) ||
    !platform_vm_backed_usage_fits(region, usage) {
    return Err(Resource(InvalidCharge))
  }
  match
    report_execution_delegation(
      capacity.ledger,
      logical,
      backed_logical_usage(usage),
    ) {
    Err(issue) => Err(Resource(issue))
    Ok(_) => {
      ticket.peak_retention = usage.peak_retention_bytes
      ticket.live_usage_reported = ticket.live_usage_reported ||
        usage != initial_ledger_usage
      Ok(())
    }
  }
}

///|
fn backed_final_usage_equal(left : LedgerUsage?, right : LedgerUsage?) -> Bool {
  // Derived typed equality follows every field of the owned record, including
  // current live/reserved counts. None is still distinct from a zero report.
  left == right
}

///|
// Both first-bootstrap consumers use the same reported-history fence. This is
// additional to their original ticket/runtime/current checks, not proof that a
// zero-byte or settled identity is pristine or that a physical child stopped.
fn[P, C] backed_child_usage_unreported(
  ticket : BackedExecutionDelegation[P, C],
) -> Bool {
  guard ticket.logical is Some(logical) else { return false }
  !ticket.live_usage_reported &&
  logical.reservation.open &&
  logical.planning == 0 &&
  logical.attempts == 0 &&
  logical.reserved_attempts == 0 &&
  logical.live_reservations == 0 &&
  logical.live_delegations == 0 &&
  logical.holdings == 0 &&
  logical.transferred == 0L &&
  logical.uncertain == 0L &&
  ticket.peak_retention == 0L &&
  ticket.final_usage is None
}

///|
/// Existing trusted physical Owner only, AFTER the same child stop AND actual
/// mapped-view/FD borrower retirement. Cancellation, Promise settlement, raw
/// EOF, equal IDs or this API itself cannot supply that observation. Unknown
/// final usage consumes the original logical remainder conservatively. Keep
/// overhead/borrow custody until this boundary; independent Store is separate.
pub fn[P, C] settle_backed_execution_after_owner_ack(
  region : BackedExecutionRegion[P, C],
  provider : P,
  child : C,
  ticket : BackedExecutionDelegation[P, C],
  final_usage : LedgerUsage?,
) -> Result[Unit, BackedExecutionIssue] {
  let (capacity, borrow, logical) = match
    backed_child_current(region, provider, child, ticket) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Root/Reader aliases and pending physical context retirement still borrow
  // this original child. Even a parent stop observation cannot erase them.
  if ticket.read_use is Some(_) {
    return Err(CleanupPending)
  }
  if logical.reservation.open {
    if final_usage is Some(usage) &&
      (
        !backed_usage_valid(ticket, usage) ||
        !platform_vm_backed_usage_fits(region, usage)
      ) {
      return Err(Resource(InvalidCharge))
    }
    match
      settle_execution_delegation(
        capacity.ledger,
        logical,
        final_usage.map(backed_logical_usage),
      ) {
      Err(issue) => return Err(Resource(issue))
      Ok(_) => ticket.final_usage = final_usage
    }
  } else if !backed_final_usage_equal(ticket.final_usage, final_usage) {
    return Err(ChangedFinalUsage)
  }
  match return_shared_capacity(borrow) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  let mut index = 0
  while !physical_equal(region.children[index], ticket) {
    index += 1
  }
  let last = region.children.pop().unwrap()
  if index < region.children.length() {
    region.children[index] = last
  }
  ticket.owner = None
  ticket.child = None
  ticket.borrow = None
  ticket.logical = None
  // Retired handles retain only bounded scalar facts, never the parent graph.
  Ok(())
}

///|
/// Graceful close does not cancel entered children or release physical memory.
/// Returning this region's original accounting borrow requires all children
/// already stopped/retired. The original physical allocation/capacity Owners
/// still perform their own actual release and settlement afterwards.
pub fn[P, C] close_backed_execution_region(
  region : BackedExecutionRegion[P, C],
  provider : P,
) -> Result[Bool, BackedExecutionIssue] {
  let (_, _) = match backed_region_current(region, provider) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  region.closing = true
  if !region.children.is_empty() {
    return Ok(false)
  }
  let borrow = region.owner_borrow.unwrap()
  match return_shared_capacity(borrow) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  region.capacity = None
  region.allocation = None
  region.provider = None
  region.owner_borrow = None
  region.working = None
  Ok(true)
}
