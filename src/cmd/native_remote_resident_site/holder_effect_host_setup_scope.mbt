///|
/// Bounded ordinary Host inputs retain their exact current verifier and pending
/// physical failure. No mapped profile, allocator or caller reservation is issued.
priv struct HolderEffectHostSetupScope {
  site : @site.ExecutionSite
  ordinary : HolderEffectHostOrdinaryLimits
  mut preparation_binding : (() -> Bool)?
  mut current_binding : (() -> Bool)?
  mut depth : Int
  mut pending : @bounded_files.NativeBoundedTextFailure?
  mut cleanup : @site.SiteCleanup?
  mut retiring : Bool
}

///|
/// No Store read belongs to this predicate. The exact admitted Site selection
/// and original Slot establish the scope of bounded ordinary input preparation;
/// runtime/current validation still follows before each actual read.
fn holder_effect_host_setup_selection_current(
  site : @site.ExecutionSite,
  expected_key : String,
  expected_generation : Int,
  expected_runtime : String,
  current_site : () -> Bool,
) -> Bool {
  current_site() &&
  @site.site_key(site) == expected_key &&
  @site.site_binding_current(site, expected_generation, expected_runtime)
}

///|
/// Capacity/binding fence only, never Account/read/publication authorization.
/// Capture the immutable original selection and actual current verifiers, not
/// the caller's resources cells or a cached current answer.
fn holder_effect_host_setup_binding(
  site : @site.ExecutionSite,
  expected_key : String,
  expected_generation : Int,
  expected_runtime : String,
  current_site : () -> Bool,
  current_runtime : () -> Bool,
) -> () -> Bool {
  () => {
    holder_effect_host_setup_selection_current(
      site, expected_key, expected_generation, expected_runtime, current_site,
    ) &&
    current_runtime()
  }
}

///|
fn holder_effect_host_read_scope_bound(
  scope : HolderEffectHostSetupScope,
) -> Bool {
  !scope.retiring && scope.pending is None && scope.depth > 0
}

///|
/// Reentrant retirement or verifier replacement refuses before physical input.
fn holder_effect_host_read_scope_prepared(
  scope : HolderEffectHostSetupScope,
) -> Bool {
  guard holder_effect_host_read_scope_bound(scope) &&
    scope.preparation_binding is Some(prepared) &&
    prepared() else {
    return false
  }
  holder_effect_host_read_scope_bound(scope) &&
  scope.preparation_binding is Some(actual) &&
  physical_equal(actual, prepared)
}

///|
fn holder_effect_host_read_scope_current(
  scope : HolderEffectHostSetupScope,
) -> Bool {
  guard holder_effect_host_read_scope_bound(scope) &&
    scope.current_binding is Some(current) else {
    return false
  }
  if !current() {
    scope.retiring = true
    return false
  }
  let valid = holder_effect_host_read_scope_bound(scope) &&
    scope.current_binding is Some(actual) &&
    physical_equal(actual, current)
  if !valid {
    scope.retiring = true
  }
  valid
}

///|
/// Ordinary metadata uses its existing Site Owner; no child allocator is entered.
fn with_holder_effect_host_site_metadata(
  _scope : HolderEffectHostSetupScope,
  update : () -> Bool,
) -> Bool {
  update()
}

///|
fn observe_holder_effect_host_read_failure(
  scope : HolderEffectHostSetupScope,
  failure : @bounded_files.NativeBoundedTextFailure,
) -> Unit {
  // Every subsequent physical read is refused while this original failure is
  // unresolved. No list of retry attempts or new Reader is accumulated.
  if scope.pending is None {
    scope.pending = Some(failure)
    if scope.cleanup is None {
      // The original pending failure remains retained until its actual
      // cleanup ACK; this token is not permission for another read.
      ignore(
        with_holder_effect_host_site_metadata(scope, () => {
          scope.cleanup = Some(@site.retain_site_cleanup(scope.site))
          true
        }),
      )
    }
  }
}

///|
fn enter_holder_effect_host_read_scope(
  scope : HolderEffectHostSetupScope,
) -> Bool {
  if scope.retiring || scope.pending is Some(_) {
    return false
  }
  if scope.depth > 0 {
    guard holder_effect_host_read_scope_current(scope) else { return false }
    scope.depth += 1
    return true
  }
  scope.depth = 1
  if !holder_effect_host_read_scope_current(scope) {
    scope.depth = 0
    return false
  }
  true
}

///|
fn leave_holder_effect_host_read_scope(
  scope : HolderEffectHostSetupScope,
) -> Bool {
  if scope.depth <= 0 {
    return false
  }
  let current = holder_effect_host_read_scope_current(scope)
  scope.depth -= 1
  current
}

///|
fn with_holder_effect_host_read_scope(
  scope : HolderEffectHostSetupScope,
  read : () -> Bool,
) -> Bool {
  guard enter_holder_effect_host_read_scope(scope) else { return false }
  let result = read()
  let current = leave_holder_effect_host_read_scope(scope)
  result && current
}

///|
/// Managed snapshot bounds are not a mapped allocation certificate or RSS cap.
fn retain_holder_effect_host_snapshot(
  scope : HolderEffectHostSetupScope,
  root : String,
  snapshot : Array[(String, String)],
) -> Bool {
  holder_effect_host_read_scope_current(scope) &&
  scope.depth == 1 &&
  root.length() <= 4096 &&
  snapshot.length() == 11 &&
  snapshot.all(entry => entry.0.length() <= 512 && entry.1.length() <= 512)
}

///|
/// Cleanup stops new reads without invoking the Store-backed verifier. A nested
/// caller must end its own frame; no physical failure is acknowledged here.
fn quiesce_holder_effect_host_setup_scope(
  scope : HolderEffectHostSetupScope,
) -> Bool {
  scope.retiring = true
  guard scope.depth >= 0 && scope.depth <= 1 else { return false }
  scope.depth = 0
  scope.preparation_binding = None
  scope.current_binding = None
  true
}

///|
/// Retry only the original physical failure. No fresh read or Store lookup.
fn prepare_holder_effect_host_scope_retirement(
  scope : HolderEffectHostSetupScope,
) -> Bool {
  scope.retiring = true
  if scope.depth > 0 {
    return false
  }
  if scope.depth == 0 && scope.pending is None {
    return true
  }
  quiesce_holder_effect_host_setup_scope(scope) &&
  retry_holder_effect_host_read_failure(scope)
}

///|
priv enum HolderEffectHostScopeRetirement {
  HostSetupReadyToDetach
  HostSetupScopePending(HolderEffectHostSetupScope)
}

///|
/// Prepare one caller scope for detachment. The pending value carries the same
/// Root/Reader failure and existing Site cleanup responsibility.
/// A caller must retain it, not translate it into a terminal CLI exit or ACK.
fn retire_holder_effect_host_scope(
  scope : HolderEffectHostSetupScope,
) -> HolderEffectHostScopeRetirement {
  guard prepare_holder_effect_host_scope_retirement(scope) else {
    if scope.cleanup is None {
      ignore(
        with_holder_effect_host_site_metadata(scope, () => {
          scope.cleanup = Some(@site.retain_site_cleanup(scope.site))
          true
        }),
      )
    }
    return HostSetupScopePending(scope)
  }
  // The caller still has to detach snapshot references and return the
  // original Site cleanup token. Managed values are not physical close ACKs.
  HostSetupReadyToDetach
}

///|
/// Move the same current verifier; ordinary input owns no Site reservation.
fn take_holder_effect_host_caller_reservation(
  scope : HolderEffectHostSetupScope,
) -> (@site.SiteOperation?, (() -> Bool)?) {
  let current = scope.current_binding
  scope.preparation_binding = None
  scope.current_binding = None
  (None, current)
}

///|
fn detach_holder_effect_host_setup(resources : HolderOutputResources) -> Bool {
  guard resources.effect_host_holding.val is None else { return true }
  let scope = match resources.effect_host_installation.val {
    Some(installed) => {
      guard retire_holder_effect_host_installation(installed) else {
        return false
      }
      Some(installed.scope)
    }
    None =>
      match resources.effect_host_setup.val {
        Some(scope) => {
          match retire_holder_effect_host_scope(scope) {
            HostSetupReadyToDetach => ()
            HostSetupScopePending(pending) => {
              resources.effect_host_setup.val = Some(pending)
              return false
            }
          }
          Some(scope)
        }
        None => None
      }
  }
  if scope is Some(original) {
    guard resources.effect_host_caller_operation is None &&
      resources.effect_host_caller_current is None else {
      return false
    }
    let (operation, current) = take_holder_effect_host_caller_reservation(
      original,
    )
    resources.effect_host_caller_operation = operation
    resources.effect_host_caller_current = current
    resources.effect_host_caller_ordinary = true
    resources.effect_host_cleanup.val = original.cleanup
    original.cleanup = None
  }
  // Production callbacks retain these cells, not a payload/snapshot copy.
  // Snapshot/read callbacks are detached; only the forwarded capacity/current
  // context remains until the separate upper caller frame ends.
  resources.effect_host_installation.val = None
  resources.effect_host_setup.val = None
  true
}

///|
priv enum HolderEffectHostSetupClose {
  HostSetupClosed
  HostSetupPending(HolderOutputResources)
}

///|
/// Exactly one close pass. A pending result owns the original resources and
/// opaque failure; it must be retained by a caller's cleanup boundary. The CLI
/// selects no mapped profile; ordinary managed values grant no Site capacity.
fn close_holder_effect_host_setup(
  resources : HolderOutputResources,
) -> HolderEffectHostSetupClose {
  guard detach_holder_effect_host_setup(resources) else {
    return HostSetupPending(resources)
  }
  // The detachment helper's locals have ended before any holding is returned.
  if resources.effect_host_holding.val is Some(holding) {
    guard @site.release_site_holding(holding) else {
      return HostSetupPending(resources)
    }
    resources.effect_host_holding.val = None
  }
  if resources.effect_host_cleanup.val is Some(cleanup) {
    guard @site.release_site_cleanup(cleanup) else {
      return HostSetupPending(resources)
    }
    resources.effect_host_cleanup.val = None
  }
  HostSetupClosed
}

///|
/// Install one original Store verifier. A refused lookup never revives.
fn install_holder_effect_host_store_current(
  scope : HolderEffectHostSetupScope,
  current : () -> Bool,
) -> Bool {
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
  holder_effect_host_read_scope_current(scope)
}

///|
fn retry_holder_effect_host_read_failure(
  scope : HolderEffectHostSetupScope,
) -> Bool {
  guard scope.pending is Some(failure) else { return true }
  if failure.retry_cleanup() is Err(_) {
    return false
  }
  scope.pending = None
  true
}
