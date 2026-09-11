///|
test "query count products preserve safe integer and zero boundaries" {
  let largest = 9007199254740991L
  for
    (left, right, expected) in [
      (largest, 1L, Ok(largest)),
      (largest, 0L, Ok(0L)),
      (0L, largest, Ok(0L)),
      (largest, 2L, Err(BoundOverflow)),
      (94906265L, 94906265L, Ok(9007199136250225L)),
      (94906266L, 94906266L, Err(BoundOverflow)),
    ] {
    let query : QueryBound = {
      inputs: [],
      left: LiteralCount(left),
      right: LiteralCount(right),
      selection: @graph.EachPair,
      clamp_left_to_right: false,
    }
    assert_eq(query_bound_value(query, _ => 0L), expected)
    assert_eq(
      query_bound_value({ ..query, selection: @graph.NearestPerSource, }, _ => {
        0L
      }),
      Ok(left),
    )
    assert_eq(
      query_bound_value({ ..query, selection: @graph.NearestPair, }, _ => 0L),
      Ok(1L),
    )
  }
  // Selector membership bounds the distinct starts by graph extent before the
  // multiplication; an oversized relation does not cause false overflow.
  let traversal : QueryBound = {
    inputs: [],
    left: LiteralCount(largest),
    right: LiteralCount(2L),
    selection: @graph.EachPair,
    clamp_left_to_right: true,
  }
  assert_eq(query_bound_value(traversal, _ => 0L), Ok(4L))
}
