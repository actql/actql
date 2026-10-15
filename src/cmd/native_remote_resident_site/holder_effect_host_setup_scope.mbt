///|
/// Private reviewed representation bounds, never selected from a request,
/// Account permission or CLI numeric text. Production currently supplies None.
/// These are heap/control/backing charges; no stack/RSS/baseline claim is made.
priv struct HolderEffectHostSetupProfile {
  read_ceiling : Int
  // The reviewed current-read composition covers this caller ceiling. SQLite
  // also preserves the original Store limit; neither quantity is permission.
  catalog_read_ceiling : Int64
  // Exact original selected SQLite component heap, not a diagnostic/row bound.
  // This observation does not establish the simultaneous funding envelope.
  catalog_sqlite_heap_bytes : Int64
  // Independent physical diagnostic bound, not inferred from Account body size.
  diagnostic_ceiling : Int
  setup_retained_bytes : Int64
  current_retained_bytes : Int64
  // Minimum remainder of the initial reservation after snapshot partition.
  // Includes caller controls/current overlap; never a raw-record-only grant.
  caller_retained_bytes : Int64
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
  // Origin/capacity preparation only; never a Store/read authorization.
  mut preparation_binding : (() -> Bool)?
  // Production installs this only after entering the original read domain.
  mut current_binding : (() -> Bool)?
  mut read_domain : HolderEffectHostReadDomain?
  mut read_parent : HolderEffectHostReadParent?
  mut caller_operation : @site.SiteOperation?
  mut operation : @site.SiteOperation?
  mut holding : @site.SiteHolding?
  mut depth : Int
  mut pending : @bounded_files.NativeBoundedTextFailure?
  mut cleanup : @site.SiteCleanup?
  mut retiring : Bool
}

///|
/// No Store read belongs to this predicate. The exact admitted Site selection
/// and original Slot can establish only the scope in which domain preparation
/// is attempted; runtime/current validation still follows inside that domain.
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
fn holder_effect_host_setup_profile_valid(
  profile : HolderEffectHostSetupProfile,
) -> Bool {
  profile.diagnostic_ceiling > 0 &&
  profile.read_ceiling > 0 &&
  profile.read_ceiling <= 1000000 &&
  profile.catalog_read_ceiling > 0L &&
  profile.catalog_sqlite_heap_bytes >= 4096L &&
  profile.catalog_sqlite_heap_bytes <= 2147483647L &&
  profile.setup_retained_bytes > 0L &&
  profile.current_retained_bytes > 0L &&
  profile.caller_retained_bytes >= profile.current_retained_bytes &&
  profile.caller_retained_bytes < profile.setup_retained_bytes &&
  profile.execution_bytes > 0L &&
  profile.string_bytes > 0L &&
  profile.utf16_unit_bytes > 0L &&
  profile.array_bytes > 0L &&
  profile.array_slot_bytes > 0L &&
  profile.tuple_bytes > 0L &&
  profile.retained_controls_bytes > 0L
}

///|
/// Select a bound for the same Store's current read, before any I/O. The
/// SQLite Owner enforces this bound before copying and keeps its original
/// constructor limit. No row, Account permission or candidate selects it.
fn holder_effect_host_catalog_read_limit(
  profile : HolderEffectHostSetupProfile?,
  original_record_limit : Int64,
) -> Int64? {
  guard profile is Some(selected) &&
    holder_effect_host_setup_profile_valid(selected) &&
    original_record_limit > 0L else {
    return None
  }
  Some(
    if original_record_limit < selected.catalog_read_ceiling {
      original_record_limit
    } else {
      selected.catalog_read_ceiling
    },
  )
}

///|
fn reserve_holder_effect_host_setup_scope(
  site : @site.ExecutionSite,
  profile : HolderEffectHostSetupProfile?,
  original_catalog_record_limit : Int64,
) -> HolderEffectHostSetupScope? {
  guard profile is Some(selected) &&
    holder_effect_host_catalog_read_limit(
      profile, original_catalog_record_limit,
    )
    is Some(_) else {
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
    preparation_binding: None,
    current_binding: None,
    read_domain: None,
    read_parent: None,
    caller_operation: Some(operation),
    operation: Some(operation),
    holding: None,
    depth: 1,
    pending: None,
    cleanup: None,
    retiring: false,
  }
  // The caller must retain this scope before allocating binding callbacks.
  // An absent binding authorizes no read; a failed later current fence must
  // return through the same caller retirement, never drop this reservation.
  Some(scope)
}

///|
fn holder_effect_host_read_scope_bound(
  scope : HolderEffectHostSetupScope,
) -> Bool {
  !scope.retiring &&
  scope.pending is None &&
  scope.depth > 0 &&
  scope.operation is Some(operation) &&
  scope.caller_operation is Some(caller) &&
  physical_equal(operation, caller) &&
  @site.site_operation_available(operation)
}

///|
/// Before domain installation, only the same live reservation and immutable
/// origin selection are checked. Reentrant replacement/retirement is refusal,
/// not a reason to acquire another operation or read the runtime Store.
fn holder_effect_host_read_scope_prepared(
  scope : HolderEffectHostSetupScope,
) -> Bool {
  guard holder_effect_host_read_scope_bound(scope) &&
    scope.operation is Some(operation) &&
    scope.preparation_binding is Some(prepared) &&
    prepared() else {
    return false
  }
  holder_effect_host_read_scope_bound(scope) &&
  scope.operation is Some(actual_operation) &&
  physical_equal(actual_operation, operation) &&
  scope.preparation_binding is Some(actual) &&
  physical_equal(actual, prepared)
}

///|
fn holder_effect_host_read_scope_current(
  scope : HolderEffectHostSetupScope,
) -> Bool {
  guard holder_effect_host_read_scope_bound(scope) &&
    scope.current_binding is Some(current) &&
    scope.operation is Some(operation) else {
    return false
  }
  let domain = scope.read_domain
  if !current() {
    // A stale/unknown runtime cannot be looked up again by leave/nested read.
    // Only original cleanup proceeds; this is not a physical close ACK.
    scope.retiring = true
    return false
  }
  // Current callbacks may retire or replace an original handle reentrantly.
  // A missing domain after a real read was entered is never a model fallback.
  let valid = holder_effect_host_read_scope_bound(scope) &&
    scope.operation is Some(actual_operation) &&
    physical_equal(actual_operation, operation) &&
    scope.current_binding is Some(actual) &&
    physical_equal(actual, current) &&
    (match (domain, scope.read_domain) {
      (Some(before), Some(after)) =>
        physical_equal(before, after) &&
        holder_effect_host_read_domain_current(before)
      // Arithmetic lifecycle fixtures install no physical read callback.
      // Production only installs its guarded callback after domain entry.
      (None, None) => true
      _ => false
    })
  if !valid {
    scope.retiring = true
  }
  valid
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
  // The initial operation keeps its remainder and workspace through the
  // caller lifetime. Reuse that exact reservation, never acquire another one.
  guard scope.operation is None &&
    scope.caller_operation is Some(operation) &&
    @site.site_operation_available(operation) else {
    return false
  }
  scope.operation = Some(operation)
  scope.depth = 1
  if scope.read_domain is Some(read) &&
    !enter_holder_effect_host_read_domain(read) {
    scope.depth = 0
    scope.operation = None
    return false
  }
  if !holder_effect_host_read_scope_current(scope) {
    if scope.read_domain is Some(read) {
      ignore(leave_holder_effect_host_read_domain(read))
    }
    scope.depth = 0
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
  if scope.depth == 0 &&
    scope.read_domain is Some(read) &&
    !leave_holder_effect_host_read_domain(read) {
    return false
  }
  if scope.depth == 0 && scope.pending is None {
    guard scope.operation is Some(operation) &&
      scope.caller_operation is Some(caller) &&
      physical_equal(operation, caller) else {
      return false
    }
    // End this read's borrow. Its initial reservation is still owned by the
    // upper caller and cannot be returned while callbacks/frames can run.
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
    holder_effect_host_extent_add(bytes, scope.profile.caller_retained_bytes)
    is Some(partition) &&
    partition <= scope.profile.setup_retained_bytes &&
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
  if scope.read_domain is Some(read) &&
    !leave_holder_effect_host_read_domain(read) {
    return false
  }
  guard retry_holder_effect_host_read_failure(scope) &&
    close_holder_effect_host_read_domain(scope) &&
    close_holder_effect_host_read_parent(scope) else {
    return false
  }
  if scope.operation is Some(operation) {
    guard scope.caller_operation is Some(caller) &&
      physical_equal(operation, caller) else {
      return false
    }
    // Physical retirement ends the read borrow, not the upper caller's
    // control/workspace reservation. No second holding is issued.
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
/// Move the original reservation/current context; this creates no permission
/// or replacement operation. The old scope cannot retain a second alias.
fn take_holder_effect_host_caller_reservation(
  scope : HolderEffectHostSetupScope,
) -> (@site.SiteOperation?, (() -> Bool)?) {
  let operation = scope.caller_operation
  let current = scope.current_binding
  scope.caller_operation = None
  scope.preparation_binding = None
  scope.current_binding = None
  (operation, current)
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
    resources.effect_host_holding.val = original.holding
    resources.effect_host_cleanup.val = original.cleanup
    original.holding = None
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
/// still selects no numeric profile. This ACK returns snapshot holding only;
/// the caller remainder/workspace stays reserved beyond this function.
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
