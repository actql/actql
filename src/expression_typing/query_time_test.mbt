///|
test "query time has a nonnullable Timestamp without a sampled literal" {
  assert_type(
    "{\"current_timestamp\":[]}", "{}", "null", "{\"type\":\"timestamp\",\"nullable\":false}",
  )
}

///|
test "current date has a nonnullable Date without sampling the clock" {
  assert_type(
    "{\"current_date\":[]}", "{}", "null", "{\"type\":\"date\",\"nullable\":false}",
  )
}
