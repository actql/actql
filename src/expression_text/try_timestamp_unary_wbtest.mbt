///|
test "unary TRY_TIMESTAMP preserves the conversion node and distinct explicit pattern" {
  assert_tree(
    "try_timestamp($stamp)", "{\"try_timestamp\":{\"value\":{\"$param\":\"stamp\"}}}",
  )
  assert_tree(
    "try_timestamp(NULL)", "{\"try_timestamp\":{\"value\":{\"literal\":null}}}",
  )
  assert_tree(
    "try_timestamp(stamp,'yyyy-MM-dd')", "{\"try_timestamp\":{\"value\":{\"field\":\"stamp\"},\"pattern\":{\"literal\":\"yyyy-MM-dd\"}}}",
  )
}
