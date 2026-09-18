///|
fn admitted_profile() -> Profile {
  admit(
    fixture(),
    "sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df",
    100000,
  ).unwrap()
}

///|
test "numeric reductions preserve selected operation sequences" {
  let profile = admitted_profile()
  let left = select(
    profile, "sha256:4077bb93149235757642468a512543d949f48d5a81f04f49827193f3e9420f55",
  ).unwrap()
  let pairs = select(
    profile, "sha256:48158d55d2a97e7c1d3ea95c8b7e085469eedc6186f24b57427aa8e610dceeba",
  ).unwrap()
  let contributors = [10000000000000000.0, 1.0, -10000000000000000.0]
  let left_sum = execute(left, Sum, contributors, 3, 100).unwrap()
  let pair_sum = execute(pairs, Sum, contributors, 3, 100).unwrap()
  assert_eq(outcome_value(left_sum), Some(0.0))
  assert_eq(outcome_value(pair_sum), Some(0.0))
  assert_eq(outcome_count(left_sum), 3)
  assert_eq(outcome_work(left_sum), 6)
  assert_eq(outcome_work(pair_sum), 5)

  let four = [10000000000000000.0, 1.0, -10000000000000000.0, 1.0]
  assert_eq(outcome_value(execute(left, Sum, four, 4, 100).unwrap()), Some(1.0))
  assert_eq(
    outcome_value(execute(pairs, Sum, four, 4, 100).unwrap()),
    Some(0.0),
  )
}

///|
test "numeric reductions implement empty average and public zero laws" {
  let profile = admitted_profile()
  let left = select(
    profile, "sha256:4077bb93149235757642468a512543d949f48d5a81f04f49827193f3e9420f55",
  ).unwrap()
  let empty = execute(left, Average, [], 0, 0).unwrap()
  assert_eq(outcome_value(empty), None)
  assert_eq(outcome_count(empty), 0)
  assert_eq(outcome_work(empty), 0)

  let zero = execute(left, Sum, [-0.0], 1, 2).unwrap()
  let value = outcome_value(zero).unwrap()
  assert_eq(value, 0.0)
  assert_true(1.0 / value > 0.0)

  let average = execute(left, Average, [1.0, 2.0], 2, 5).unwrap()
  assert_eq(outcome_value(average), Some(1.5))
  assert_eq(outcome_work(average), 5)
}

///|
test "numeric reductions reject invalid domains and exact one-short work" {
  let profile = admitted_profile()
  let left = select(
    profile, "sha256:4077bb93149235757642468a512543d949f48d5a81f04f49827193f3e9420f55",
  ).unwrap()
  let pairs = select(
    profile, "sha256:48158d55d2a97e7c1d3ea95c8b7e085469eedc6186f24b57427aa8e610dceeba",
  ).unwrap()
  assert_true(execute(left, Sum, [1.0], -1, 2) is Err(InvalidLimits))
  assert_true(execute(left, Sum, [1.0], 0, 2) is Err(ContributorLimit))
  assert_true(execute(left, Sum, [1.0], 1, 1) is Err(WorkLimit))
  assert_eq(execute(left, Sum, [1.0], 1, 2).map(outcome_work), Ok(2))
  assert_true(execute(pairs, Average, [1.0, 2.0, 3.0], 3, 5) is Err(WorkLimit))
  assert_eq(
    execute(pairs, Average, [1.0, 2.0, 3.0], 3, 6).map(outcome_work),
    Ok(6),
  )
  assert_true(
    execute(left, Sum, [1.0 / 0.0], 1, 10) is Err(NonfiniteContributor(0)),
  )
  assert_true(
    execute(left, Sum, [1.7976931348623157e308, 1.7976931348623157e308], 2, 10)
    is Err(NonfiniteIntermediate),
  )
}
