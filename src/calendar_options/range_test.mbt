///|
test "Calendar bound range uses original canonical domain and chronological order" {
  assert_eq(
    validate_range("2000-01-01T00:00:00.000Z", "2000-01-01T00:00:00.000Z"),
    Ok(()),
  )
  assert_eq(
    validate_range("0001-01-01T00:00:00.000Z", "9999-12-31T23:59:59.999Z"),
    Ok(()),
  )
  assert_eq(
    validate_range("0000-01-01T00:00:00.000Z", "2000-01-01T00:00:00.000Z"),
    Err(InvalidTimestamp),
  )
  assert_eq(
    validate_range("2000-01-01T00:00:00Z", "2000-01-02T00:00:00.000Z"),
    Err(InvalidTimestamp),
  )
  assert_eq(
    validate_range("2000-01-02T00:00:00.000Z", "2000-01-01T00:00:00.000Z"),
    Err(ReversedRange),
  )
}
