///|
pub fn client_check_environment_wrapper_construction_extent(
  scratch : Bool,
) -> @environment.RegistryConstructionExtent {
  // CheckEnvironment8R1W, ExpressionProfiles2W, PureOperationProfiles5W,
  // retained ModelTasks Some1R1W and returned checker Some1R1W. The copied
  // empty request-policy Array belongs to this checker, not its wire owner.
  // Construction additionally owns the original default Array and sequential
  // Result/Option alternatives while the copy and wrapper are constructed.
  let arrays = if scratch { 2L } else { 1L }
  let extra = if scratch { 4L } else { 0L }
  let value = @shape.collection_construction_extent({
    records: 5L + extra,
    record_references: 10L + extra,
    record_words: 10L + extra,
    reference_arrays: arrays,
    reference_items: 0L,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
  {
    record_headers: value.record_headers,
    reference_slots: value.reference_slots,
    scalar_words: value.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}
