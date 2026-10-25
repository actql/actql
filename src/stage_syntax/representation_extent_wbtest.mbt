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
