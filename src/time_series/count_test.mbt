///|
test "literal row counts are exact across calendar and millisecond boundaries" {
  // Fixed expectations independently checked with ECMAScript UTC Date parsing.
  let cases : Array[(String, String, String, Int64)] = [
    ("0000-01-01T00:00:00.000Z", "0001-01-01T00:00:00.000Z", "86400000", 366L),
    ("1900-02-28T00:00:00.000Z", "1900-03-01T00:00:00.000Z", "86400000", 1L),
    ("2000-02-28T00:00:00.000Z", "2000-03-01T00:00:00.000Z", "86400000", 2L),
    (
      "0000-01-01T00:00:00.000Z", "9999-12-31T23:59:59.999Z", "1", 315569519999999L,
    ),
    (
      "0000-01-01T00:00:00.000Z", "9999-12-31T23:59:59.999Z", "9007199254740991",
      1L,
    ),
    ("2000-01-01T23:59:59.999Z", "2000-01-02T00:00:00.010Z", "3", 4L),
    (
      "2000-01-01T00:00:00.000Z", "2400-01-01T00:00:00.000Z", "86400000", 146097L,
    ),
    ("2000-01-01T00:00:00.000Z", "2000-01-01T00:00:00.000Z", "1", 0L),
    ("2000-01-01T00:00:00.000Z", "2000-01-01T00:00:00.010Z", "5", 2L),
    ("2000-01-01T00:00:00.000Z", "2000-01-01T00:00:00.001Z", "2", 1L),
  ]
  for (a, z, step, expected) in cases {
    let c = @time_series.check(
      cursor(
        "{\"start\":\"" + a + "\",\"end\":\"" + z + "\",\"step\":" + step + "}",
      ),
      None,
      limits(),
    ).unwrap()
    assert_eq(@time_series.known_row_count(c), Some(expected))
    assert_true(!@time_series.pending_validations(c).contains(ResolveRowBound))
    assert_true(@time_series.pending_validations(c).contains(ResolveResources))
    assert_true(@time_series.pending_validations(c).contains(CheckedArithmetic))
  }
}

///|
test "row counts never substitute defaults and empty intervals retain binding obligations" {
  let parameters = @parameter.read_declarations(
    Some(
      cursor(
        "{\"start\":{\"type\":\"timestamp\",\"default\":\"2000-01-01T00:00:00.000Z\"},\"step\":{\"type\":\"number\",\"default\":1}}",
      ),
    ),
    { max_parameters: 2, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  for
    (start, step, expected) in [
      ("{\"$param\":\"start\"}", "1", None),
      ("\"1999-01-01T00:00:00.000Z\"", "{\"$param\":\"step\"}", None),
      ("\"2000-01-01T00:00:00.000Z\"", "{\"$param\":\"step\"}", Some(0L)),
    ] {
    let c = @time_series.check(
      cursor(
        "{\"start\":" +
        start +
        ",\"end\":\"2000-01-01T00:00:00.000Z\",\"step\":" +
        step +
        "}",
      ),
      Some(parameters),
      limits(),
    ).unwrap()
    assert_eq(@time_series.known_row_count(c), expected)
    assert_eq(
      @time_series.pending_validations(c).contains(ResolveRowBound),
      expected is None,
    )
    assert_true(@time_series.pending_validations(c).contains(ValidateRange))
    if step == "{\"$param\":\"step\"}" {
      assert_true(
        @time_series.pending_validations(c).contains(BindStep("step")),
      )
    }
  }
}
