///|
test "TRY_DECIMAL NULL uses its original explicit Decimal target context" {
  assert_type(
    "\"try_decimal(NULL,4,2)\"", "{}", "null", "{\"type\":\"decimal\",\"nullable\":true,\"precision\":4,\"scale\":2}",
  )
  assert_type(
    "\"try_decimal(CAST(NULL AS STRING),4,2)\"", "{}", "null", "{\"type\":\"decimal\",\"nullable\":true,\"precision\":4,\"scale\":2}",
  )
}
