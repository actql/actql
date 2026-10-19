///|
test "QUANTIZE NULL retains original explicit Decimal context" {
  assert_type(
    "\"quantize(NULL,4,2,'half_even')\"", "{}", "null", "{\"type\":\"decimal\",\"nullable\":true,\"precision\":4,\"scale\":2}",
  )
}
