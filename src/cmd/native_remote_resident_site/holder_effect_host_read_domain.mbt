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
  // Sticky validation refusal is not physical context retirement or close ACK.
  mut store_current_refused : Bool
  mut ready : Bool
  mut active : Bool
}

///|
/// Necessary compatibility check between the existing Site reservation and
/// the original Host's independently admitted physical domain. This does not
/// derive a workspace bound, an allocator layout, or a numeric profile. In
/// particular, fitting raw record sizes does not prove page-charged demand.
fn holder_effect_host_read_budget_fits(
  profile : HolderEffectHostSetupProfile,
  payload_bytes : Int64,
  delegated_execution_bytes : Int64,
) -> Bool {
  guard holder_effect_host_setup_profile_valid(profile) &&
    payload_bytes > 0L &&
    delegated_execution_bytes > 0L &&
    holder_effect_host_extent_add(
      profile.setup_retained_bytes,
      profile.execution_bytes,
    )
    is Some(required_bytes) else {
    return false
  }
  required_bytes <= payload_bytes && required_bytes <= delegated_execution_bytes
}

///|
/// Get quantities from the same nominal Owner/current domain, never from a
/// candidate DATA descriptor. The small observation tuple leaves this frame
/// before entering the read allocator or acquiring any Root/Reader.
fn holder_effect_host_original_read_budget_fits(
  scope : HolderEffectHostSetupScope,
  original : @slot.NativeExecutorSlot,
  host : @bootstrap.NativeHostBootstrap[@slot.NativeExecutorSlot],
  domain : @bootstrap.NativeBackedExecutionDomain[
    @slot.NativeExecutorSlot,
    @site.SiteOperation,
  ],
  operation : @site.SiteOperation,
) -> Bool {
  guard scope.profile is Some(profile) &&
    host.backed_domain_capacity(original, domain, operation)
    is Ok((payload_bytes, delegated_execution_bytes)) else {
    return false
  }
  holder_effect_host_read_budget_fits(
    profile, payload_bytes, delegated_execution_bytes,
  )
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
    holder_effect_host_read_scope_prepared(scope) &&
    scope.caller_operation is Some(operation) &&
    (installed.select)(original, operation) is Some((host, domain)) &&
    holder_effect_host_read_scope_prepared(scope) &&
    scope.read_domain is None &&
    scope.depth == 1 &&
    scope.caller_operation is Some(actual_operation) &&
    physical_equal(operation, actual_operation) &&
    host.require_backed_domain_current(original, domain, operation) is Ok(_) &&
    holder_effect_host_original_read_budget_fits(
      scope, original, host, domain, operation,
    ) else {
    return false
  }
  let retained : HolderEffectHostReadDomain = {
    original,
    operation,
    host,
    domain,
    store_current_refused: false,
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
  guard holder_effect_host_read_scope_prepared(scope) &&
    scope.read_domain is Some(actual) &&
    physical_equal(actual, retained) &&
    enter_holder_effect_host_read_domain(retained) else {
    return false
  }
  holder_effect_host_read_scope_prepared(scope) &&
  scope.read_domain is Some(actual) &&
  physical_equal(actual, retained) &&
  holder_effect_host_read_domain_current(retained)
}

///|
/// Publish the full Store-backed callback only inside the original context.
/// The retained context is checked before and after every Store validation;
/// missing/pending/foreign domains cannot trigger a Store or Account read.
/// This closure captures original handles, never the scope/resources cell.
fn install_holder_effect_host_store_current(
  scope : HolderEffectHostSetupScope,
  current : () -> Bool,
) -> Bool {
  if scope.ordinary is Some(_) {
    guard scope.current_binding is None &&
      holder_effect_host_read_scope_prepared(scope) else {
      return false
    }
    let refused = Ref(false)
    scope.current_binding = Some(() => {
      if refused.val {
        return false
      }
      let valid = current()
      if !valid {
        refused.val = true
      }
      valid
    })
    return holder_effect_host_read_scope_current(scope)
  }
  guard scope.current_binding is None &&
    holder_effect_host_read_scope_prepared(scope) &&
    scope.read_domain is Some(read) &&
    scope.caller_operation is Some(operation) &&
    physical_equal(read.operation, operation) &&
    holder_effect_host_read_domain_current(read) else {
    return false
  }
  scope.current_binding = Some(() => {
    if read.store_current_refused {
      return false
    }
    let valid = holder_effect_host_read_domain_current(read) &&
      current() &&
      holder_effect_host_read_domain_current(read)
    if !valid {
      // The upper cleanup lifetime also retains this exact callback. Its
      // direct invocation must not repeat a refused/unknown Store lookup.
      read.store_current_refused = true
    }
    valid
  })
  // The ordinary current path preserves its post-callback/reentrant fences.
  // A refused Store validation stays installed for original retirement only.
  holder_effect_host_read_scope_current(scope)
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
