///|
/// One physical managed Local output's cleanup state. Result aliases share the
/// same original. Four weak entries, two records, two overlapping generations
/// of async/finally closure environments and the cached-wrapper/close captures.
/// Promise engine/backing implementation is opaque runtime support, not RSS.
/// Module WeakMap owners and this immutable tariff recipe are installation-owned.
let managed_cleanup_control_units : @execution.PreparationRepresentationUnits = {
  // Completed-scratch continuation adds two original method closures, one
  // availability thunk, and the helper/caller async contexts (5H,10R), plus the SAME retained result owner (1R).
  // Three progress words, one same-Run flight latch, and the Model cleanup's
  // continuation-selection/sticky-failure words add6W. This is one fixed
  // original cleanup inventory, not a per-wrapper fee or new allowance.
  record_headers: 10L + 5L,
  reference_slots: 25L + 11L,
  scalar_words: 1L + 6L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
let managed_cleanup_control_bytes : Int64 = @execution.preparation_representation_cost(
  managed_cleanup_control_units,
).unwrap()

///|
fn client_local_cleanup_retained_bytes() -> Int64 {
  managed_cleanup_control_bytes
}
