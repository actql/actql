///|
test "SQL timestamp functions lower format-first arguments to existing Common fields" {
  assert_eq(
    emit("PARSE_TIMESTAMP('yyyy-MM-dd', '2026-01-02')"),
    "{\"parse_timestamp\":{\"pattern\":{\"literal\":\"yyyy-MM-dd\"},\"value\":{\"literal\":\"2026-01-02\"}}}",
  )
  assert_eq(
    emit(
      "FORMAT_TIMESTAMP('yyyy', CAST('2026-01-02T00:00:00.000Z' AS TIMESTAMP))",
    ),
    "{\"format_timestamp\":{\"pattern\":{\"literal\":\"yyyy\"},\"value\":{\"cast\":{\"target\":{\"type\":\"timestamp\"},\"value\":{\"literal\":\"2026-01-02T00:00:00.000Z\"}}}}}",
  )
}

///|
test "SQL timestamp functions preserve original parameter and NULL roles" {
  for
    (name, tag) in [
      ("PARSE_TIMESTAMP", "parse_timestamp"),
      ("FORMAT_TIMESTAMP", "format_timestamp"),
    ] {
    assert_eq(
      emit(name + "(@format, @value)"),
      "{\"" +
      tag +
      "\":{\"pattern\":{\"$param\":\"format\"},\"value\":{\"$param\":\"value\"}}}",
    )
    assert_eq(
      emit(name + "('yyyy-MM-dd', NULL)"),
      "{\"" +
      tag +
      "\":{\"pattern\":{\"literal\":\"yyyy-MM-dd\"},\"value\":{\"literal\":null}}}",
    )
  }
  // The established TRY_TIMESTAMP surface is value-first, not a SQL format
  // spelling. Connecting the two functions must not reverse that contract.
  assert_eq(
    emit("TRY_TIMESTAMP(@value, @format)"),
    "{\"try_timestamp\":{\"pattern\":{\"$param\":\"format\"},\"value\":{\"$param\":\"value\"}}}",
  )
}

///|
test "SQL timestamp functions retain closed arity and namespace refusal" {
  for name in ["PARSE_TIMESTAMP", "FORMAT_TIMESTAMP"] {
    for args in ["", "'yyyy'", "'yyyy', NULL, 'UTC'"] {
      assert_true(
        lower(fixture(name + "(" + args + ")"), _ => None, limits())
        is Err({ issue: InvalidArguments, .. }),
      )
    }
    assert_true(
      lower(fixture("ACTQL." + name + "('yyyy', NULL)"), _ => None, limits())
      is Err({ issue: UnsupportedFunction, .. }),
    )
  }
}

///|
test "SQL timestamp functions retain lowering work admission" {
  for name in ["PARSE_TIMESTAMP", "FORMAT_TIMESTAMP"] {
    assert_true(
      lower(fixture(name + "('yyyy-MM-dd', NULL)"), _ => None, {
        ..limits(),
        max_work: 0,
      })
      is Err({ issue: WorkLimit, .. }),
    )
  }
}
