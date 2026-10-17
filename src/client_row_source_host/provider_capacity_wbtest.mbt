///|
test "provider envelope addition is checked before the original reservation" {
  // Independent logical fixture units, not a production physical profile.
  let capacity = @execution.execution_capacity(7L, 9L).unwrap()
  assert_eq(
    row_provider_capacity_sum(11L, 13L, 5L, Some(capacity)).unwrap(),
    (18L, 27L),
  )
  assert_true(
    row_provider_capacity_sum(11L, 13L, 5L, None)
    is Err(Physical(InvalidLimits)),
  )
  assert_true(
    row_provider_capacity_sum(-1L, 13L, 5L, Some(capacity))
    is Err(Physical(InvalidLimits)),
  )
  assert_true(
    row_provider_capacity_sum(11L, -1L, 5L, Some(capacity))
    is Err(Physical(InvalidLimits)),
  )
  assert_true(
    row_provider_capacity_sum(11L, 13L, -1L, Some(capacity))
    is Err(Physical(InvalidLimits)),
  )
  assert_true(
    row_provider_capacity_sum(9223372036854775801L, 13L, 5L, Some(capacity))
    is Err(Physical(InvalidLimits)),
  )
  assert_true(
    row_provider_capacity_sum(11L, 9223372036854775799L, 0L, Some(capacity))
    is Err(Physical(InvalidLimits)),
  )
  assert_true(
    row_provider_capacity_sum(11L, 9223372036854775798L, 1L, Some(capacity))
    is Err(Physical(InvalidLimits)),
  )
}
