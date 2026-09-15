///|
test "adaptive quantities retain occurrences unknowns and pair overflow" {
  let sum : Result[Int64?, AdaptiveEstimateIssue[Unit]] = sum_dispatch_quantities([
      Some(7L),
      Some(7L),
    ],
  )
  assert_eq(sum.unwrap(), Some(14L))
  let unknown : Result[Int64?, AdaptiveEstimateIssue[Unit]] = sum_dispatch_quantities([
      Some(7L),
      None,
    ],
  )
  assert_eq(unknown.unwrap(), None)
  let zero_pair : Result[Int64?, AdaptiveEstimateIssue[Unit]] = dispatch_pair_quantity(
    Some(0L),
    None,
  )
  assert_eq(zero_pair.unwrap(), Some(0L))
  let unknown_pair : Result[Int64?, AdaptiveEstimateIssue[Unit]] = dispatch_pair_quantity(
    Some(2L),
    None,
  )
  assert_eq(unknown_pair.unwrap(), None)
  let pairs : Result[Int64?, AdaptiveEstimateIssue[Unit]] = dispatch_pair_quantity(
    Some(2L),
    Some(3L),
  )
  assert_eq(pairs.unwrap(), Some(6L))
  let overflow_pair : Result[Int64?, AdaptiveEstimateIssue[Unit]] = dispatch_pair_quantity(
    Some(9223372036854775807L),
    Some(2L),
  )
  assert_true(overflow_pair is Err(EstimateOverflow))
  let overflow_sum : Result[Int64?, AdaptiveEstimateIssue[Unit]] = sum_dispatch_quantities([
      Some(9223372036854775807L),
      Some(1L),
    ],
  )
  assert_true(overflow_sum is Err(EstimateOverflow))
}
