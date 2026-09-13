///|
test "formal window grouping retains boundary roles and its distinct execution operation" {
  for
    aggregates in [
      "{}", "{\"value\":{\"fn\":\"count\"}}", "{\"value\":{\"fn\":\"min\",\"field\":\"id\"}}",
    ] {
    let programs : Array[CheckedProgram] = []
    let _ = local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      through_check=true,
      checked_results=programs,
      second_stage=true,
      tea=true,
      second_steps="[{\"row_window\":{\"time\":\"id\",\"kind\":\"sliding\",\"size\":10,\"step\":3}},{\"window_group\":{\"by\":[\"id\"" +
        (if aggregates == "{}" { ",\"value\"" } else { "" }) +
        ",\"window_start\",\"window_end\",\"window_start\"],\"aggregates\":" +
        aggregates +
        "},\"as\":\"selected\"}]",
      second_result_from="selected",
      extra_step_budget=2,
    )
    let p = programs[0]
    let pipeline = unit_pipeline(p, 1).unwrap()
    guard @pipeline.step_at(pipeline, 1).unwrap().operation
      is @pipeline.WindowGroup(op) else {
      fail("window grouping lost its operation kind")
    }
    let group = @relation.group(op).unwrap()
    if @relation.aggregate_at(group, 0) is Some(call) {
      assert_eq(
        @relation.aggregate_result(call).nullable,
        aggregates.contains("\"min\""),
      )
    }
    let keys = @relation.group_keys(group)
    assert_eq(keys.length(), if aggregates == "{}" { 4 } else { 3 })
    assert_eq(keys[0].field, Unqualified("window_start"))
    assert_eq(keys[1].field, Unqualified("window_end"))
    assert_eq(keys[2].field, Unqualified("id"))
    assert_eq(
      @pipeline.window_fields(
        @pipeline.window_evidence_at(pipeline, Step(1)).unwrap(),
      ),
      (Unqualified("window_start"), Unqualified("window_end")),
    )
    let closure = @context.stage_requirement_operations(requirements(p))
    let mut partition = 0
    let mut calls = 0
    for i in 0..<@context.operation_closure_count(closure) {
      guard @context.operation_closure_at(closure, i)
        is Some(ExecutionCheck(GroupExecution(check))) &&
        check.site.stage == 1 &&
        check.site.step == 1 else {
        continue
      }
      assert_true(physical_equal(check.group, group))
      assert_true(physical_equal(check.operation, op))
      assert_true(check.step.operation is @pipeline.WindowGroup(_))
      assert_eq(check.input, @pipeline.Step(0))
      match check.rule {
        PartitionGroups => partition += 1
        EvaluateAggregate(_) => calls += 1
        ValidateResultContract(_) => ()
        _ => fail("unexpected window-group rule")
      }
    }
    assert_eq(partition, 1)
    assert_eq(calls, if aggregates == "{}" { 0 } else { 1 })
    assert_eq(unit_window_limit_count(p, 1), Some(1))
    assert_eq(unit_group_limit_count(p, 1), Some(0))
    let owner = @context.stage_requirement_owner(requirements(p))
    let (work, count) = @context.stage_requirement_usage(requirements(p))
    let limits : @context.StageRequirementLimits = {
      max_work: work,
      max_requirements: count,
      max_local_inputs: 10,
    }
    assert_true(@context.close_stage_requirements(owner, limits) is Ok(_))
    assert_true(
      @context.close_stage_requirements(owner, { ..limits, max_work: work - 1, })
      is Err(_),
    )
  }
}

///|
test "window numeric scopes without an admitted profile stay unresolved" {
  for aggregate in ["{\"fn\":\"sum\",\"field\":\"id\"}"] {
    let checked : Array[CheckedProgram] = []
    try
      local_construction_fixture(
        { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
        through_check=true,
        checked_results=checked,
        second_stage=true,
        tea=true,
        second_steps="[{\"row_window\":{\"time\":\"id\",\"kind\":\"fixed\",\"size\":10}},{\"window_group\":{\"by\":[\"id\"],\"aggregates\":{\"value\":" +
          aggregate +
          "}},\"as\":\"selected\"}]",
        second_result_from="selected",
        extra_step_budget=2,
      )
    catch {
      Closure(UnresolvedOperation(site)) => {
        assert_eq(site.stage, 1)
        assert_eq(site.step, 1)
        guard site.requirement is @pipeline.RelationRequirement(pending) else {
          fail("expected the window aggregate requirement")
        }
        assert_true(pending.kind is @relation.NumericAggregateObservation)
      }
      error => raise error
    } noraise {
      _ => fail("unclosed aggregate scope was accepted")
    }
    assert_eq(checked.length(), 0)
  }
}
