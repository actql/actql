///|
test "Timestamp conversion preserves the original nullable contract without widening strict binding" {
  for nullable in [false, true] {
    let original = @contract.primitive(@contract.TimestampType, nullable~)
    for text in ["2026-01-02T03:04:05.123Z", "2026-01-02T03:04:05.123456789Z"] {
      let checked = checked_timestamp_conversion(text, original).unwrap()
      assert_true(physical_equal(checked.contract, original))
      assert_true(checked.value is Timestamp(actual) && actual == text)
      assert_eq(checked_timestamp_value(text, original) is Some(_), !nullable)
    }
    for text in ["2026-01-02T03:04:05Z", "2026-01-02 03:04:05+00"] {
      assert_true(checked_timestamp_conversion(text, original) is None)
    }
  }
  let other = @contract.primitive(@contract.StringType, nullable=false)
  assert_true(
    checked_timestamp_conversion("2026-01-02T03:04:05.123Z", other) is None,
  )
}
