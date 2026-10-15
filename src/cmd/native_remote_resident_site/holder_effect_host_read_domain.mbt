///|
/// A trusted installer supplies already acquired original handles. It cannot
/// replace this with extent DATA, a profile, a Site quota or Account permission.
/// Parent view/loan/Host/FD cleanup remains with that same installation owner.
priv struct HolderEffectHostReadInstallation {
  select : (@slot.NativeExecutorSlot, @site.SiteOperation) -> (
    @bootstrap.NativeHostBootstrap[@slot.NativeExecutorSlot],
    @bootstrap.NativeBackedExecutionDomain[
      @slot.NativeExecutorSlot,
      @site.SiteOperation,
    ],
  )?
}

///|
/// Private references to existing Owners, not another allocator or cleanup
/// owner. These extra controls require reviewed funding before profile adoption.
priv struct HolderEffectHostReadDomain {
  original : @slot.NativeExecutorSlot
  operation : @site.SiteOperation
  host : @bootstrap.NativeHostBootstrap[@slot.NativeExecutorSlot]
  domain : @bootstrap.NativeBackedExecutionDomain[
    @slot.NativeExecutorSlot,
    @site.SiteOperation,
  ]
  mut ready : Bool
  mut active : Bool
}

///|
fn install_holder_effect_host_read_domain(
  scope : HolderEffectHostSetupScope,
  original : @slot.NativeExecutorSlot,
  installation : HolderEffectHostReadInstallation?,
) -> Bool {
  guard installation is Some(installed) &&
    scope.read_domain is None &&
    scope.depth == 1 &&
    holder_effect_host_read_scope_current(scope) &&
    scope.caller_operation is Some(operation) &&
    (installed.select)(original, operation) is Some((host, domain)) &&
    holder_effect_host_read_scope_current(scope) &&
    host.require_backed_domain_current(original, domain, operation) is Ok(_) else {
    return false
  }
  let retained : HolderEffectHostReadDomain = {
    original,
    operation,
    host,
    domain,
    ready: false,
    active: false,
  }
  // Retain before the fallible read-use/physical-context preparation. Any
  // partial initialization is closed through this exact original domain.
  scope.read_domain = Some(retained)
  guard host.prepare_backed_read_context(original, domain, operation) is Ok(_) else {
    return false
  }
  retained.ready = true
  enter_holder_effect_host_read_domain(retained)
}

///|
fn holder_effect_host_read_domain_current(
  read : HolderEffectHostReadDomain,
) -> Bool {
  read.ready &&
  read.active &&
  read.host.require_backed_read_context_current(
    read.original,
    read.domain,
    read.operation,
  )
  is Ok(_)
}

///|
fn enter_holder_effect_host_read_domain(
  read : HolderEffectHostReadDomain,
) -> Bool {
  guard read.ready &&
    !read.active &&
    read.host.enter_backed_read_context(
      read.original,
      read.domain,
      read.operation,
    )
    is Ok(_) else {
    return false
  }
  read.active = true
  true
}

///|
fn leave_holder_effect_host_read_domain(
  read : HolderEffectHostReadDomain,
) -> Bool {
  if !read.active {
    return true
  }
  guard read.host.leave_backed_read_context(
      read.original,
      read.domain,
      read.operation,
    )
    is Ok(_) else {
    // Failed leave retains the same active carrier for existing cleanup.
    return false
  }
  read.active = false
  true
}

///|
/// A separate frame ensures the original bounded failure/temporary cleanup
/// aliases leave this function before the caller asks the domain to retire.
fn retry_holder_effect_host_read_failure(
  scope : HolderEffectHostSetupScope,
) -> Bool {
  guard scope.pending is Some(failure) else { return true }
  if scope.read_domain is Some(read) {
    guard !read.active &&
      read.host.enter_backed_read_cleanup(
        read.original,
        read.domain,
        read.operation,
      )
      is Ok(_) else {
      return false
    }
    read.active = true
    let closed = failure.retry_cleanup() is Ok(_)
    let left = leave_holder_effect_host_read_domain(read)
    if !closed || !left {
      return false
    }
  } else if failure.retry_cleanup() is Err(_) {
    return false
  }
  scope.pending = None
  true
}

///|
/// Actual Owner ACK covers read users/aliases and this domain, not the parent
/// view/loan/Host/FD or worker. Those original responsibilities stay installed.
fn close_holder_effect_host_read_domain(
  scope : HolderEffectHostSetupScope,
) -> Bool {
  guard scope.read_domain is Some(read) else { return true }
  guard leave_holder_effect_host_read_domain(read) &&
    read.host.close_backed_domain(read.original, read.domain, read.operation)
    is Ok(_) else {
    return false
  }
  read.ready = false
  scope.read_domain = None
  true
}
