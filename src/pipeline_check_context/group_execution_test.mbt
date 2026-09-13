///|
test "group execution binds result contracts without discharging numeric observations" {
  let profiles = resolution_profiles(
    operation_order_fixture(
      "[{\"derive\":{\"x\":\"concat($p, to_string($n))\"}},{\"group\":{\"by\":[\"id\",\"id\"],\"aggregates\":{\"z\":{\"fn\":\"sum\",\"field\":\"id\"},\"a\":{\"fn\":\"count\",\"expr\":\"id / 0\",\"filter\":\"FALSE\"}}}}]",
    ),
  )
  let index = index_program_operation_resolutions(profiles, 10000000, 100).unwrap()
  let mut partitions = 0
  let mut calls = 0
  let mut bounds = 0
  let mut observations = 0
  for i in 0..<operation_resolution_count(index) {
    let site = operation_requirements_at(
      operation_resolution_requirements(index),
      i,
    ).unwrap()
    guard site.requirement is @pipeline.RelationRequirement(pending) else {
      continue
    }
    match operation_resolution_at(index, i).unwrap() {
      Execution(GroupExecution(check)) => {
        assert_true(physical_equal(check.site, site))
        assert_true(
          physical_equal(
            check.step,
            @pipeline.step_at(site.pipeline, site.step).unwrap(),
          ),
        )
        assert_eq(check.step.input, Some(check.input))
        assert_eq(
          operation_execution_phase(GroupExecution(check)),
          BeforeOperationOutput,
        )
        assert_eq(
          operation_execution_failure(GroupExecution(check)),
          RejectOperationOutput,
        )
        match check.rule {
          EnforceArrayItems(_) => fail("array limits require explicit linking")
          EnforceStringBytes(_) =>
            fail("string limits require explicit linking")
          EnforceStatisticalLaw(_, _) => fail("unexpected statistical fold")
          ValidateResultContract(call) => {
            assert_eq(pending.kind, @relation.AggregateEnvelope)
            assert_true(
              physical_equal(
                call,
                @relation.aggregate_for_validation(check.group, site.index).unwrap(),
              ),
            )
            bounds += 1
          }
          PartitionGroups => {
            assert_eq(pending.kind, @relation.GroupPartitioning)
            assert_eq(@relation.group_keys(check.group).length(), 2)
            partitions += 1
          }
          EvaluateAggregate(call) => {
            assert_eq(pending.kind, @relation.AggregateDemand)
            assert_true(
              physical_equal(
                call,
                @relation.aggregate_for_validation(check.group, site.index).unwrap(),
              ),
            )
            if @relation.aggregate_name(call) == "a" {
              assert_true(@relation.aggregate_filter(call) is Some(_))
              assert_true(
                @relation.aggregate_argument(call) is @relation.Expression(_),
              )
            } else {
              assert_eq(@relation.aggregate_name(call), "z")
              assert_true(@relation.aggregate_filter(call) is None)
            }
            calls += 1
          }
        }
      }
      Unresolved =>
        match pending.kind {
          @relation.AggregateEnvelope =>
            fail("scalar result contract was not bound")
          @relation.NumericAggregateObservation => observations += 1
          _ => ()
        }
      _ => ()
    }
  }
  assert_true(partitions > 0)
  assert_eq(calls, partitions * 2)
  assert_eq(bounds, calls)
  assert_eq(observations, partitions)
  assert_true(
    close_program_operations(index, 10000000, 100)
    is Err(IncompleteResolution(_)),
  )
  let work = operation_resolution_work(index)
  assert_true(index_program_operation_resolutions(profiles, work, 100) is Ok(_))
  assert_true(
    index_program_operation_resolutions(profiles, work - 1, 100)
    is Err(BudgetExceeded),
  )
}

///|
test "empty global group retains its partition execution obligation" {
  let profiles = resolution_profiles(
    operation_order_fixture(
      "[{\"derive\":{\"x\":\"concat($p, to_string($n))\"}},{\"group\":{\"by\":[],\"aggregates\":{}}}]",
    ),
  )
  let index = index_program_operation_resolutions(profiles, 10000000, 100).unwrap()
  assert_eq(operation_resolution_unresolved_count(index), 0)
  let closed = close_program_operations(index, 10000000, 100).unwrap()
  assert_true(operation_closure_count(closed) > 0)
  for i in 0..<operation_closure_count(closed) {
    guard operation_closure_at(closed, i)
      is Some(ExecutionCheck(GroupExecution(check))) else {
      fail("missing empty-group execution")
    }
    assert_true(check.rule is PartitionGroups)
    assert_eq(@relation.group_keys(check.group).length(), 0)
    assert_eq(@relation.aggregate_count(check.group), 0)
  }
}
