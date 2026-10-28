///|
/// Shallow retained container facts for an already admitted Program. This is
/// not a preparation grant or a recursive byte quote. Cursor trees, shared
/// strings, import variants and source-usage records remain separate owners.
pub(all) struct ProgramRepresentationExtent {
  program_records : Int64
  stage_records : Int64
  object_views : Int64
  array_owners : Int64
  array_backing_slots : Int64
  array_uninspected_slots : Int64
  map_owners : Int64
  map_backing_slots : Int64
  map_entries : Int64
  import_tuples : Int64
  export_tuples : Int64
  cursor_references : Int64
  inspection_work : Int
} derive(Eq, Debug)

///|
pub fn same_program_representation_owner(
  left : Program,
  right : Program,
) -> Bool {
  physical_equal(left, right)
}

///|
/// Charge the caller's bounded inspection before walking each stage. Capacities
/// include spare slots; those slots may retain opaque references and are never
/// treated as absent merely because the logical array length is smaller.
pub fn program_representation_extent(
  value : Program,
  max_work : Int,
) -> ProgramRepresentationExtent? {
  if max_work < 1 || value.stages.length() > max_work - 1 {
    return None
  }
  let mut slots = value.stages.capacity().to_int64() +
    value.exports.capacity().to_int64()
  let mut spare = (value.stages.capacity() - value.stages.length()).to_int64() +
    (value.exports.capacity() - value.exports.length()).to_int64()
  let mut maps = 0L
  let mut entries = 0L
  let mut imports = 0L
  for stage in value.stages {
    let (input_slots, input_entries) = @wire.object_view_map_geometry(
      stage.original_inputs,
    )
    slots += stage.original_input_names.capacity().to_int64() +
      stage.imports.capacity().to_int64() +
      stage.results.capacity().to_int64() +
      stage.table_inputs.capacity().to_int64() +
      stage.effects.capacity().to_int64()
    spare += (stage.original_input_names.capacity() -
      stage.original_input_names.length()).to_int64() +
      (stage.imports.capacity() - stage.imports.length()).to_int64() +
      (stage.results.capacity() - stage.results.length()).to_int64() +
      (stage.table_inputs.capacity() - stage.table_inputs.length()).to_int64() +
      (stage.effects.capacity() - stage.effects.length()).to_int64()
    maps += input_slots.to_int64() +
      stage.result_index.capacity().to_int64() +
      stage.table_input_index.capacity().to_int64() +
      stage.effect_index.capacity().to_int64()
    entries += input_entries.to_int64() +
      stage.result_index.length().to_int64() +
      stage.table_input_index.length().to_int64() +
      stage.effect_index.length().to_int64()
    imports += stage.imports.length().to_int64()
  }
  let stages = value.stages.length().to_int64()
  Some({
    program_records: 1L,
    stage_records: stages,
    object_views: stages,
    array_owners: 2L + 5L * stages,
    array_backing_slots: slots,
    array_uninspected_slots: spare,
    map_owners: 4L * stages,
    map_backing_slots: maps,
    map_entries: entries,
    import_tuples: imports,
    export_tuples: value.exports.length().to_int64(),
    cursor_references: 1L + 3L * stages,
    inspection_work: value.stages.length() + 1,
  })
}
