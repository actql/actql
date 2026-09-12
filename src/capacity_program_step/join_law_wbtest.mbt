///|
test "pinned join laws retain outer emptiness and safe arithmetic" {
  for
    (kind, left, right, expected) in [
      (@join.Inner, 3L, 4L, Ok(12L)),
      (@join.Inner, 0L, 9007199254740991L, Ok(0L)),
      (@join.Left, 3L, 0L, Ok(3L)),
      (@join.Full, 0L, 4L, Ok(4L)),
      (@join.Full, 3L, 0L, Ok(3L)),
      (@join.Full, 1L, 4L, Ok(5L)),
      (@join.Full, 3L, 1L, Ok(4L)),
      (@join.Full, 2L, 3L, Ok(6L)),
      (@join.Semi, 3L, 0L, Ok(0L)),
      (@join.Semi, 3L, 4L, Ok(3L)),
      (@join.Anti, 3L, 0L, Ok(3L)),
      (@join.Inner, 9007199254740991L, 2L, Err(BoundOverflow)),
      (@join.Full, 9007199254740991L, 1L, Err(BoundOverflow)),
    ] {
    assert_eq(
      join_bound(
        kind,
        @numeric.read(left).unwrap(),
        @numeric.read(right).unwrap(),
        None,
      ),
      expected,
    )
  }
}
