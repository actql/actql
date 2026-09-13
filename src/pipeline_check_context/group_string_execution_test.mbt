///|
test "string execution binds owned occurrences and charges all candidates atomically" {
  for host in [None, Some(7L)] {
    let index = string_limit_fixture(
      string_limit_policy(host),
      ",\"max_bytes\":{\"$param\":\"n\"}",
    )
    let linked = link_program_group_string_limits(index, 10000000, 100, 100).unwrap()
    let mut count = 0
    for i in 0..<operation_resolution_count(index) {
      guard operation_resolution_at(linked, i)
        is Some(Execution(GroupExecution(check))) &&
        check.rule is EnforceStringBytes(limit) else {
        continue
      }
      count += 1
      assert_true(operation_resolution_at(index, i) is Some(Unresolved))
      assert_true(physical_equal(group_string_limit_owner(limit), index))
      assert_eq(group_string_limit_requirement(limit), i)
      assert_true(
        physical_equal(
          group_string_limit_call(limit),
          @relation.aggregate_for_validation(check.group, check.site.index).unwrap(),
        ),
      )
      assert_eq(check.step.input, Some(check.input))
      assert_eq(group_string_limit_maximum(limit), 1L)
      assert_true(
        group_string_limit_guard_resolution(limit).unwrap().value is Integer(1L),
      )
      assert_eq(
        operation_execution_phase(GroupExecution(check)),
        BeforeOperationOutput,
      )
      assert_eq(
        operation_execution_failure(GroupExecution(check)),
        RejectOperationOutput,
      )
    }
    assert_eq(count, 3)
    assert_eq(
      operation_resolution_unresolved_count(linked),
      operation_resolution_unresolved_count(index) - count,
    )
    let work = operation_resolution_work(linked)
    let candidates = count * (if host is Some(_) { 2 } else { 1 })
    assert_true(
      link_program_group_string_limits(index, work, count, candidates) is Ok(_),
    )
    assert_true(
      link_program_group_string_limits(index, work - 1, count, candidates)
      is Err(BudgetExceeded),
    )
    assert_true(
      link_program_group_string_limits(index, work, count - 1, candidates)
      is Err(BudgetExceeded),
    )
    assert_true(
      link_program_group_string_limits(index, work, count, candidates - 1)
      is Err(BudgetExceeded),
    )
    assert_true(
      link_program_group_string_limits(linked, 10000000, 100, 100)
      is Err(InvalidRequirement),
    )
  }
  let missing = string_limit_fixture(string_limit_policy(None), "")
  assert_true(
    link_program_group_string_limits(missing, 10000000, 100, 100)
    is Err(MissingFiniteBound),
  )
  assert_true(
    link_program_group_string_limits(missing, -1, 100, 100)
    is Err(InvalidLimits),
  )
}
