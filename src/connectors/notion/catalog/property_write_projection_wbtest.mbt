///|
test "Notion people writes reject 101 supplied users at the actual vendor request boundary" {
  let value = write_test_value(
    "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"string\",\"nullable\":false}}",
    "[" + Array::make(101, "\"user\"").join(",") + "]",
  )
  assert_eq(
    prepare_notion_property_write(write_test_source("people"), 0, value, {
      ..write_test_limits(),
      max_items: 101,
    }).unwrap_err(),
    BudgetExceeded,
  )
}

///|
test "Notion people and relation writes retain vendor100 and stricter original supplied bounds" {
  let value = write_test_value(
    "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"string\",\"nullable\":false}}",
    "[" + Array::make(100, "\"user\"").join(",") + "]",
  )
  for kind in ["people", "relation"] {
    let source = write_test_source(kind)
    assert_true(
      prepare_notion_property_write(source, 0, value, write_test_limits())
      is Ok(_),
    )
    assert_eq(
      prepare_notion_property_write(source, 0, value, {
        ..write_test_limits(),
        max_items: 99,
      }).unwrap_err(),
      BudgetExceeded,
    )
  }
}
