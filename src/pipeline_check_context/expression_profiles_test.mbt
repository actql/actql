///|
test "expression profiles inspect unselected and repeated owned occurrences" {
  let context = prepare_expression_validation(
    validation_fixture(validation_profile(valid_text_policy()), true),
    validation_limits(),
  ).unwrap()
  let neither : ExpressionProfiles = { text_time: false, veca: false, }
  let failure = check_expression_profiles(context, neither, 1000000)
  match failure {
    Err(UnsupportedProfile(i, profile)) => {
      assert_eq(profile, "actql-text-time/0.1")
      let site = expression_validation_at(context, i).unwrap()
      assert_true(
        validation_site_requirement(site).obligation.kind
        is @typing.ProfileAdmission(_),
      )
      assert_eq(
        expression_profiles_diagnostic(UnsupportedProfile(i, profile)),
        Some("ACTQL_E_PROFILE_UNSUPPORTED"),
      )
    }
    _ => fail("unclaimed profile accepted")
  }
  // VecA alone is not text-time support, and a present Host policy is not a claim.
  assert_true(
    check_expression_profiles(
      context,
      { text_time: false, veca: true, },
      1000000,
    )
    is Err(UnsupportedProfile(_, _)),
  )
  let declared : ExpressionProfiles = { text_time: true, veca: false, }
  let checked = check_expression_profiles(context, declared, 1000000).unwrap()
  assert_true(physical_equal(expression_profiles_context(checked), context))
  assert_eq(expression_profiles_declared(checked), declared)
  assert_eq(expression_profiles_count(checked), 3)
  assert_eq(expression_validation_count(context), 9)
  let work = expression_profiles_work(checked)
  assert_eq(work, expression_validation_usage(context).work + 10)
  assert_true(check_expression_profiles(context, declared, work) is Ok(_))
  assert_true(
    check_expression_profiles(context, declared, work - 1)
    is Err(BudgetExceeded),
  )
  assert_true(
    check_expression_profiles(context, declared, -1) is Err(InvalidLimits),
  )
  assert_eq(expression_profiles_diagnostic(BudgetExceeded), None)
}

///|
test "unused expression profiles do not require claims or fabricate policy" {
  let context = prepare_expression_validation(
    validation_fixture(capacity_profile(false), false),
    validation_limits(),
  ).unwrap()
  let checked = check_expression_profiles(
    context,
    { text_time: false, veca: false, },
    1000000,
  ).unwrap()
  assert_eq(expression_profiles_count(checked), 0)
  assert_true(expression_validation_text_time(context) is None)
}

///|
test "VecA expression claims are independent of text-time and Host policy" {
  let (inputs, capacity) = selected_fixture(
    false,
    steps=Some(
      (
        #|[{"as":"vectors","values":{"schema":{"v":{"type":"vector","dimensions":2,"nullable":false}},"rows":[{"v":[1,2]}]}},{"derive":{"x":"vector_score(v, v, 'dot')"}}]
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
  let context = prepare_expression_validation(selected, validation_limits()).unwrap()
  assert_true(
    check_expression_profiles(
      context,
      { text_time: true, veca: false, },
      1000000,
    )
    is Err(UnsupportedProfile(_, "actql-veca/0.1")),
  )
  let checked = check_expression_profiles(
    context,
    { text_time: false, veca: true, },
    1000000,
  ).unwrap()
  assert_eq(expression_profiles_count(checked), 3)
  assert_true(expression_validation_text_time(context) is None)
}
