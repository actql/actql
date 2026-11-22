///|
fn make_date_expression(
  day? : String = "{\"field\":\"d\"}",
) -> @lower.Expression {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"y\":{\"type\":\"int64\",\"nullable\":true},\"m\":{\"type\":\"int64\",\"nullable\":false},\"d\":{\"type\":\"int64\",\"nullable\":false}},\"rows\":[{\"y\":null,\"m\":\"1\",\"d\":\"1\"}]},\"as\":\"seed\"},{\"derive\":{\"date\":{\"make_date\":[{\"field\":\"y\"},{\"field\":\"m\"}," +
    day +
    "]}}}]",
  )
  @lower.lower_expression(owner, 1, 0, {
    max_nodes: 100,
    max_work: 10000,
    max_depth: 100,
    max_literal_nodes: 100,
    max_literal_text_bytes: 1000,
  }).unwrap()
}

///|
test "make_date preserves Gregorian range, calendar and exact original Date wire" {
  let expr = make_date_expression()
  let integer = (n : Int64) => capture(@admitted.signed64_value(n))
  for
    (y, m, d, expected) in [
      (1L, 1L, 1L, "0001-01-01"),
      (9999L, 12L, 31L, "9999-12-31"),
      (2000L, 2L, 29L, "2000-02-29"),
    ] {
    let result = evaluate_expression(
      expr,
      Map([("y", integer(y)), ("m", integer(m)), ("d", integer(d))]),
      [],
      { remaining: 1000, max_frames: 10, },
    ).unwrap()
    assert_true(result is Captured(@admitted.Date(date)) && date == expected)
  }
  for
    (y, m, d) in [
      (0L, 1L, 1L),
      (10000L, 1L, 1L),
      (9223372036854775807L, 1L, 1L),
      (1900L, 2L, 29L),
      (2026L, 13L, 1L),
      (2026L, 4L, 31L),
      (2026L, 1L, 0L),
    ] {
    assert_true(
      evaluate_expression(
        expr,
        Map([("y", integer(y)), ("m", integer(m)), ("d", integer(d))]),
        [],
        { remaining: 1000, max_frames: 10, },
      )
      is Err({ kind: Scalar(InvalidOperand), .. }),
    )
  }
  assert_true(
    evaluate_expression(
      expr,
      Map([("y", Null), ("m", integer(2L)), ("d", integer(3L))]),
      [],
      { remaining: 1000, max_frames: 10, },
    ).unwrap()
    is Null,
  )
  let writer = @encode.writer(10000, 100, 20)
  @lower.emit_expression(expr, writer)
  assert_eq(
    @encode.finish(writer),
    "{\"body\":[{\"body\":\"y\",\"op\":\"field\"},{\"body\":\"m\",\"op\":\"field\"},{\"body\":\"d\",\"op\":\"field\"}],\"op\":\"make_date\"}",
  )
}

///|
test "make_date does not skip a failing later coordinate after NULL" {
  let expr = make_date_expression(
    day="{\"integer_divide\":[{\"field\":\"d\"},{\"field\":\"m\"}]}",
  )
  let integer = (n : Int64) => capture(@admitted.signed64_value(n))
  assert_true(
    evaluate_expression(
      expr,
      Map([("y", Null), ("m", integer(0L)), ("d", integer(1L))]),
      [],
      { remaining: 1000, max_frames: 20, },
    )
    is Err({ kind: Scalar(ArithmeticFailure), .. }),
  )
}
