///|
test "GCS physical updated projects nine fractional digits into exact UTC without millisecond rounding" {
  for
    (reported, expected) in [
      ("2026-10-17T00:00:00.123001Z", "2026-10-17T00:00:00.123001Z"),
      ("2026-10-17T00:00:00.000000001Z", "2026-10-17T00:00:00.000000001Z"),
      ("2026-10-17T00:00:00.123456780Z", "2026-10-17T00:00:00.12345678Z"),
      ("2026-10-17T00:00:00.999999999Z", "2026-10-17T00:00:00.999999999Z"),
      ("1969-12-31T23:59:59.999999999Z", "1969-12-31T23:59:59.999999999Z"),
      ("1970-01-01T00:00:00.000000001+00:01", "1969-12-31T23:59:00.000000001Z"),
      ("2000-03-01T00:00:00.000000001+00:01", "2000-02-29T23:59:00.000000001Z"),
      ("2025-12-31T23:30:00.123456789-01:00", "2026-01-01T00:30:00.123456789Z"),
      ("2026-10-17T00:00:00.100000000Z", "2026-10-17T00:00:00.100Z"),
    ] {
    assert_eq(object_source_timestamp(reported), Some(expected))
    assert_true(@admitted.timestamp_instant(expected) is Some(_))
  }
}

///|
test "GCS exact updated Source row retains independent physical report digest and byte bound" {
  let reported = "2026-10-17T01:30:00.123456789+01:30"
  let wire = object_page_wire(
    "[" + metadata_wire(extra=",\"updated\":\"" + reported + "\"") + "]",
  )
  let page = object_page_read(wire).unwrap()
  assert_eq(page.items[0].updated, Some(reported))
  assert_eq(
    object_metadata_page_response_sha256(page),
    @sha.hex(@utf8.encode(wire)),
  )
  let row = object_metadata_page_row_json(page, 0, 8192, metadata_limits()).unwrap()
  assert_true(row.contains("\"updated\":\"2026-10-17T00:00:00.123456789Z\""))
  assert_true(row.contains("\"version\":\"9007199254740993\""))
  let size = @utf8.encode(row).length()
  assert_eq(
    object_metadata_page_row_json(page, 0, size, metadata_limits()),
    Ok(row),
  )
  assert_true(
    object_metadata_page_row_json(page, 0, size - 1, metadata_limits())
    is Err(BudgetExceeded),
  )
  assert_eq(page.items[0].updated, Some(reported))
  assert_eq(
    object_metadata_page_response_sha256(page),
    @sha.hex(@utf8.encode(wire)),
  )
}

///|
test "GCS exact updated keeps its original physical grammar and range refusals" {
  for
    invalid in [
      "2026-10-17T00:00:00.0000000001Z", "2026-10-17T00:00:00.1234567890Z", "2026-10-17t00:00:00.123456789Z",
      "2026-10-17T00:00:00.123456789z", "2026-10-17T00:00:60.123456789Z", "2026-02-29T00:00:00.123456789Z",
      "2026-10-17T00:00:00.123456789+24:00", "2026-10-17T00:00:00.123456789+01:60",
      "0000-01-01T00:00:00.000000001+00:01", "9999-12-31T23:59:59.999999999-00:01",
    ] {
    assert_eq(object_source_timestamp(invalid), None)
  }
}
