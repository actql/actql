///|
test "equal aggregate identities do not authorize mixing separately checked owners" {
  let programs : Array[CheckedProgram] = []
  for _ in 0..<2 {
    let _ = local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      second_stage=true,
      through_check=true,
      checked_results=programs,
      second_steps="[{\"group\":{\"by\":[\"id\"],\"aggregates\":{\"value\":{\"fn\":\"array_agg\",\"field\":\"value\",\"order_by\":[{\"id\":\"asc\"}],\"max_items\":2}}},\"as\":\"selected\"}]",
      second_result_from="selected",
      extra_step_budget=2,
    )
  }
  let first = programs[0].units[1]
  let second = programs[1].units[1]
  assert_eq(first.definition_cid, second.definition_cid)
  assert_false(physical_equal(first.pipeline, second.pipeline))
  let left = unit_group_aggregate_source_at(programs[0], 1, 0, 0).unwrap()
  let right = unit_group_aggregate_source_at(programs[1], 1, 0, 0).unwrap()
  assert_eq(
    group_aggregate_subject(left, 10000),
    group_aggregate_subject(right, 10000),
  )
  assert_false(physical_equal(left.call, right.call))
  assert_true(unit_group_aggregate_source(first, second.pipeline, 0, 0) is None)
  assert_true(unit_group_aggregate_source(second, first.pipeline, 0, 0) is None)
}

///|
test "formal array group scopes bind Unit, call and measurement without copied owners" {
  let checked : Array[CheckedProgram] = []
  let _ = local_construction_fixture(
    { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
    second_stage=true,
    through_check=true,
    checked_results=checked,
    second_steps="[{\"group\":{\"by\":[\"id\"],\"aggregates\":{\"value\":{\"fn\":\"array_agg\",\"field\":\"value\",\"order_by\":[{\"id\":\"asc\"}],\"max_items\":2},\"a~/b\":{\"fn\":\"array_agg\",\"field\":\"value\",\"order_by\":[{\"id\":\"asc\"}],\"max_items\":3}}},\"as\":\"selected\"}]",
    second_result_from="selected",
    extra_step_budget=2,
  )
  let program = checked[0]
  let unit = program.units[1]
  let sources = [
    unit_group_aggregate_source_at(program, 1, 0, 0).unwrap(),
    unit_group_aggregate_source_at(program, 1, 0, 1).unwrap(),
  ]
  for index in 0..<2 {
    let source = sources[index]
    let name = if index == 0 { "a~/b" } else { "value" }
    let token = if index == 0 { "a~0~1b" } else { "value" }
    assert_eq(@relation.aggregate_name(source.call), name)
    assert_true(physical_equal(source.operation.pipeline, unit.pipeline))
    assert_eq(source.operation.unit_definition_cid, unit.definition_cid)
    assert_eq(
      group_aggregate_subject(source, 10000),
      "unit:" +
      unit.definition_cid +
      "#/steps/0/group/aggregates/" +
      token +
      "/items",
    )
    let work = 4 * name.length() + unit.definition_cid.length() + 64
    assert_eq(
      group_aggregate_subject(source, work),
      group_aggregate_subject(source, 10000),
    )
    for cap in [-1, work - 1] {
      try group_aggregate_subject(source, cap) catch {
        BudgetExceeded => ()
        error => raise error
      } noraise {
        _ => fail("subject exceeded its preparation budget")
      }
    }
  }
  assert_true(
    unit_group_aggregate_source(unit, program.units[0].pipeline, 0, 0) is None,
  )
  assert_true(unit_group_aggregate_source_at(program, 0, 0, 0) is None)
  for invalid in [-1, 2, 2147483647] {
    assert_true(unit_group_aggregate_source_at(program, invalid, 0, 0) is None)
    assert_true(unit_group_aggregate_source_at(program, 1, invalid, 0) is None)
    assert_true(unit_group_aggregate_source_at(program, 1, 0, invalid) is None)
  }
  let closure = @context.stage_requirement_operations(requirements(program))
  let mut limits = 0
  for i in 0..<@context.operation_closure_count(closure) {
    guard @context.operation_closure_at(closure, i)
      is Some(ExecutionCheck(GroupExecution(check))) &&
      check.rule is EnforceArrayItems(limit) else {
      continue
    }
    assert_true(physical_equal(check.site.pipeline, unit.pipeline))
    assert_true(
      sources.any(source => {
        physical_equal(source.call, @context.group_array_limit_call(limit))
      }),
    )
    assert_eq(
      @context.group_array_limit_guard(limit),
      Some(
        if @relation.aggregate_name(@context.group_array_limit_call(limit)) ==
          "a~/b" {
          3L
        } else {
          2L
        },
      ),
    )
    limits += 1
  }
  assert_eq(limits, 2)
}
