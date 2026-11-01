///|
test "public narrow Program extent and explicit wide observer share original geometry and refusal" {
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
  let original = parse(
    "{\"version\":\"actql/0.1\",\"id\":\"p\",\"stages\":[{\"id\":\"s\",\"inputs\":{},\"steps\":[],\"results\":{\"r\":{}}}],\"results\":{\"out\":{\"from\":{\"stage\":\"s\",\"result\":\"r\"}}}}",
    limits,
    format=Json,
  ).unwrap()
  assert_true(program_construction_extent(original.body, 1) is None)
  assert_true(program_construction_extent64(original.body, 1L) is None)
  let narrow = program_construction_extent(original.body, 100).unwrap()
  let wide = program_construction_extent64(original.body, 2147483650L).unwrap()
  // One Stage now retains its original empty input table/name Array too.
  // No imports, one root export and one stage-result name.
  // Arrays 2+5=7 with capacity8*7+2*3=62; maps4 with8*4+4=36.
  assert_eq(narrow.stage_records, 1)
  assert_eq(narrow.import_tuple_bound, 0L)
  assert_eq(narrow.export_tuples, 1)
  assert_eq(narrow.name_index_entries, 1L)
  assert_eq(narrow.retained_array_capacity_bound, 62L)
  assert_eq(narrow.retained_map_capacity_bound, 36L)
  assert_eq(wide.stage_records, narrow.stage_records)
  assert_eq(wide.import_tuple_bound, narrow.import_tuple_bound)
  assert_eq(wide.export_tuples, narrow.export_tuples)
  assert_eq(wide.name_index_entries, narrow.name_index_entries)
  assert_eq(
    wide.retained_array_capacity_bound,
    narrow.retained_array_capacity_bound,
  )
  assert_eq(
    wide.retained_map_capacity_bound,
    narrow.retained_map_capacity_bound,
  )
  assert_eq(wide.inspection_work, narrow.inspection_work.to_int64())
  assert_eq(
    program_container_construction_extent(narrow),
    program_container_construction_extent64(wide),
  )
  // Wide work is DATA independent of the same checked container geometry.
  let large = { ..wide, inspection_work: 2147483650L, }
  assert_eq(
    program_container_construction_extent64(large),
    Some({
      record_headers: 32L,
      reference_slots: 146L,
      scalar_words: 47L,
      shallow_record_headers: 7L,
      shallow_reference_slots: 28L,
      shallow_scalar_words: 4L,
    }),
  )
  assert_true(
    program_container_construction_extent64({ ..wide, inspection_work: -1L, })
    is None,
  )
  assert_true(
    program_container_construction_extent64({
      ..wide,
      retained_map_capacity_bound: 35L,
    })
    is None,
  )
}
