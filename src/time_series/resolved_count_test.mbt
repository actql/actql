///|
fn admitted_timestamp(text : String) -> @value.CheckedValue {
  @value.admit(
    @contract.primitive(TimestampType, nullable=false),
    cursor("\"" + text + "\""),
    { max_nodes: 1, max_depth: 0, max_text_bytes: 24, },
  ).unwrap()
}

///|
test "resolved series counts validate typed endpoints and exact integer steps" {
  let declarations = @parameter.read_declarations(
    Some(
      cursor(
        "{\"a\":{\"type\":\"timestamp\"},\"z\":{\"type\":\"timestamp\"},\"s\":{\"type\":\"number\"}}",
      ),
    ),
    { max_parameters: 3, max_nodes: 30, max_depth: 10, max_text_bytes: 100, },
  ).unwrap()
  let checked = @time_series.check(
    cursor(
      "{\"start\":{\"$param\":\"a\"},\"end\":{\"$param\":\"z\"},\"step\":{\"$param\":\"s\"}}",
    ),
    Some(declarations),
    limits(),
  ).unwrap()
  for
    (a, z, step, expected) in [
      ("0000-01-01T00:00:00.000Z", "0001-01-01T00:00:00.000Z", 86400000L, 366L),
      ("1900-02-28T00:00:00.000Z", "1900-03-01T00:00:00.000Z", 86400000L, 1L),
      ("2000-02-28T00:00:00.000Z", "2000-03-01T00:00:00.000Z", 86400000L, 2L),
      (
        "0000-01-01T00:00:00.000Z", "9999-12-31T23:59:59.999Z", 1L, 315569519999999L,
      ),
      (
        "0000-01-01T00:00:00.000Z", "9999-12-31T23:59:59.999Z", 9007199254740991L,
        1L,
      ),
      ("2000-01-01T23:59:59.999Z", "2000-01-02T00:00:00.010Z", 3L, 4L),
      ("2000-01-01T00:00:00.000Z", "2000-01-01T00:00:00.000Z", 1L, 0L),
    ] {
    let start = admitted_timestamp(a)
    let end = admitted_timestamp(z)
    assert_eq(
      @time_series.resolve_row_count(
        checked,
        start_value=Some(start),
        end_value=Some(end),
        step_value=Some(step),
      ),
      Ok(expected),
    )
    assert_true(@time_series.known_row_count(checked) is None)
    for bad in [0L, -1L, 9007199254740992L] {
      assert_eq(
        @time_series.resolve_row_count(
          checked,
          start_value=Some(start),
          end_value=Some(end),
          step_value=Some(bad),
        ),
        Err(InvalidStep),
      )
    }
    assert_eq(
      @time_series.resolve_row_count(
        checked,
        start_value=Some(start),
        end_value=Some(end),
      ),
      Err(MissingStep),
    )
    if a != z {
      assert_eq(
        @time_series.resolve_row_count(
          checked,
          start_value=Some(end),
          end_value=Some(start),
          step_value=Some(step),
        ),
        Err(ReversedRange),
      )
    }
  }
  assert_eq(
    @time_series.resolve_row_count(checked),
    Err(MissingEndpoint("start")),
  )
  let text = @value.admit(
    @contract.primitive(StringType, nullable=false),
    cursor("\"2000-01-01T00:00:00.000Z\""),
    { max_nodes: 1, max_depth: 0, max_text_bytes: 24, },
  ).unwrap()
  assert_eq(
    @time_series.resolve_row_count(checked, start_value=Some(text)),
    Err(InvalidEndpoint("start")),
  )
}

///|
test "literal endpoints cannot be overwritten and empty ranges still validate bound steps" {
  let declarations = @parameter.read_declarations(
    Some(cursor("{\"s\":{\"type\":\"number\"}}")),
    { max_parameters: 1, max_nodes: 10, max_depth: 5, max_text_bytes: 100, },
  ).unwrap()
  let checked = @time_series.check(
    cursor(
      "{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-01T00:00:00.000Z\",\"step\":{\"$param\":\"s\"}}",
    ),
    Some(declarations),
    limits(),
  ).unwrap()
  assert_eq(@time_series.known_row_count(checked), Some(0L))
  assert_eq(@time_series.resolve_row_count(checked), Err(MissingStep))
  assert_eq(
    @time_series.resolve_row_count(checked, step_value=Some(0)),
    Err(InvalidStep),
  )
  assert_eq(@time_series.resolve_row_count(checked, step_value=Some(1)), Ok(0L))
  assert_eq(
    @time_series.resolve_row_count(
      checked,
      start_value=Some(admitted_timestamp("2000-01-01T00:00:00.000Z")),
      step_value=Some(1),
    ),
    Err(UnexpectedEndpoint("start")),
  )
  let literal = @time_series.check(
    cursor(
      "{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-01T00:00:00.000Z\",\"step\":1}",
    ),
    None,
    limits(),
  ).unwrap()
  assert_eq(@time_series.resolve_row_count(literal), Ok(0L))
  assert_eq(
    @time_series.resolve_row_count(literal, step_value=Some(1)),
    Err(UnexpectedStep),
  )
}
