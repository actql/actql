///|
test "DECIMAL_DIVIDE NULL receives original explicit target and peer contexts" {
  for
    text in [
      "decimal_divide(NULL,2,4,2,'half_even')", "decimal_divide(CAST('1' AS DECIMAL(6,2)),NULL,4,2,'half_even')",
      "decimal_divide(NULL,NULL,4,2,'half_even')",
    ] {
    assert_type(
      "\"" + text + "\"",
      "{}",
      "null",
      "{\"type\":\"decimal\",\"nullable\":true,\"precision\":4,\"scale\":2}",
    )
  }
}
