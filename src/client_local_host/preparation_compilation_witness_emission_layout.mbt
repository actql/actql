///|
/// capacity_witness::emit_cursor over a parsed Unit Values witness. HostSource
/// and constructed witnesses allocate less; all six candidate/standalone
/// scopes use this conservative dependency. Original indexed tree and text
/// remain borrowed. This does not admit or issue a witness.
fn compilation_small_witness_emitter_layout() -> PreparationRepresentationUnits? {
  // Per scope: view creates at most15 ValueView variants; three ObjectViews
  // (2 fields),3 open_object Ok and3 object_field_names Ok. Thirteen lookups
  // each allocate Map.get Some, map closure, Cursor(3 fields), returned Some.
  let records = closed_values_capacity_record_packet(
    15L + 3L + 3L + 3L + 4L * 13L,
    15L + 6L + 3L + 3L + 6L * 13L,
  )
  let maps = closed_values_program_maps(3L, 13L, true)
  // Three sorted key arrays total13 names; one detached ArrayValue projection
  // has at most14 children (actual dependencies empty). Its projected Cursors
  // are conservatively included by the common walk dependency below.
  let arrays = closed_values_program_arrays(4L, 27L, true)
  guard closed_values_walk_storage_layout(15, 9) is Some(walk) &&
    closed_values_sort_scratch_layout(9) is Some(sort) &&
    closed_values_sum_layouts([records, maps, arrays, walk, sort, sort, sort])
    is Some(one) else {
    return None
  }
  // Row limit2 candidates +byte limit1 +three standalone witness scopes.
  compilation_metadata_repeat_units(one, 6L)
}
