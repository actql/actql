///|
test "program retained container extent keeps source dependencies separate" {
  let limits : Limits = {
    source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 40, },
    tree: {
      max_nodes: 1000,
      max_depth: 40,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
    max_stages: 10,
  }
  let program = parse(
    "{\"version\":\"actql/0.1\",\"id\":\"p\",\"stages\":[{\"id\":\"s\",\"inputs\":{},\"steps\":[],\"results\":{\"r\":{}}}],\"results\":{\"out\":{\"from\":{\"stage\":\"s\",\"result\":\"r\"}}}}",
    limits,
    format=Json,
  ).unwrap()
  assert_true(program_construction_extent(program.body, 1) is None)
  let construction = program_construction_extent(program.body, 100).unwrap()
  assert_eq(construction.stage_records, 1)
  assert_true(program_representation_extent(program, 1) is None)
  let extent = program_representation_extent(program, 2).unwrap()
  assert_eq(extent.stage_records, 1L)
  assert_eq(extent.array_owners, 6L)
  assert_eq(extent.map_owners, 3L)
  assert_eq(extent.map_entries, 1L)
  assert_eq(extent.export_tuples, 1L)
  assert_eq(extent.cursor_references, 2L)
  assert_true(same_program_representation_owner(program, program))
  assert_true(extent.array_backing_slots >= 3L)
  assert_true(
    construction.retained_array_capacity_bound >= extent.array_backing_slots,
  )
  assert_true(
    construction.retained_map_capacity_bound >= extent.map_backing_slots,
  )
}

///|
test "generic Program container owner preserves the independent one-stage vector" {
  let extent : ProgramConstructionExtent = {
    stage_records: 1,
    import_tuple_bound: 0L,
    export_tuples: 1,
    name_index_entries: 1L,
    retained_array_capacity_bound: 54L,
    retained_map_capacity_bound: 28L,
    inspection_work: 29,
  }
  assert_eq(
    program_container_construction_extent(extent),
    Some({
      record_headers: 38L,
      reference_slots: 130L,
      scalar_words: 76L,
      shallow_record_headers: 4L,
      shallow_reference_slots: 19L,
      shallow_scalar_words: 2L,
    }),
  )
  for
    bad in [
      { ..extent, stage_records: -1, },
      { ..extent, export_tuples: -1, },
      { ..extent, inspection_work: -1, },
      { ..extent, import_tuple_bound: -1L, },
      { ..extent, import_tuple_bound: 4294967295L, },
      { ..extent, name_index_entries: -1L, },
      { ..extent, name_index_entries: 2147483648L, },
      { ..extent, retained_array_capacity_bound: 53L, },
      { ..extent, retained_map_capacity_bound: 27L, },
    ] {
    assert_true(program_container_construction_extent(bad) is None)
  }
}

///|
test "generic Program construction covers multiple imports and public Results before decoding" {
  let original = parse_program_input(
    "{\"version\":\"actql/0.1\",\"id\":\"imports\",\"stages\":[{\"id\":\"a\",\"inputs\":{},\"steps\":[],\"results\":{\"r\":{},\"second\":{}},\"effects\":{\"e\":{}},\"table_inputs\":{\"t\":{}}},{\"id\":\"b\",\"inputs\":{\"rows\":{\"result\":{\"stage\":\"a\",\"result\":\"r\"}},\"receipt\":{\"receipt\":{\"stage\":\"a\",\"effect\":\"e\"}}},\"steps\":[],\"results\":{\"out\":{}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"b\",\"result\":\"out\"}},\"other\":{\"from\":{\"stage\":\"a\",\"result\":\"second\"}}}}",
    {
      source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 40, },
      tree: {
        max_nodes: 1000,
        max_depth: 40,
        max_string_bytes: 10000,
        max_total_string_bytes: 10000,
      },
      max_stages: 2,
    },
    format=Json,
  ).unwrap()
  let bounds = program_construction_extent(program_input_cursor(original), 1000).unwrap()
  assert_eq(bounds.stage_records, 2)
  assert_eq(bounds.import_tuple_bound, 4L)
  assert_eq(bounds.export_tuples, 2)
  assert_eq(bounds.name_index_entries, 5L)
  assert_eq(bounds.retained_array_capacity_bound, 106L)
  assert_eq(bounds.retained_map_capacity_bound, 68L)
  assert_eq(
    program_container_construction_extent(bounds),
    Some({
      record_headers: 92L,
      reference_slots: 296L,
      scalar_words: 185L,
      shallow_record_headers: 16L,
      shallow_reference_slots: 51L,
      shallow_scalar_words: 8L,
    }),
  )
  assert_true(
    program_construction_extent(
      program_input_cursor(original),
      bounds.inspection_work - 1,
    )
    is None,
  )
  let program = finish_program_input(original).unwrap()
  let actual = program_representation_extent(program, 3).unwrap()
  assert_eq(actual.stage_records, 2L)
  assert_eq(actual.import_tuples, 2L)
  assert_eq(actual.export_tuples, 2L)
  assert_eq(actual.map_entries, 5L)
  assert_true(
    actual.array_backing_slots <= bounds.retained_array_capacity_bound,
  )
  assert_true(actual.map_backing_slots <= bounds.retained_map_capacity_bound)
}

///|
test "generic Program constructor linear count limits stay representable" {
  let n = 2147483647L
  let extent : ProgramConstructionExtent = {
    stage_records: 2147483647,
    import_tuple_bound: 2L * n,
    export_tuples: 2147483647,
    name_index_entries: n,
    retained_array_capacity_bound: 16L + 42L * n,
    retained_map_capacity_bound: 28L * n,
    inspection_work: 2147483647,
  }
  let result = program_container_construction_extent(extent).unwrap()
  assert_eq(result.record_headers, 81604378590L)
  assert_eq(result.reference_slots, 259845521308L)
  assert_eq(result.scalar_words, 158913789882L)
}
