///|
test "physical timestamp conversion retains the exact instant without broadening canonical admission" {
  let contract = @contract.primitive(@contract.TimestampType, nullable=false)
  for
    (original, expected) in [
      ("2026-10-17T10:00:00+09:00", "2026-10-17T01:00:00.000Z"),
      ("2026-10-17T01:00:00-02:30", "2026-10-17T03:30:00.000Z"),
      ("2026-10-17t01:00:00.123000z", "2026-10-17T01:00:00.123Z"),
      ("2026-10-17T00:00:00.1+00:00", "2026-10-17T00:00:00.100Z"),
      ("2026-10-17T00:00:00.12Z", "2026-10-17T00:00:00.120Z"),
      ("2024-03-01T00:30:00+01:00", "2024-02-29T23:30:00.000Z"),
    ] {
    assert_eq(normalize_timestamp_text(original, 40), Some(expected))
    assert_true(checked_timestamp_value(original, contract) is None)
    assert_true(checked_timestamp_value(expected, contract) is Some(_))
    assert_eq(normalize_timestamp_text(original, original.length() - 1), None)
  }
}

///|
test "physical timestamp conversion refuses unknown offsets invalid dates range loss and exhausted input bounds" {
  for
    original in [
      "2026-02-29T00:00:00Z", "2026-10-17T25:00:00Z", "2026-10-17T00:00:60Z", "2026-10-17T00:00:00.0001Z",
      "2026-10-17T00:00:00.Z", "2026-10-17T00:00:00-00:00", "2026-10-17T00:00:00+24:00",
      "2026-10-17T00:00:00+00:60", "2026-10-17T00:00:00", "0000-01-01T00:00:00+01:00",
      "9999-12-31T23:59:59-01:00",
    ] {
    assert_eq(normalize_timestamp_text(original, 40), None)
  }
  let canonical = "2026-10-17T00:00:00.000Z"
  assert_eq(normalize_timestamp_text(canonical, 24), Some(canonical))
  assert_eq(normalize_timestamp_text(canonical, 23), None)
  assert_eq(normalize_timestamp_text(canonical, 0), None)
}
