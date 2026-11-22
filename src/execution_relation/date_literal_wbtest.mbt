///|
test "date literal preserves the Date value and distinct machine expression" {
  let date = "{\"date_literal\":\"2026-01-02\"}"
  assert_true(run_expr(date).unwrap() is Captured(@admitted.Date("2026-01-02")))
  let writer = @encode.writer(1000, 10, 10)
  @lower.emit_expression(lowered(date), writer)
  assert_eq(
    @encode.finish(writer),
    "{\"body\":\"2026-01-02\",\"op\":\"date_literal\"}",
  )

  let text = "{\"literal\":\"2026-01-02\"}"
  assert_true(run_expr(text).unwrap() is Text("2026-01-02"))
  let writer = @encode.writer(1000, 10, 10)
  @lower.emit_expression(lowered(text), writer)
  assert_eq(
    @encode.finish(writer),
    "{\"body\":\"2026-01-02\",\"op\":\"literal\"}",
  )
}
