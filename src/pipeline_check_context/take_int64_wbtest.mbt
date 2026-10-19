///|
test "take int64 count bindings preserve exact safe-integer domains without numeric promotion" {
  for
    (n, accepted) in [
      (0L, false),
      (-1L, false),
      (1L, true),
      (9007199254740991L, true),
      (9007199254740992L, false),
      (9223372036854775807L, false),
    ] {
    let result = operation_scalar_value(
      @value.signed64_value(n),
      @pipeline.SafeInteger("n", minimum=1L),
    )
    assert_eq(result is Some(_), accepted)
    if accepted {
      assert_eq(result, Some(Integer(n)))
    }
  }
  assert_eq(
    operation_scalar_value(
      @value.signed64_value(0L),
      @pipeline.SafeInteger("offset", minimum=0L),
    ),
    Some(Integer(0L)),
  )
  for
    demand in [
      @pipeline.Fraction("n"),
      @pipeline.Finite("n"),
      @pipeline.Milliseconds("n", signed=true),
    ] {
    assert_true(
      operation_scalar_value(@value.signed64_value(1L), demand) is None,
    )
  }
}
