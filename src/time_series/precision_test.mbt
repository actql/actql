///|
test "bound series counts preserve exact admitted fractional endpoints" {
  let declarations = @parameter.read_declarations(
    Some(
      cursor("{\"a\":{\"type\":\"timestamp\"},\"z\":{\"type\":\"timestamp\"}}"),
    ),
    { max_parameters: 2, max_nodes: 20, max_depth: 10, max_text_bytes: 100, },
  ).unwrap()
  let series = @time_series.check(
    cursor(
      "{\"start\":{\"$param\":\"a\"},\"end\":{\"$param\":\"z\"},\"step\":1}",
    ),
    Some(declarations),
    limits(),
  ).unwrap()
  for
    (a, z, expected) in [
      ("2000-01-01T00:00:00.000000001Z", "2000-01-01T00:00:00.001000002Z", 2L),
      ("2000-01-01T00:00:00.123Z", "2000-01-01T00:00:00.123000001Z", 1L),
      ("2000-01-01T00:00:00.000000001Z", "2000-01-01T00:00:00.001Z", 1L),
      ("2000-01-01T00:00:00.000000001Z", "2000-01-01T00:00:00.001000001Z", 1L),
      ("1969-12-31T23:59:59.999999999Z", "1970-01-01T00:00:00.001Z", 2L),
      (
        "0000-01-01T00:00:00.000000001Z", "9999-12-31T23:59:59.999999999Z", 315569520000000L,
      ),
    ] {
    let admit = fn(text) {
      @value.admit(
        @contract.primitive(TimestampType, nullable=false),
        cursor("\"" + text + "\""),
        { max_nodes: 1, max_depth: 0, max_text_bytes: 30, },
      ).unwrap()
    }
    let start = admit(a)
    let end = admit(z)
    assert_true(start.value is @value.Timestamp(text) && text == a)
    assert_true(end.value is @value.Timestamp(text) && text == z)
    assert_eq(
      @time_series.resolve_row_count(
        series,
        start_value=Some(start),
        end_value=Some(end),
      ),
      Ok(expected),
    )
    assert_eq(
      @time_series.resolve_row_count(
        series,
        start_value=Some(end),
        end_value=Some(start),
      ),
      Err(ReversedRange),
    )
    assert_eq(
      @time_series.resolve_row_count(
        series,
        start_value=Some(start),
        end_value=Some(start),
      ),
      Ok(0L),
    )
  }
}

///|
test "literal series endpoints use the same exact fractional count and ordering" {
  let a = "2000-01-01T00:00:00.123Z"
  let z = "2000-01-01T00:00:00.124000001Z"
  let series = @time_series.check(
    cursor("{\"start\":\"" + a + "\",\"end\":\"" + z + "\",\"step\":1}"),
    None,
    limits(),
  ).unwrap()
  assert_true(@time_series.start(series) is Literal(text) && text == a)
  assert_true(@time_series.end(series) is Literal(text) && text == z)
  assert_eq(@time_series.known_row_count(series), Some(2L))
  assert_eq(@time_series.resolve_row_count(series), Ok(2L))
  let reversed = @time_series.check(
    cursor("{\"start\":\"" + z + "\",\"end\":\"" + a + "\",\"step\":1}"),
    None,
    limits(),
  ).unwrap_err()
  assert_eq(reversed.kind, @time_series.ReversedRange)
}
