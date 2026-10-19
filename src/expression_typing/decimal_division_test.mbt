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

///|
test "exact division public result and literal NULL contexts never promote real inputs" {
  for
    source in [
      "decimal_divide(NULL,2,3)", "decimal_divide(CAST('1' AS DECIMAL(1,0)),NULL,3)",
      "decimal_divide(NULL,NULL,3)",
    ] {
    assert_type(
      "\"" + source + "\"",
      "{}",
      "null",
      "{\"type\":\"decimal\",\"nullable\":true,\"precision\":38,\"scale\":3}",
    )
  }
  assert_type(
    "\"decimal_divide(CAST('1' AS DECIMAL(1,0)),8,3)\"", "{}", "null", "{\"type\":\"decimal\",\"nullable\":false,\"precision\":38,\"scale\":3}",
  )
}
