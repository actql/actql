///|
test "imported Result retains an admitted producer row bound without consumer copies" {
  let checked : Array[CheckedProgram] = []
  ignore(
    local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      through_check=true,
      checked_results=checked,
      second_stage=true,
      host_limit=1000,
      generated_rows=Some("[{\"id\":1}]"),
      generated_proofs=[keyed_sourceview_claim()],
      generated_proof_stage=0,
      second_steps="[]",
      second_result_from="rows",
    ),
  )
  let program = checked[0]
  let producer = program.units[0].publication_rows[0]
  let consumer = program.units[1].publication_rows[0]
  assert_eq(@context.publication_row_limit_maximum(producer), 1L)
  assert_true(@context.publication_row_limit_program_count(producer) > 0)
  assert_eq(@context.publication_row_limit_maximum(consumer), 1L)
  assert_true(@context.publication_row_limit_program_count(consumer) > 0)
  assert_eq(@context.publication_row_limit_program_count(consumer), 2)
  for i in 0..<2 {
    let membership = @context.publication_row_limit_program_at(consumer, i).unwrap().membership
    assert_eq(@capacity.target_membership_consumer_visit(membership), 0)
    let (visit, claim, _) = @capacity.target_membership_coordinates(membership)
    assert_eq(visit, i + 1)
    assert_eq(claim, 0)
  }
  let closed = @context.publication_row_limit_owner(consumer)
  let work = @context.publication_closure_work(closed)
  let count = @context.publication_closure_count(closed) +
    @context.publication_row_candidate_count(closed)
  let owner = @context.publication_closure_owner(closed)
  assert_true(@context.close_program_publications(owner, work, count) is Ok(_))
  assert_true(
    @context.close_program_publications(owner, work - 1, count)
    is Err(@context.BudgetExceeded),
  )
  assert_true(
    @context.close_program_publications(owner, work, count - 1)
    is Err(@context.BudgetExceeded),
  )
}

///|
test "imported producer bounds tighten array aggregate items without consumer copies" {
  let checked : Array[CheckedProgram] = []
  ignore(
    local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      through_check=true,
      checked_results=checked,
      second_stage=true,
      host_limit=1000,
      generated_rows=Some("[{\"id\":1}]"),
      generated_proofs=[keyed_sourceview_claim()],
      generated_proof_stage=0,
      second_steps="[{\"assert_rows\":{\"unique_by\":[\"id\"]}},{\"group\":{\"by\":[\"id\"],\"aggregates\":{\"value\":{\"fn\":\"array_agg\",\"field\":\"value\",\"order_by\":[{\"id\":\"asc\"}],\"max_items\":20}}},\"as\":\"selected\"}]",
      second_result_from="selected",
      extra_step_budget=3,
    ),
  )
  let program = checked[0]
  assert_eq(unit_group_limit_count(program, 1), Some(1))
  let retained = unit_group_limit_at(program, 1, 0).unwrap()
  let selected = group_limit_selection(retained)
  assert_eq(@context.group_array_limit_guard(selected), Some(20L))
  assert_eq(@context.group_array_limit_maximum(selected), 1L)
  assert_true(@context.group_array_limit_candidate_count(selected) > 0)
  assert_true(group_limit_proof_count(retained) > 0)
}

///|
test "analytic arrays use producer tables without importing their proof into the consumer table" {
  let checked : Array[CheckedProgram] = []
  ignore(
    local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      through_check=true,
      checked_results=checked,
      second_stage=true,
      host_limit=1000,
      analytic_limit=Some(1000),
      generated_rows=Some("[{\"id\":1}]"),
      generated_proofs=[keyed_sourceview_claim()],
      generated_proof_stage=0,
      second_steps="[{\"assert_rows\":{\"unique_by\":[\"id\"]}},{\"analytic\":{\"partition_by\":[],\"order_by\":[{\"id\":\"asc\"}],\"frame\":{\"start\":\"unbounded_preceding\",\"end\":\"current_row\"},\"functions\":{\"items\":{\"fn\":\"array_agg\",\"field\":\"value\",\"max_items\":20}}}},{\"select\":[\"id\",{\"value\":\"items\"}],\"as\":\"selected\"}]",
      second_result_from="selected",
      extra_step_budget=4,
    ),
  )
  let retained = unit_analytic_limit_at(checked[0], 1, 0).unwrap()
  let writer = @encode.writer(100000, 10000, 100)
  @wire.emit_limit(analytic_limit_claim(retained), writer)
  let wire = @encode.finish(writer)
  assert_true(wire.contains("\"effective_max\":1,"))
  assert_true(
    wire.contains("\"author_guard_binding\":\"currently_non_binding\""),
  )
  assert_true(analytic_limit_proof_count(retained) > 0)
}

///|
test "unrelated imported producer proofs cannot bound a separate consumer values target" {
  let checked : Array[CheckedProgram] = []
  ignore(
    local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      through_check=true,
      checked_results=checked,
      second_stage=true,
      host_limit=1000,
      generated_rows=Some("[{\"id\":1}]"),
      generated_proofs=[keyed_sourceview_claim()],
      generated_proof_stage=0,
      second_steps="[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"value\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1,\"value\":2},{\"id\":2,\"value\":3}]},\"as\":\"selected\"}]",
      second_result_from="selected",
      extra_step_budget=2,
    ),
  )
  let consumer = checked[0].units[1].publication_rows[0]
  assert_eq(@context.publication_row_limit_maximum(consumer), 1000L)
  assert_eq(@context.publication_row_limit_program_count(consumer), 0)
}
