///|
test "SQL TIMESTAMP literal produces the canonical UTC expression" {
  for
    (source, expected) in [
      ("2026-01-02 03:04:05+00", "2026-01-02T03:04:05.000Z"),
      ("2026-1-2 0:3:4.123456+7:30", "2026-01-01T16:33:04.123456Z"),
      ("1969-12-31t23:59:58.75z", "1969-12-31T23:59:58.750Z"),
      ("2016-12-31 23:59:60 Etc/UTC", "2017-01-01T00:00:00.000Z"),
      ("2024-2-29", "2024-02-29T00:00:00.000Z"),
      ("9999-12-31 23:59:59.999999Z", "9999-12-31T23:59:59.999999Z"),
      ("0001-01-01 14:00:00+14", "0001-01-01T00:00:00.000Z"),
    ] {
    let program = compile(
      @query.parse_query(
        "SELECT TIMESTAMP '" + source + "' AS x",
        syntax_limits(),
      ).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_true(semantic(program).contains("\"literal\":\"" + expected + "\""))
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("the literal already includes a complete instant")
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
  }
}

///|
test "SQL TIMESTAMP literal refuses invalid dates, offsets and precision" {
  for
    source in [
      "0000-01-01", "2026-02-29", "2026-01-02 00:30:00+14:1", "0001-01-01 00:00:00+00:01",
      "9999-12-31 23:59:60Z", "2026-01-02 03:04:05.1234567Z", "2026-01-02 03:04:05 Z",
      "2026-01-02 24:00:00Z",
    ] {
    assert_true(
      compile(
        @query.parse_query(
          "SELECT TIMESTAMP '" + source + "' AS x",
          syntax_limits(),
        ).unwrap(),
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      )
      is Err(Expression({ issue: InvalidArguments, .. })),
      msg=source,
    )
  }
}
