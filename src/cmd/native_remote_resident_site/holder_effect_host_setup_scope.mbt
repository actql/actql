///|
/// Private reviewed representation bounds, never selected from a request,
/// Account permission or CLI numeric text. Production currently supplies None.
/// These are heap/control/backing charges; no stack/RSS/baseline claim is made.
priv struct HolderEffectHostSetupProfile {
  read_ceiling : Int
  setup_retained_bytes : Int64
  current_retained_bytes : Int64
  execution_bytes : Int64
  string_bytes : Int64
  utf16_unit_bytes : Int64
  array_bytes : Int64
  array_slot_bytes : Int64
  tuple_bytes : Int64
  retained_controls_bytes : Int64
}

///|
/// References the existing Site operation/holding Owners. This private caller
/// has no issuer, persistence, execution state or authority of its own.
priv struct HolderEffectHostSetupScope {
  site : @site.ExecutionSite
  profile : HolderEffectHostSetupProfile
  current_binding : () -> Bool
  mut operation : @site.SiteOperation?
  mut holding : @site.SiteHolding?
  mut depth : Int
  mut pending : @bounded_files.NativeBoundedTextFailure?
  mut cleanup : @site.SiteCleanup?
  mut retiring : Bool
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
    current_site() &&
    @site.site_key(site) == expected_key &&
    @site.site_binding_current(site, expected_generation, expected_runtime) &&
    current_runtime()
  }
}

///|
fn holder_effect_host_setup_profile_valid(
  profile : HolderEffectHostSetupProfile,
) -> Bool {
  profile.read_ceiling > 0 &&
  profile.read_ceiling <= 1000000 &&
  profile.setup_retained_bytes > 0L &&
  profile.current_retained_bytes > 0L &&
  profile.execution_bytes > 0L &&
  profile.string_bytes > 0L &&
  profile.utf16_unit_bytes > 0L &&
  profile.array_bytes > 0L &&
  profile.array_slot_bytes > 0L &&
  profile.tuple_bytes > 0L &&
  profile.retained_controls_bytes > 0L
}

///|
fn begin_holder_effect_host_setup_scope(
  site : @site.ExecutionSite,
  profile : HolderEffectHostSetupProfile?,
  current_binding : () -> Bool,
) -> HolderEffectHostSetupScope? {
  guard profile is Some(selected) &&
    holder_effect_host_setup_profile_valid(selected) else {
    return None
  }
  // Reserve before the fallible physical binding checks. Selection of bytes
  // proves neither Account permission nor that the Host baseline is installed.
  guard @site.start_site_operation(
      site,
      selected.setup_retained_bytes,
      selected.execution_bytes,
    )
    is Some(operation) else {
    return None
  }
  let scope : HolderEffectHostSetupScope = {
    site,
    profile: selected,
    current_binding,
    operation: Some(operation),
    holding: None,
    depth: 1,
    pending: None,
    cleanup: None,
    retiring: false,
  }
  if !current_binding() {
    ignore(@site.settle_site_operation(operation))
    return None
  }
  Some(scope)
}

///|
fn holder_effect_host_read_scope_current(
  scope : HolderEffectHostSetupScope,
) -> Bool {
  !scope.retiring &&
  scope.pending is None &&
  scope.depth > 0 &&
  scope.operation is Some(operation) &&
  @site.site_operation_available(operation) &&
  (scope.current_binding)()
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
      scope.cleanup = Some(@site.retain_site_cleanup(scope.site))
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
  guard scope.operation is None &&
    @site.start_site_operation(
      scope.site,
      scope.profile.current_retained_bytes,
      scope.profile.execution_bytes,
    )
    is Some(operation) else {
    return false
  }
  scope.operation = Some(operation)
  scope.depth = 1
  if !(scope.current_binding)() {
    scope.depth = 0
    ignore(@site.settle_site_operation(operation))
    scope.operation = None
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
  if scope.depth == 0 && scope.pending is None {
    guard scope.operation is Some(operation) else { return false }
    if !@site.settle_site_operation(operation) {
      return false
    }
    scope.operation = None
  }
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
fn holder_effect_host_extent_add(left : Int64, right : Int64) -> Int64? {
  if left < 0L || right < 0L || right > 9223372036854775807L - left {
    None
  } else {
    Some(left + right)
  }
}

///|
fn holder_effect_host_extent_product(left : Int64, right : Int64) -> Int64? {
  if left < 0L ||
    right < 0L ||
    (left != 0L && right > 9223372036854775807L / left) {
    None
  } else {
    Some(left * right)
  }
}

///|
/// The loader uses names.map: pinned Array.map allocates its result at exactly
/// names.length(), not a growing list. Occurrence charging is conservative for
/// shared immutable Strings. No Account parser/temporary buffer is held here.
fn holder_effect_host_snapshot_extent(
  profile : HolderEffectHostSetupProfile,
  root : String,
  snapshot : Array[(String, String)],
  control_text_bytes? : Int64 = 0L,
) -> Int64? {
  guard holder_effect_host_extent_add(
      profile.retained_controls_bytes,
      control_text_bytes,
    )
    is Some(initial) else {
    return None
  }
  let mut total = initial
  for fixed in [profile.array_bytes, profile.string_bytes] {
    guard holder_effect_host_extent_add(total, fixed) is Some(value) else {
      return None
    }
    total = value
  }
  guard holder_effect_host_extent_product(
      profile.utf16_unit_bytes,
      root.length().to_int64(),
    )
    is Some(root_units) &&
    holder_effect_host_extent_add(total, root_units) is Some(root_total) else {
    return None
  }
  total = root_total
  for entry in snapshot {
    guard holder_effect_host_extent_add(total, profile.array_slot_bytes)
      is Some(slot_total) &&
      holder_effect_host_extent_add(slot_total, profile.tuple_bytes)
      is Some(tuple_total) else {
      return None
    }
    total = tuple_total
    for text in [entry.0, entry.1] {
      guard holder_effect_host_extent_product(
          profile.utf16_unit_bytes,
          text.length().to_int64(),
        )
        is Some(units) &&
        holder_effect_host_extent_add(profile.string_bytes, units)
        is Some(string_total) &&
        holder_effect_host_extent_add(total, string_total) is Some(value) else {
        return None
      }
      total = value
    }
  }
  Some(total)
}

///|
fn retain_holder_effect_host_snapshot(
  scope : HolderEffectHostSetupScope,
  root : String,
  snapshot : Array[(String, String)],
  control_text_bytes? : Int64 = 0L,
) -> Bool {
  guard holder_effect_host_read_scope_current(scope) &&
    scope.depth == 1 &&
    scope.holding is None &&
    scope.operation is Some(operation) &&
    holder_effect_host_snapshot_extent(
      scope.profile,
      root,
      snapshot,
      control_text_bytes~,
    )
    is Some(bytes) &&
    @site.retain_site_operation_holding(operation, bytes) is Some(holding) else {
    return false
  }
  scope.holding = Some(holding)
  true
}

///|
/// The caller first drops its payload/closures. This path only retries original
/// physical cleanup. Unknown remains with the same opaque failure and Site
/// cleanup token; this one pass neither polls nor releases the holding.
fn prepare_holder_effect_host_scope_retirement(
  scope : HolderEffectHostSetupScope,
) -> Bool {
  scope.retiring = true
  if scope.depth > 0 {
    return false
  }
  if scope.pending is Some(failure) {
    guard failure.retry_cleanup() is Ok(_) else { return false }
    scope.pending = None
  }
  if scope.operation is Some(operation) {
    guard @site.settle_site_operation(operation) else { return false }
    scope.operation = None
  }
  true
}

///|
priv enum HolderEffectHostScopeRetirement {
  HostSetupReadyToDetach
  HostSetupScopePending(HolderEffectHostSetupScope)
}

///|
/// Prepare one caller scope for detachment. The pending value carries the same
/// Root/Reader, operation, holding and existing Site cleanup responsibility.
/// A caller must retain it, not translate it into a terminal CLI exit or ACK.
fn retire_holder_effect_host_scope(
  scope : HolderEffectHostSetupScope,
) -> HolderEffectHostScopeRetirement {
  guard prepare_holder_effect_host_scope_retirement(scope) else {
    if scope.cleanup is None {
      scope.cleanup = Some(@site.retain_site_cleanup(scope.site))
    }
    return HostSetupScopePending(scope)
  }
  // This is not close/holding completion. The caller still has to detach all
  // snapshot references and return the original holding/cleanup tokens.
  HostSetupReadyToDetach
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
          guard retire_holder_effect_host_scope(scope) is HostSetupReadyToDetach else {
            return false
          }
          Some(scope)
        }
        None => None
      }
  }
  if scope is Some(original) {
    resources.effect_host_holding.val = original.holding
    resources.effect_host_cleanup.val = original.cleanup
    original.holding = None
    original.cleanup = None
  }
  // Production callbacks retain these cells, not a payload/snapshot copy.
  // No snapshot/current closure survives this helper's actual local scope.
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
/// opaque failure; the holder's cleanup boundary retains that same custody.
/// This receiver does not install a funded production setup profile.
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
