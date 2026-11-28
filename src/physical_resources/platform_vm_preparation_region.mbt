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
    capacity_observation(
      ledger,
      15,
      -1,
      execution,
      0L,
      ledger.limits.execution_bytes,
      ledger.usage.reserved_execution_bytes,
    )
    return Err(ExecutionLimit)
  }
  guard origin.acquire_window is Some(acquire) else {
    return Err(RetentionLimit)
  }
  let before = ledger.usage
  origin.acquiring_window = true
  let result = match acquire(retained, execution) {
    Err(issue) => {
      if issue is ExecutionLimit {
        capacity_observation(
          ledger,
          16,
          -1,
          execution,
          0L,
          ledger.limits.execution_bytes,
          ledger.usage.reserved_execution_bytes,
        )
      }
      Err(issue)
    }
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
            capacity_observation(
              ledger,
              15,
              -1,
              execution,
              0L,
              ledger.limits.execution_bytes,
              ledger.usage.reserved_execution_bytes,
            )
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

///|
/// Reserve planned run counters on the same platform VM preparation child.
/// Only a preparation-only delegation can make this transition. Memory and
/// planning bounds, child identity and the provisioning attempt stay intact.
pub fn[P, C, I] fund_platform_vm_preparation_run(
  owner : BackedPreparationAdmission[I],
  access : BackedExecutionLiveAccess[P, C, I],
  input : I,
  attempts : Int,
  holdings : Int,
  transfer_bytes : Int64,
) -> Result[Unit, ImportedChildLedgerIssue] {
  if attempts <= 0 || holdings < 0 || transfer_bytes < 0L {
    return Err(InvalidOriginal)
  }
  match check_backed_preparation_input(owner, input) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let frame = owner.initial.frame
  guard owner.initial.host_taken &&
    frame.ledger is Some(child_ledger) &&
    access.child_origin is Some(origin) &&
    physical_equal(origin, frame.origin) else {
    return Err(ForeignOriginal)
  }
  match check_imported_original_child_ledger(frame, child_ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // No external observations after this fence. A callback during currentness
  // may have changed the original, stopped it, or already funded the plan.
  match check_backed_preparation_input(owner, input) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard access.original is Some(original) &&
    physical_equal(original, access) &&
    !access.closing &&
    access.child_origin is Some(current_origin) &&
    physical_equal(current_origin, origin) &&
    access.runtime is Some(runtime) &&
    physical_equal(runtime, input) &&
    access.region is Some(region) &&
    !region.closing &&
    region.working is Some((working, _, _)) &&
    !working.closing &&
    !working.vm.closing &&
    working.vm.failure is None &&
    access.read_use is Some(read) &&
    !read.closing &&
    access.ticket is Some(ticket) &&
    ticket.logical is Some(logical) &&
    logical.reservation.open &&
    region.capacity is Some(capacity) &&
    !capacity.closing &&
    physical_equal(capacity.ledger, logical.owner) &&
    frame.pending_report is None &&
    frame.pending_report_issue is None &&
    !frame.stop_attempted &&
    ticket.limits == child_ledger.limits else {
    return Err(Unavailable)
  }
  let old = ticket.limits
  if logical.limits.attempts != old.attempts ||
    logical.limits.holdings != old.holdings ||
    logical.limits.transfer_bytes != old.transfer_bytes {
    return Err(ForeignOriginal)
  }
  // Retrying the same target observes the funded delegation. A different
  // target cannot refill or shrink it, even before any Model Call is entered.
  if old.attempts == attempts &&
    old.holdings == holdings &&
    old.transfer_bytes == transfer_bytes {
    return Ok(())
  }
  if old.attempts != 0 ||
    old.holdings != 0 ||
    old.transfer_bytes != 0L ||
    logical.reservation.transfer != 0L {
    return Err(AlreadyConsumed)
  }
  let parent = logical.owner
  match check_original_resources_mutable_current(parent) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  fund_platform_vm_run_delegation_current(
    ticket, logical, child_ledger, attempts, holdings, transfer_bytes,
  ).map_err(issue => ImportedChildLedgerIssue::Resource(issue))
}

///|
/// Admit the execution dimensions of this exact completed in-process Plan
/// against the same physical parent. The Request started without attempts,
/// holdings or transfer and still owns its original working bytes. No
/// operation starts, no child is replaced and no cleanup is acknowledged.
pub fn[P, C, I, Plan] fund_platform_vm_prepared_run(
  access : BackedExecutionLiveAccess[P, C, I],
  owner : BackedPreparationAdmission[I],
  input : I,
  capacity : PreparationCapacity[I, Plan],
  plan : Plan,
  attempts : Int,
  holdings : Int,
  transfer_bytes : Int64,
  initial_transfer_bytes? : Int64? = None,
) -> Result[Unit, BackedExecutionIssue] {
  let initial_transfer = initial_transfer_bytes.unwrap_or(transfer_bytes)
  if attempts < 0 ||
    holdings < 0 ||
    transfer_bytes < 0L ||
    initial_transfer < 0L ||
    initial_transfer > transfer_bytes ||
    (attempts == 0 && holdings == 0 && transfer_bytes == 0L) {
    return Err(Resource(InvalidCharge))
  }
  if !(check_backed_preparation_input(owner, input) is Ok(_)) {
    return Err(ForeignOriginal)
  }
  let (region, _, _, ticket, read_use) = match
    backed_live_original(access, input) {
    Err(issue) => return Err(issue)
    Ok(original) => original
  }
  guard region.working is Some((working, _, _)) &&
    access.child_origin is Some(origin) &&
    ticket.logical is Some(logical) else {
    return Err(ForeignOriginal)
  }
  let frame = owner.initial.frame
  guard check_backed_preparation_input(owner, input) is Ok(_) &&
    owner.initial.host_taken &&
    frame.ledger is Some(ledger) &&
    physical_equal(origin, frame.origin) &&
    origin.working is Some((mounted, _, _)) &&
    physical_equal(mounted, working) &&
    check_imported_original_child_ledger_current(frame, ledger) is Ok(_) &&
    physical_equal(capacity.ledger, ledger) &&
    capacity.input is Some(original_input) &&
    physical_equal(original_input, input) &&
    capacity.body is Some(original_plan) &&
    physical_equal(original_plan, plan) else {
    return Err(ForeignOriginal)
  }
  if access.closing ||
    read_use.closing ||
    region.closing ||
    working.closing ||
    working.vm.capacity.closing ||
    working.vm.closing ||
    working.vm.failure is Some(_) ||
    frame.stop_attempted ||
    frame.pending_report is Some(_) ||
    frame.pending_report_issue is Some(_) ||
    capacity.phase != Ready ||
    capacity.borrowers != 0 ||
    capacity.retirement_claimed ||
    !reservation_open(capacity.reservation.reservation) {
    return Err(RegionClosing)
  }
  let parent = logical.owner
  match reservation_check_current(parent, logical.reservation) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  match check_imported_child_admission_current(parent) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  match check_original_resources_mutable_current(ledger) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  let old = ticket.limits
  if old.attempts != 0 ||
    old.holdings != 0 ||
    old.transfer_bytes != 0L ||
    ledger.limits != old ||
    logical.reservation.transfer != 0L ||
    !backed_child_usage_unreported(ticket) ||
    working.fund_transfer is Some(_) {
    return Err(Resource(InvalidCharge))
  }
  match
    fund_platform_vm_run_delegation_current(
      ticket, logical, ledger, attempts, holdings, initial_transfer,
    ) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  if initial_transfer < transfer_bytes {
    working.fund_transfer = Some((required, retained, executing) => {
      guard backed_live_original(access, input)
        is Ok((active_region, _, _, active_ticket, active_read)) &&
        physical_equal(active_region, region) &&
        physical_equal(active_ticket, ticket) &&
        physical_equal(active_read, read_use) &&
        !access.closing &&
        !active_read.closing &&
        !region.closing &&
        !working.closing &&
        !working.vm.closing &&
        !origin.stopping &&
        !origin.unavailable &&
        frame.pending_report is None &&
        frame.pending_report_issue is None &&
        !frame.stop_attempted &&
        origin.ledger is Some(current) &&
        physical_equal(current, ledger) &&
        ticket.logical is Some(active_logical) &&
        physical_equal(active_logical, logical) &&
        required <= transfer_bytes else {
        return Err(TransferLimit)
      }
      fund_platform_vm_run_transfer_current(
        ticket, logical, ledger, required, retained, executing,
      )
    })
  }
  Ok(())
}

///|
// After both exact quotes succeed, grow the single existing parent debit and
// all its live observations. The child's attempt installs immediately after
// this returns. A refusal leaves the old transfer quota and history intact.
fn[P, C] fund_platform_vm_run_transfer_current(
  ticket : BackedExecutionDelegation[P, C],
  logical : ExecutionDelegation,
  ledger : Ledger,
  required : Int64,
  retained : Int64,
  executing : Int64,
) -> Result[Unit, LedgerIssue] {
  let parent = logical.owner
  let before = ledger.limits.transfer_bytes
  guard !physical_equal(parent, ledger) &&
    required > before &&
    ticket.limits == ledger.limits &&
    logical.limits.transfer_bytes == before &&
    logical.reservation.transfer ==
    before - logical.transferred - logical.uncertain else {
    return Err(InvalidCharge)
  }
  reservation_check_current(parent, logical.reservation).bind(_ => {
    let usage = parent.usage
    let delta = required - before
    if delta >
      parent.limits.transfer_bytes -
      usage.transferred_bytes -
      usage.uncertain_transfer_bytes -
      usage.reserved_transfer_bytes {
      return Err(TransferLimit)
    }
    grow_imported_platform_working_current(ledger, retained, executing).map(_ => {
      parent.usage = {
        ..usage,
        reserved_transfer_bytes: usage.reserved_transfer_bytes + delta,
      }
      logical.reservation.transfer += delta
      logical.limits = { ..logical.limits, transfer_bytes: required, }
      ticket.limits = { ..ticket.limits, transfer_bytes: required, }
      ledger.limits = ticket.limits
    })
  })
}

///|
// Both entry points have already checked their original Request and current
// parent. This is the only write to the linked delegation and ledgers.
fn[P, C] fund_platform_vm_run_delegation_current(
  ticket : BackedExecutionDelegation[P, C],
  logical : ExecutionDelegation,
  child_ledger : Ledger,
  attempts : Int,
  holdings : Int,
  transfer_bytes : Int64,
) -> Result[Unit, LedgerIssue] {
  let parent = logical.owner
  let old = ticket.limits
  let usage = parent.usage
  if attempts >
    parent.limits.attempts -
    parent.delegated_attempts -
    usage.attempts -
    usage.reserved_attempts {
    return Err(AttemptLimit)
  }
  if holdings >
    parent.limits.holdings - parent.delegated_holdings - usage.holdings {
    return Err(HoldingLimit)
  }
  if transfer_bytes >
    parent.limits.transfer_bytes -
    usage.transferred_bytes -
    usage.uncertain_transfer_bytes -
    usage.reserved_transfer_bytes {
    return Err(TransferLimit)
  }
  // Construct the replacement records before changing either owner. These
  // fixed controls belong to the Request's already paid phase envelope.
  let next_usage = {
    ..usage,
    reserved_transfer_bytes: usage.reserved_transfer_bytes + transfer_bytes,
  }
  let next_logical = { ..logical.limits, attempts, holdings, transfer_bytes, }
  let next_limits = { ..old, attempts, holdings, transfer_bytes, }
  // The provisioning attempt was reserved when this ticket opened. Debit
  // only the new allowance; the same reservation reports cumulative use.
  parent.delegated_attempts += attempts
  parent.delegated_holdings += holdings
  parent.usage = next_usage
  logical.reservation.transfer = transfer_bytes
  logical.limits = next_logical
  ticket.limits = next_limits
  child_ledger.limits = next_limits
  Ok(())
}
