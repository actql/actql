///|
test "right join upper bound preserves empty and asymmetric inputs" {
  for
    (left, right, expected) in [
      (0L, 0L, 0L),
      (0L, 4L, 4L),
      (4L, 0L, 0L),
      (1L, 5L, 5L),
      (5L, 1L, 5L),
      (2L, 3L, 6L),
    ] {
    assert_eq(
      join_bound(
        @join.Right,
        @numeric.read(left).unwrap(),
        @numeric.read(right).unwrap(),
        None,
      ),
      Ok(expected),
    )
  }
  assert_eq(
    join_bound(
      @join.Right,
      @numeric.read(9007199254740991L).unwrap(),
      @numeric.read(0L).unwrap(),
      None,
    ),
    Ok(0L),
  )
  assert_eq(
    join_bound(
      @join.Right,
      @numeric.read(9007199254740991L).unwrap(),
      @numeric.read(2L).unwrap(),
      None,
    ),
    Err(BoundOverflow),
  )
}
