///|
/// Explicit trusted installer inputs, never a request/profile/permission grant.
/// The Host and allocation already belong to the original Slot. The borrowed
/// FD remains owned by the physical installer beyond this mapping's ACK.
priv struct HolderEffectHostReadParentInstallation {
  host : @bootstrap.NativeHostBootstrap[@slot.NativeExecutorSlot]
  allocation : @bootstrap.NativeBootstrapAllocation[@slot.NativeExecutorSlot]
  fd : Int
  extent : @resources.BackedExecutionExtent
  limits : @resources.LedgerLimits
  overhead_retained : Int64
  overhead_execution : Int64
}

///|
/// Partial acquisition references in the existing setup scope. Additional
/// controls require the same reviewed caller funding; no normal profile exists.
priv struct HolderEffectHostReadParent {
  original : @slot.NativeExecutorSlot
  operation : @site.SiteOperation
  selected : HolderEffectHostReadParentInstallation
  mut region : @bootstrap.NativeBackedExecutionRegion[
    @slot.NativeExecutorSlot,
    @site.SiteOperation,
  ]?
  mut borrow : @bootstrap.NativeBootstrapBorrow[@slot.NativeExecutorSlot]?
  mut borrow_active : Bool
  mut loan : @bootstrap.NativeBackedExecutionLoan[
    @slot.NativeExecutorSlot,
    @site.SiteOperation,
  ]?
  mut view : @bootstrap.NativeBackedExecutionView[
    @slot.NativeExecutorSlot,
    @site.SiteOperation,
  ]?
  mut domain : @bootstrap.NativeBackedExecutionDomain[
    @slot.NativeExecutorSlot,
    @site.SiteOperation,
  ]?
  mut attempted : Bool
  mut closing : Bool
}

///|
fn holder_effect_host_read_parent_current(
  scope : HolderEffectHostSetupScope,
  parent : HolderEffectHostReadParent,
) -> Bool {
  !parent.closing &&
  scope.read_parent is Some(before) &&
  physical_equal(before, parent) &&
  holder_effect_host_read_scope_prepared(scope) &&
  !parent.closing &&
  scope.read_parent is Some(after) &&
  physical_equal(after, parent) &&
  scope.caller_operation is Some(operation) &&
  physical_equal(operation, parent.operation) &&
  parent.selected.host.require_current(parent.original) is Ok(_)
}

///|
/// Each returned physical partial is retained before observing its status. A
/// subsequent call cannot re-issue a loan, reset the FD header or acquire again.
fn select_holder_effect_host_read_parent(
  scope : HolderEffectHostSetupScope,
  parent : HolderEffectHostReadParent,
  original : @slot.NativeExecutorSlot,
  operation : @site.SiteOperation,
) -> (
  @bootstrap.NativeHostBootstrap[@slot.NativeExecutorSlot],
  @bootstrap.NativeBackedExecutionDomain[
    @slot.NativeExecutorSlot,
    @site.SiteOperation,
  ],
)? {
  guard !parent.attempted &&
    physical_equal(parent.original, original) &&
    physical_equal(parent.operation, operation) &&
    holder_effect_host_read_parent_current(scope, parent) else {
    return None
  }
  parent.attempted = true
  let selected = parent.selected
  let host = selected.host
  let region = match host.issue_backed_region(original, selected.allocation) {
    Ok(value) => value
    Err(_) => return None
  }
  parent.region = Some(region)
  guard holder_effect_host_read_parent_current(scope, parent) else {
    return None
  }
  let borrow = match host.borrow_backing(original) {
    Ok(value) => value
    Err(_) => return None
  }
  parent.borrow = Some(borrow)
  guard holder_effect_host_read_parent_current(scope, parent) &&
    host.enter_borrow_scope(original, borrow) is Ok(_) else {
    return None
  }
  parent.borrow_active = true
  guard holder_effect_host_read_parent_current(scope, parent) else {
    return None
  }
  let acquired = match
    host.lend_backed_region(
      original,
      region,
      borrow,
      operation,
      selected.extent,
      @resources.ExclusiveWrite,
      selected.limits,
      selected.overhead_retained,
      selected.overhead_execution,
    ) {
    Ok(value) => value
    Err(_) => return None
  }
  let loan = match acquired {
    @bootstrap.Lent(value) => value
    @bootstrap.Pending(value, _) => {
      parent.loan = Some(value)
      return None
    }
  }
  parent.loan = Some(loan)
  guard holder_effect_host_read_parent_current(scope, parent) else {
    return None
  }
  let mapped = match
    host.map_backed_view(original, loan, operation, selected.fd) {
    Ok(value) => value
    Err(_) => return None
  }
  let view = match mapped {
    @bootstrap.Mapped(value) => value
    @bootstrap.PendingView(value, _) => {
      parent.view = Some(value)
      return None
    }
  }
  parent.view = Some(view)
  guard holder_effect_host_read_parent_current(scope, parent) else {
    return None
  }
  let acquired = match host.acquire_backed_domain(original, view, operation) {
    Ok(value) => value
    Err(_) => return None
  }
  let domain = match acquired {
    @bootstrap.DomainReady(value) => value
    @bootstrap.DomainPending(value, _) => {
      parent.domain = Some(value)
      return None
    }
  }
  parent.domain = Some(domain)
  guard holder_effect_host_read_parent_current(scope, parent) &&
    host.transfer_backed_domain(original, domain, operation) is Ok(_) else {
    return None
  }
  // The child context must not run under the parent's physical borrow scope.
  // Failed leave retains the exact active scope for the original cleanup pass.
  guard host.leave_borrow_scope(original, borrow) is Ok(_) else { return None }
  parent.borrow_active = false
  guard holder_effect_host_read_parent_current(scope, parent) else {
    return None
  }
  Some((host, domain))
}

///|
fn prepare_holder_effect_host_read_parent(
  scope : HolderEffectHostSetupScope,
  original : @slot.NativeExecutorSlot,
  selected : HolderEffectHostReadParentInstallation,
) -> HolderEffectHostReadInstallation? {
  guard scope.read_parent is None &&
    holder_effect_host_read_scope_prepared(scope) &&
    scope.caller_operation is Some(operation) &&
    selected.fd >= 0 &&
    selected.host.require_current(original) is Ok(_) else {
    return None
  }
  let parent : HolderEffectHostReadParent = {
    original,
    operation,
    selected,
    region: None,
    borrow: None,
    borrow_active: false,
    loan: None,
    view: None,
    domain: None,
    attempted: false,
    closing: false,
  }
  // Publish before issue/lend/map/acquire. Selection failure never drops this
  // carrier into the old issue-only boundary or starts a substitute read.
  scope.read_parent = Some(parent)
  Some({
    select: (slot, child) => {
      select_holder_effect_host_read_parent(scope, parent, slot, child)
    },
  })
}

///|
/// The same Owner validates each ACK. No caller boolean proves a physical
/// return; failure leaves its exact handle for the next ordinary cleanup pass.
fn close_holder_effect_host_read_parent(
  scope : HolderEffectHostSetupScope,
) -> Bool {
  guard scope.read_parent is Some(parent) else { return true }
  parent.closing = true
  let host = parent.selected.host
  let original = parent.original
  let operation = parent.operation
  if parent.borrow_active {
    guard parent.borrow is Some(borrow) &&
      host.leave_borrow_scope(original, borrow) is Ok(_) else {
      return false
    }
    parent.borrow_active = false
  }
  if parent.domain is Some(domain) {
    guard host.close_backed_domain(original, domain, operation) is Ok(_) else {
      return false
    }
    parent.domain = None
  }
  if parent.view is Some(view) {
    guard host.close_backed_view(original, view, operation) is Ok(_) else {
      return false
    }
    parent.view = None
  }
  if parent.loan is Some(loan) {
    guard host.settle_backed_region_after_owner_ack(
        original,
        loan,
        operation,
        None,
      )
      is Ok(_) else {
      return false
    }
    parent.loan = None
  }
  if parent.region is Some(region) {
    guard host.close_backed_region(original, region) == Ok(true) else {
      return false
    }
    parent.region = None
  }
  if parent.borrow is Some(borrow) {
    guard host.return_borrow(original, borrow) is Ok(_) else { return false }
    parent.borrow = None
  }
  guard host.try_close(original) is Ok(_) else { return false }
  scope.read_parent = None
  true
}
