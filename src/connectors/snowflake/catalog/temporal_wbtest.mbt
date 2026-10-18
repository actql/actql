///|
test "selected DATE and LTZ formats retain exact Common temporal values" {
  let columns =
    #|[{"name":"DAY","type":"DATE","nullable":false},{"name":"INSTANT","type":"TIMESTAMP_LTZ","nullable":false,"scale":9}]
  let result = project_result_set(
    test_body(columns, "[[\"2024-02-29\",\"1969-12-31T23:59:59.999999999Z\"]]"),
    test_limits(),
  ).unwrap()
  assert_true(
    result_set_cell(result, 0, 0).unwrap().value is @admitted.Date("2024-02-29"),
  )
  assert_true(
    result_set_cell(result, 0, 1).unwrap().value
    is @admitted.Timestamp("1969-12-31T23:59:59.999999999Z"),
  )
}

///|
fn temporal_ltz_column(scale : Int, nullable? : Bool = false) -> String {
  "[{\"name\":\"INSTANT\",\"type\":\"TIMESTAMP_LTZ\",\"nullable\":" +
  nullable.to_string() +
  ",\"scale\":" +
  scale.to_string() +
  "}]"
}

///|
test "selected LTZ output canonicalizes only extra trailing zeros without losing precision" {
  for
    (original, canonical, scale) in [
      ("1970-01-01T00:00:00.000000000Z", "1970-01-01T00:00:00.000Z", 0),
      ("1970-01-01T00:00:00.123000000Z", "1970-01-01T00:00:00.123Z", 3),
      ("1970-01-01T00:00:00.123400000Z", "1970-01-01T00:00:00.1234Z", 4),
      ("1970-01-01T00:00:00.000000001Z", "1970-01-01T00:00:00.000000001Z", 9),
      ("9999-12-31T23:59:59.999999999Z", "9999-12-31T23:59:59.999999999Z", 9),
    ] {
    let result = project_result_set(
      test_body(temporal_ltz_column(scale), "[[\"" + original + "\"]]"),
      test_limits(),
    ).unwrap()
    assert_true(
      result_set_cell(result, 0, 0).unwrap().value
      is @admitted.Timestamp(actual) &&
      actual == canonical,
    )
  }
}

///|
test "selected LTZ refuses ambiguous epochs offsets and unselected authored spellings" {
  for
    text in [
      "1611871777123456789", "1611871777.123456789", "1970-01-01T00:00:00.123Z",
      "1970-01-01T00:00:00.1234567890Z", "1970-01-01T00:00:00.123456789z", "1970-01-01 00:00:00.123456789Z",
      "1970-01-01T00:00:00.123456789+00:00", "2023-02-29T00:00:00.000000000Z", "1970-01-01T00:00:60.000000000Z",
    ] {
    assert_true(
      project_result_set(
        test_body(temporal_ltz_column(9), "[[\"" + text + "\"]]"),
        test_limits(),
      )
      is Err(_),
    )
  }
}

///|
test "LTZ scale is retained and finer contradictory data is refused rather than rounded" {
  assert_true(
    project_result_set(
      test_body(
        temporal_ltz_column(3),
        "[[\"1970-01-01T00:00:00.123000001Z\"]]",
      ),
      test_limits(),
    )
    is Err(ValueBeyondScale("INSTANT")),
  )
  for scale in ["null", "true", "-1", "10", "1.5", "\"9\""] {
    let columns = "[{\"name\":\"INSTANT\",\"type\":\"TIMESTAMP_LTZ\",\"nullable\":false,\"scale\":" +
      scale +
      "}]"
    assert_true(
      project_result_set(
        test_body(columns, "[[\"1970-01-01T00:00:00.000000000Z\"]]"),
        test_limits(),
      )
      is Err(InvalidColumn("INSTANT")),
    )
  }
}

///|
test "Date uses the selected Gregorian format without session or epoch interpretation" {
  let columns = "[{\"name\":\"DAY\",\"type\":\"DATE\",\"nullable\":false}]"
  for
    value in [
      "18262", "01/01/2020", "2023-02-29", "2024-02-29T00:00:00.000Z", "2024-02-29 ",
    ] {
    assert_true(
      project_result_set(
        test_body(columns, "[[\"" + value + "\"]]"),
        test_limits(),
      )
      is Err(_),
    )
  }
  for value in ["0001-01-01", "2000-02-29", "9999-12-31"] {
    let result = project_result_set(
      test_body(columns, "[[\"" + value + "\"]]"),
      test_limits(),
    ).unwrap()
    assert_true(
      result_set_cell(result, 0, 0).unwrap().value is @admitted.Date(actual) &&
      actual == value,
    )
  }
}

///|
test "temporal SQL nullability and actual text node requirements stay independent" {
  let nullable = project_result_set(
    test_body(temporal_ltz_column(9, nullable=true), "[[null]]"),
    test_limits(),
  ).unwrap()
  assert_true(result_set_cell(nullable, 0, 0).unwrap().value is @admitted.Null)
  for raw in ["null", "true", "0", "\"null\""] {
    assert_true(
      project_result_set(
        test_body(temporal_ltz_column(9), "[[" + raw + "]]"),
        test_limits(),
      )
      is Err(_),
    )
  }
}

///|
test "temporal conversion retains the original raw response hash and partition identity" {
  let body = test_body(
    temporal_ltz_column(9),
    "[[\"1970-01-01T00:00:00.123400000Z\"]]",
    partitions="[{\"rowCount\":1},{\"rowCount\":1}]",
    total="2",
  )
  let result = project_result_set(body, test_limits()).unwrap()
  assert_eq(result_set_response_sha256(result), @sha.hex(body))
  let next = @utf8.encode("{\"data\":[[\"1969-12-31T23:59:59.999999999Z\"]]}")
  let partition = project_partition(next, result, 1, test_limits()).unwrap()
  assert_true(
    partition_cell(partition, 0, 0).unwrap().value
    is @admitted.Timestamp("1969-12-31T23:59:59.999999999Z"),
  )
}

///|
test "civil and retained-offset timestamp types remain explicit unfinished carriers" {
  for kind in ["TIME", "TIMESTAMP_NTZ", "TIMESTAMP_TZ"] {
    let columns = "[{\"name\":\"UNFINISHED\",\"type\":\"" +
      kind +
      "\",\"nullable\":false,\"scale\":9}]"
    assert_true(
      project_result_set(
        test_body(columns, "[[\"1970-01-01T00:00:00.000000000Z\"]]"),
        test_limits(),
      )
      is Err(UnsupportedColumn("UNFINISHED", observed)) &&
      observed == kind,
    )
  }
}
