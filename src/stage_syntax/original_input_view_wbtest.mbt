///|
fn retained_stage_input_fixture() -> Program {
  parse(
    "{\"version\":\"actql/0.1\",\"id\":\"p\",\"stages\":[{\"id\":\"s\",\"inputs\":{\"b\":\"local-b\",\"a\":\"local-a\"},\"steps\":[],\"results\":{\"r\":{}}}],\"results\":{\"out\":{\"from\":{\"stage\":\"s\",\"result\":\"r\"}}}}",
    {
      source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 40, },
      tree: {
        max_nodes: 1000,
        max_depth: 40,
        max_string_bytes: 10000,
        max_total_string_bytes: 10000,
      },
      max_stages: 10,
    },
    format=Json,
  ).unwrap()
}

///|
test "original Stage input declarations retain one view ordered names and exact steps Source" {
  let program = retained_stage_input_fixture()
  let stage = program.stages[0]
  let view = stage.original_inputs
  let names = stage.original_input_names
  let geometry = @wire.object_view_map_geometry(view)
  for _ in 0..<3 {
    assert_eq(stage_input_declaration_count(stage), 2)
    assert_eq(stage_input_declaration_name_at(stage, 0), Some("b"))
    assert_eq(stage_input_declaration_name_at(stage, 1), Some("a"))
    assert_true(stage_input_declaration_name_at(stage, 2) is None)
    assert_eq(
      @wire.text(stage_input_declaration(stage, "b").unwrap()),
      Ok("local-b"),
    )
    assert_true(stage_input_declaration(stage, "foreign") is None)
    assert_true(physical_equal(stage.original_inputs, view))
    assert_true(physical_equal(stage.original_input_names, names))
    assert_true(physical_equal(stage_steps_source(stage), stage.original_steps))
    assert_eq(@wire.object_view_map_geometry(view), geometry)
  }
  assert_eq(@wire.array_length(stage_steps_source(stage)), Some(0))
}

///|
test "original retained declaration table is included by constructor and actual buffer inventories" {
  let program = retained_stage_input_fixture()
  let compatibility = program_construction_extent64(program.body, 1000L).unwrap()
  // The compatibility API permits two imports per declaration; the actual
  // constructor inventory sees these two original Local strings, no imports.
  assert_eq(compatibility.import_tuple_bound, 4L)
  assert_eq(compatibility.retained_array_capacity_bound, 74L)
  let original = program_constructor_inventory(program.body, 10000L).unwrap().retained
  assert_eq(original.name_index_entries, 3L)
  assert_eq(original.retained_array_capacity_bound, 66L)
  assert_eq(original.retained_map_capacity_bound, 44L)
  let held = program_container_construction_extent64(original).unwrap()
  // Independent one-Stage vector: shallow7H28R4W; seven Arrays14H73R14W;
  // four original Maps/three entries17H67R39W from the shared owner.
  assert_eq(
    (held.record_headers, held.reference_slots, held.scalar_words),
    (38L, 168L, 57L),
  )
  let actual = program_representation_extent(program, 2).unwrap()
  assert_eq(actual.array_owners, 7L)
  assert_eq(actual.map_owners, 4L)
  assert_eq(actual.map_entries, 3L)
  assert_eq(actual.object_views, 1L)
  assert_eq(actual.cursor_references, 4L)
  assert_true(
    actual.array_backing_slots <= original.retained_array_capacity_bound,
  )
  assert_true(actual.map_backing_slots <= original.retained_map_capacity_bound)
}

///|
test "structural control quotation consumes the same original container holder" {
  let program = retained_stage_input_fixture()
  let inventory = program_constructor_inventory(program.body, 10000L).unwrap()
  let quote = program_constructor_container_extent(inventory).unwrap()
  assert_true(physical_equal(quote.original, inventory))
  let retained = quote.retained
  let first = program_constructor_control_extent(quote).unwrap()
  let second = program_constructor_control_extent(quote).unwrap()
  assert_eq(first, second)
  assert_true(physical_equal(quote.retained, retained))
  assert_true(physical_equal(quote.original, inventory))
}
