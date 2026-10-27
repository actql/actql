///|
fn capacity_construction_program() -> @syntax.Program {
  @syntax.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"p\",\"stages\":[{\"id\":\"a\",\"inputs\":{},\"steps\":[{}],\"results\":{\"r\":{}}},{\"id\":\"b\",\"inputs\":{},\"steps\":[{}],\"results\":{\"r\":{}}}],\"results\":{\"r\":{\"from\":{\"stage\":\"b\",\"result\":\"r\"}}}}",
    {
      source: { max_input_bytes: 1000, max_nodes: 100, max_depth: 20, },
      tree: {
        max_nodes: 100,
        max_depth: 20,
        max_string_bytes: 1000,
        max_total_string_bytes: 1000,
      },
      max_stages: 2,
    },
    format=Json,
  ).unwrap()
}

///|
test "capacity binding constructor preserves independent empty graph and two Stage vector" {
  let program = capacity_construction_program()
  let inventory = capacity_input_construction_inventory(program, []).unwrap()
  assert_eq(inventory.records, 49L)
  assert_eq(inventory.record_references, 57L)
  assert_eq(inventory.record_words, 72L)
  assert_eq(inventory.reference_arrays, 20L)
  assert_eq(inventory.reference_items, 4L)
  assert_eq(inventory.scalar_arrays, 8L)
  assert_eq(inventory.maps, 5L)
  assert_eq(inventory.map_entries, 2L)
  assert_eq(
    @shape.collection_construction_extent(inventory),
    Some({ record_headers: 176L, reference_slots: 449L, scalar_words: 355L, }),
  )
  let (result, work) = observe_capacity_input_binding(program, [], 1000)
  assert_eq(work, 12)
  let original = result.unwrap()
  assert_eq(original.materials.length(), 2)
  assert_eq(original.work, work)
  let (failed, spent) = observe_capacity_input_binding(program, [], 11)
  assert_true(failed is Err(BudgetExceeded))
  assert_eq(spent, 11)
  let (early, untouched) = observe_capacity_input_binding(program, [], 1)
  assert_true(early is Err(BudgetExceeded))
  assert_eq(untouched, 0)
  assert_eq(observe_capacity_input_binding(program, [], -1).1, 0)
}

///|
test "capacity binding counts each retained consumer but only one transient limit Map" {
  let program = capacity_construction_program()
  let sources = sequence_limit_sources()
  let mixed = @wire.program_claim_mixed(@host.source_claims(sources)).unwrap()
  let limit = @wire.mixed_limit_at(mixed, 1).unwrap()
  let entries : Array[StageCapacityInput] = [
    { stage: "a", sources, uses: [Join(step=0, output=limit)], },
    {
      stage: "b",
      sources,
      uses: [Join(step=0, output=limit), Join(step=0, output=limit)],
    },
  ]
  let quoted = capacity_input_construction_inventory(program, entries).unwrap()
  assert_eq(quoted.maps, 6L)
  assert_eq(quoted.map_entries, 4L + @wire.mixed_limit_count(mixed).to_int64())
  assert_eq(quoted.reference_items, 7L)
  let (result, charged) = observe_capacity_input_binding(
    program, entries, 10000,
  )
  let bound = result.unwrap()
  assert_eq(bound.materials[0].consumers.length(), 1)
  assert_eq(bound.materials[1].consumers.length(), 2)
  assert_eq(charged, bound.work)
  let foreign = sequence_limit_sources()
  let equal_limit = @wire.mixed_limit_at(
    @wire.program_claim_mixed(@host.source_claims(foreign)).unwrap(),
    1,
  ).unwrap()
  let (failed, spent) = observe_capacity_input_binding(
    program,
    [{ stage: "a", sources, uses: [Join(step=0, output=equal_limit)], }],
    10000,
  )
  assert_true(failed is Err(ForeignLimit(0, 0)))
  assert_true(spent > 0 && spent < 10000)
}
