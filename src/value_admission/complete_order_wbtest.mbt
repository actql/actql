///|
fn order_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(
      text,
      { max_input_bytes: 1000, max_nodes: 100, max_depth: 20, },
      source_path="complete-order.json",
    ).unwrap(),
    {
      max_nodes: 100,
      max_depth: 20,
      max_string_bytes: 1000,
      max_total_string_bytes: 1000,
    },
  ).unwrap()
}

///|
fn order_checked(contract : @contract.Contract, text : String) -> CheckedValue {
  admit(contract, order_cursor(text), {
    max_nodes: 100,
    max_depth: 20,
    max_text_bytes: 1000,
  }).unwrap()
}

///|
test "complete order keys retain typed null and aggregate order" {
  let text = @contract.primitive(@contract.StringType, nullable=true)
  let array = @contract.array_contract(
    text,
    nullable=false,
    max_items=Some(10L),
  ).unwrap()
  let limits = { max_nodes: 100, max_depth: 20, max_text_bytes: 1000, }
  let first = order_checked(array, "[null,\"a\",\"b\"]")
  let second = order_checked(array, "[null,\"a\",\"c\"]")
  let first_key = complete_order_key(first, limits).unwrap()
  let repeated_key = complete_order_key(first, limits).unwrap()
  let second_key = complete_order_key(second, limits).unwrap()
  assert_eq(first_key, repeated_key)
  assert_true(@canonical.compare_utf16(first_key, second_key) < 0)
}

///|
test "complete order keys fail closed under their byte ceiling" {
  let text = @contract.primitive(@contract.StringType, nullable=false)
  let value = order_checked(text, "\"long\"")
  assert_eq(
    complete_order_key(value, {
      max_nodes: 10,
      max_depth: 2,
      max_text_bytes: 1,
    }),
    Err(CompleteOrderLimit),
  )
}

///|
test "complete order budget includes typed tags and JSON escaping" {
  let text = @contract.primitive(@contract.StringType, nullable=false)
  let value = order_checked(text, "\"\\\"\\\\x\"")
  let key = complete_order_key(value, {
    max_nodes: 1,
    max_depth: 1,
    max_text_bytes: 3,
  }).unwrap()
  assert_true(key.contains("text"))
  assert_true(key.length() > 3)
}
