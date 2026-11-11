///|
/// The actual empty ModelTask registry still owns its entries and selector
/// containers. This recipe deliberately does not describe populated ModelTask
/// grammar, schemas, hashing, generation or data-handling construction.
pub fn empty_model_tasks_construction_extent(
  original : WireEnvironment,
) -> RegistryConstructionExtent? {
  if member_count(original, ModelTaskContracts) != 0 {
    return None
  }
  let retained = empty_model_tasks_retained_units()
  // Original budget, outer/body/contract limits, successful Result and typed
  // refusal alternatives. The WireEnvironment is borrowed, never copied.
  Some({
    record_headers: retained.record_headers + 7L,
    reference_slots: retained.reference_slots + 5L,
    scalar_words: retained.scalar_words + 15L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
pub fn empty_model_tasks_retained_extent(
  original : WireEnvironment,
) -> RegistryConstructionExtent? {
  if member_count(original, ModelTaskContracts) != 0 {
    return None
  }
  Some(wire_admission_units(empty_model_tasks_retained_units()))
}

///|
fn empty_model_tasks_retained_units() -> @shape.CollectionConstructionExtent {
  // ModelTasks(environment, entries, selectors; bytes/nodes/work and both
  // contract counters), original empty entries Array and original empty Map.
  @shape.collection_construction_extent({
    records: 1L,
    record_references: 3L,
    record_words: 5L,
    reference_arrays: 1L,
    reference_items: 0L,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 1L,
    map_entries: 0L,
  }).unwrap()
}
