///|
test "query time has a nonnullable Timestamp without a sampled literal" {
  assert_type(
    "{\"current_timestamp\":[]}", "{}", "null", "{\"type\":\"timestamp\",\"nullable\":false}",
  )
}
