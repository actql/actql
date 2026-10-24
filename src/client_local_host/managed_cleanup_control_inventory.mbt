///|
/// One physical managed Local output's cleanup state. Result aliases share the
/// same original. Four weak entries, two records, two overlapping generations
/// of async/finally closure environments and the cached-wrapper/close captures.
/// Promise engine/backing implementation is opaque runtime support, not RSS.
/// Module WeakMap owners and this immutable tariff recipe are installation-owned.
let managed_cleanup_control_units : PreparationRepresentationUnits = {
  record_headers:10L,reference_slots:25L,scalar_words:1L,
  owned_utf16_units:0L,owned_wire_bytes:0L,
}

///|
let managed_cleanup_control_bytes : Int64 =
  preparation_representation_cost(managed_cleanup_control_units).unwrap()

///|
fn client_local_cleanup_retained_bytes() -> Int64 { managed_cleanup_control_bytes }
