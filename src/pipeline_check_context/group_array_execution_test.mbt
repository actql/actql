///|
test "array envelopes bind exact calls with cumulative budgets and atomic failure" {
  let profiles = resolution_profiles(
    operation_order_fixture(
      "[{\"derive\":{\"x\":\"concat($p, to_string($n))\"}},{\"assert_rows\":{\"unique_by\":[\"id\"]}},{\"group\":{\"by\":[],\"aggregates\":{\"a\":{\"fn\":\"array_agg\",\"field\":\"id\",\"order_by\":[{\"id\":\"asc\"}],\"max_items\":{\"$param\":\"n\"}},\"b\":{\"fn\":\"array_agg\",\"field\":\"id\",\"order_by\":[{\"id\":\"asc\"}],\"max_items\":2},\"z\":{\"fn\":\"sum\",\"field\":\"id\"}}}}]",
    ),
  )
  let index = index_program_operation_resolutions(profiles, 10000000, 100).unwrap()
  let linked = link_program_group_array_limits(index, 10000000, 100, 100).unwrap()
  assert_true(
    physical_equal(
      operation_resolution_requirements(index),
      operation_resolution_requirements(linked),
    ),
  )
  let mut arrays = 0
  let mut remaining = 0
  for i in 0..<operation_resolution_count(index) {
    match operation_resolution_at(linked, i).unwrap() {
      Execution(GroupExecution(check)) => {
        guard check.rule is EnforceArrayItems(limit) else { continue }
        arrays += 1
        assert_true(operation_resolution_at(index, i) is Some(Unresolved))
        assert_true(physical_equal(group_array_limit_owner(limit), index))
        assert_eq(group_array_limit_requirement(limit), i)
        assert_true(
          physical_equal(
            check.site,
            operation_requirements_at(
              operation_resolution_requirements(index),
              i,
            ).unwrap(),
          ),
        )
        assert_true(
          physical_equal(
            group_array_limit_call(limit),
            @relation.aggregate_for_validation(check.group, check.site.index).unwrap(),
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
        assert_eq(
          group_array_limit_guard(limit),
          Some(
            if @relation.aggregate_name(group_array_limit_call(limit)) == "a" {
              1L
            } else {
              2L
            },
          ),
        )
      }
      Unresolved => {
        remaining += 1
        assert_true(operation_resolution_at(index, i) is Some(Unresolved))
      }
      _ => ()
    }
  }
  // Both calls are also visited through the consumer Stage's producer closure.
  assert_eq(arrays, 6)
  assert_eq(
    operation_resolution_unresolved_count(linked),
    operation_resolution_unresolved_count(index) - arrays,
  )
  assert_true(remaining > 0)
  assert_true(
    close_program_operations(linked, 10000000, 100)
    is Err(IncompleteResolution(_)),
  )
  let work = operation_resolution_work(linked)
  assert_true(
    link_program_group_array_limits(index, work, arrays, arrays * 2) is Ok(_),
  )
  assert_true(
    link_program_group_array_limits(index, work - 1, arrays, arrays * 2)
    is Err(BudgetExceeded),
  )
  assert_true(
    link_program_group_array_limits(index, work, arrays - 1, arrays * 2)
    is Err(BudgetExceeded),
  )
  assert_true(
    link_program_group_array_limits(index, work, arrays, arrays * 2 - 1)
    is Err(BudgetExceeded),
  )
  assert_true(
    link_program_group_array_limits(index, work, 0, 0) is Err(BudgetExceeded),
  )
  assert_true(
    link_program_group_array_limits(index, -1, 2, 4) is Err(InvalidLimits),
  )
  assert_true(
    link_program_group_array_limits(linked, 10000000, 2, 4)
    is Err(ForeignEvidence),
  )
}
