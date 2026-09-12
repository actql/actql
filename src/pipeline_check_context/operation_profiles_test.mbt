///|
test "unused temporal generators require TEA in every owned producer visit" {
  let (inputs, capacity) = selected_fixture(
    false,
    steps=Some(
      (
        #|[{"time_series":{"start":"2000-01-01T00:00:00.000Z","end":"2000-01-01T00:00:00.000Z","step":"1s"},"as":"grid"},{"derive":{"x":"$n"},"from":"a"}]
      ),
    ),
  )
  let selected = bind_capacity_policy(
    inputs,
    capacity,
    max_work=1000000,
    max_text_bytes=1000000,
    max_policy_nodes=100,
  ).unwrap()
  let validation = prepare_expression_validation(selected, validation_limits()).unwrap()
  let expressions = check_text_bounds(
    check_patterns(validation, pattern_limits()).unwrap(),
    bound_limits(),
  ).unwrap()
  let profiles = check_expression_profiles(
    validation,
    { text_time: false, veca: false, },
    1000000,
  ).unwrap()
  let preparation = assemble_preparation(
    preparation_sources_fixture(selected),
    expressions,
    profiles,
    preparation_limits(),
  ).unwrap()
  let declared : PureOperationProfiles = {
    rela: true,
    sga: false,
    tea: false,
    calendar: false,
    text_rank: false,
  }
  assert_true(
    check_operation_profiles(preparation, declared, 10000000)
    is Err(UnsupportedProfile(0, 0, 0, @pipeline.TEA)),
  )
  // Merely declaring Calendar does not silently enable its TEA prerequisite.
  assert_true(
    check_operation_profiles(
      preparation,
      { ..declared, calendar: true, },
      10000000,
    )
    is Err(UnsupportedProfile(0, 0, 0, @pipeline.TEA)),
  )
  let admitted = { ..declared, tea: true, }
  let result = check_operation_profiles(preparation, admitted, 10000000).unwrap()
  assert_eq(operation_profiles_count(result), 6)
  assert_eq(
    operation_profiles_work(result),
    preparation_usage(preparation).work + 18,
  )
  assert_true(
    physical_equal(operation_profiles_preparation(result), preparation),
  )
  assert_true(
    check_operation_profiles(
      preparation,
      { ..admitted, rela: false, },
      10000000,
    )
    is Err(UnsupportedProfile(0, 0, 1, @pipeline.RelA)),
  )
  assert_true(
    check_operation_profiles(
      preparation,
      admitted,
      operation_profiles_work(result) - 1,
    )
    is Err(BudgetExceeded),
  )
}
