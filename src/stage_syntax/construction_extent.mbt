///|
/// Preconstruction structural facts from the already admitted indexed source.
/// This is a bound on the stage envelope only, not semantic checking or a grant.
/// The indexed tree, temporary ObjectViews/name arrays, strings and diagnostic
/// paths need separate simultaneous owners. The caller funds this inspection.
pub(all) struct ProgramConstructionExtent {
  stage_records : Int
  import_tuple_bound : Int64
  export_tuples : Int
  name_index_entries : Int64
  retained_array_capacity_bound : Int64
  retained_map_capacity_bound : Int64
  inspection_work : Int
} derive(Eq, Debug)

///|
pub(all) struct ProgramConstructionExtent64 {
  stage_records : Int
  import_tuple_bound : Int64
  export_tuples : Int
  name_index_entries : Int64
  retained_array_capacity_bound : Int64
  retained_map_capacity_bound : Int64
  inspection_work : Int64
} derive(Eq, Debug)

///|
priv struct ConstructionExtentWork {
  mut remaining : Int64
  mut exhausted : Bool
}

///|
/// Cursor lookup is deliberately not open_object: no additional name Map is
/// built merely to determine the constructor's own Map envelope.
fn construction_field(
  cursor : @wire.Cursor,
  name : String,
  work : ConstructionExtentWork,
) -> @wire.Cursor? {
  guard @wire.object_length(cursor) is Some(count) else { return None }
  if count.to_int64() > work.remaining {
    work.exhausted = true
    return None
  }
  work.remaining -= count.to_int64()
  for index in 0..<count {
    guard @wire.field_at(cursor, index) is Some((key, value)) else {
      return None
    }
    if key == name {
      return Some(value)
    }
  }
  None
}

///|
/// Existing public Int interface over the same one-pass quantity observer.
/// The original Int maximum bounds spent work, so this conversion is exact.
/// Projection adds one narrow DATA record/Some, not another source scan.
pub fn program_construction_extent(
  root : @wire.Cursor,
  max_work : Int,
) -> ProgramConstructionExtent? {
  program_construction_extent64(root, max_work.to_int64()).map(value => {
    stage_records: value.stage_records,
    import_tuple_bound: value.import_tuple_bound,
    export_tuples: value.export_tuples,
    name_index_entries: value.name_index_entries,
    retained_array_capacity_bound: value.retained_array_capacity_bound,
    retained_map_capacity_bound: value.retained_map_capacity_bound,
    inspection_work: value.inspection_work.to_int(),
  })
}

///|
pub fn program_construction_extent64(
  root : @wire.Cursor,
  max_work : Int64,
) -> ProgramConstructionExtent64? {
  if max_work < 1 {
    return None
  }
  let work : ConstructionExtentWork = {
    remaining: max_work - 1,
    exhausted: false,
  }
  guard construction_field(root, "stages", work) is Some(stages) else {
    return None
  }
  guard construction_field(root, "results", work) is Some(exports) else {
    return None
  }
  guard @wire.array_length(stages) is Some(stage_count) else { return None }
  guard @wire.object_length(exports) is Some(export_count) else { return None }
  if stage_count.to_int64() > work.remaining {
    return None
  }
  work.remaining -= stage_count.to_int64()
  let mut imports = 0L
  let mut names = 0L
  for index in 0..<stage_count {
    guard @wire.element_at(stages, index) is Some(stage) else { return None }
    guard construction_field(stage, "inputs", work) is Some(inputs) else {
      return None
    }
    guard @wire.object_length(inputs) is Some(input_count) else { return None }
    // An admitted input declaration can contain at most result and receipt
    // imports. Malformed declarations remain the actual decoder's concern.
    if input_count.to_int64() > work.remaining {
      return None
    }
    work.remaining -= input_count.to_int64()
    imports += 2L * input_count.to_int64()
    guard construction_field(stage, "results", work) is Some(results) else {
      return None
    }
    guard @wire.object_length(results) is Some(result_count) else {
      return None
    }
    if result_count.to_int64() > work.remaining {
      return None
    }
    work.remaining -= result_count.to_int64()
    names += result_count.to_int64()
    for name in ["effects", "table_inputs"] {
      match construction_field(stage, name, work) {
        Some(value) => {
          guard @wire.object_length(value) is Some(count) else { return None }
          if count.to_int64() > work.remaining {
            return None
          }
          work.remaining -= count.to_int64()
          names += count.to_int64()
        }
        None => if work.exhausted { return None }
      }
    }
  }
  // Pinned grow-only arrays start at <=8 and double: capacity<=8+2n.
  // Four retained arrays per stage, plus Program stages/exports. Maps grow
  // below full occupancy: conservative capacity<=8+4n, with three per stage.
  let arrays = 2L + 4L * stage_count.to_int64()
  let array_items = stage_count.to_int64() +
    export_count.to_int64() +
    imports +
    names
  Some({
    stage_records: stage_count,
    import_tuple_bound: imports,
    export_tuples: export_count,
    name_index_entries: names,
    retained_array_capacity_bound: 8L * arrays + 2L * array_items,
    retained_map_capacity_bound: 24L * stage_count.to_int64() + 4L * names,
    inspection_work: max_work - work.remaining,
  })
}

///|
/// Retained shallow Program containers only. Strings (including normalized
/// identifiers), the indexed source and constructor scratch remain separate
/// owners. The common representation tariff performs byte conversion.
pub(all) struct ProgramContainerConstructionExtent {
  record_headers : Int64
  reference_slots : Int64
  scalar_words : Int64
  // The same original shallow records also coexist with constructor scratch.
  shallow_record_headers : Int64
  shallow_reference_slots : Int64
  shallow_scalar_words : Int64
} derive(Eq, Debug)

///|
/// The same envelope decoder owns these records, import variants, arrays and
/// name indexes. The input is structural DATA from its original bounded source
/// inspection, never execution permission or proof of physical allocation.
pub fn program_container_construction_extent(
  value : ProgramConstructionExtent,
) -> ProgramContainerConstructionExtent? {
  program_container_construction_extent_fields(
    value.stage_records,
    value.import_tuple_bound,
    value.export_tuples,
    value.name_index_entries,
    value.retained_array_capacity_bound,
    value.retained_map_capacity_bound,
    value.inspection_work.to_int64(),
  )
}

///|
pub fn program_container_construction_extent64(
  value : ProgramConstructionExtent64,
) -> ProgramContainerConstructionExtent? {
  program_container_construction_extent_fields(
    value.stage_records,
    value.import_tuple_bound,
    value.export_tuples,
    value.name_index_entries,
    value.retained_array_capacity_bound,
    value.retained_map_capacity_bound,
    value.inspection_work,
  )
}

///|
fn program_container_construction_extent_fields(
  stage_records : Int,
  import_tuple_bound : Int64,
  export_tuples : Int,
  name_index_entries : Int64,
  retained_array_capacity_bound : Int64,
  retained_map_capacity_bound : Int64,
  inspection_work : Int64,
) -> ProgramContainerConstructionExtent? {
  // The original indexed tree bounds every Stage, input and name by its
  // Int-sized node/field domain. Inspection work itself is exact Int64. Each input contributes at most two imports. These range checks
  // also make all following linear products provably fit signed Int64.
  let max_count = 2147483647L
  if stage_records < 0 ||
    export_tuples < 0 ||
    inspection_work < 0 ||
    import_tuple_bound < 0L ||
    import_tuple_bound > 2L * max_count ||
    name_index_entries < 0L ||
    name_index_entries > max_count {
    return None
  }
  let stages = stage_records.to_int64()
  let imports = import_tuple_bound
  let exports = export_tuples.to_int64()
  let names = name_index_entries
  let predecessors = Int64::max(0L, stages - 1L)
  let arrays = 2L + 4L * stages
  let items = stages + exports + imports + names
  let array_capacity = 8L * arrays + 2L * items
  let maps = 3L * stages
  let map_capacity = 8L * maps + 4L * names
  if retained_array_capacity_bound != array_capacity ||
    retained_map_capacity_bound != map_capacity {
    return None
  }
  // Program(1H5R); Stage(1H9R plus predecessor tag/ref); each noninitial
  // predecessor(1H1R1W); Stage Cursor(1H2R1W); import tuple and its payload
  // variant(2H4R1W); export tuple(1H3R). Initial is an inline scalar tag.
  let headers = 1L + 2L * stages + predecessors + 2L * imports + exports
  let refs = 5L + 11L * stages + 2L * predecessors + 4L * imports + 3L * exports
  let words = 2L * stages + imports
  // Array wrapper/backing:2H1R2W plus capacity refs. Map record/backing,
  // entries and tagged bucket/lookup controls:6H6R9W per map,4H5R7W per
  // entry, plus backing reference/scalar slots. All element bodies borrow
  // their original owner; no row, parameter value or source String is copied.
  Some({
    shallow_record_headers: headers,
    shallow_reference_slots: refs,
    shallow_scalar_words: words,
    record_headers: headers + 2L * arrays + 6L * maps + 4L * names,
    reference_slots: refs +
    arrays +
    array_capacity +
    6L * maps +
    map_capacity +
    5L * names,
    scalar_words: words + 2L * arrays + 9L * maps + map_capacity + 7L * names,
  })
}
