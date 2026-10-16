///|
test "record page wire retains exact decimal and temporal contracts through Common emission" {
  let observed = page(
    (
      #|{"results":[{"id":"9007199254740993","archived":false,"properties":{"name":"ACME","amount":"9007199254740993.01","live":"false","tags":"a;b","day":"8640000000","instant":"-1"}}]}
    ),
    ["name", "amount", "live", "tags", "day", "instant"],
  ).unwrap()
  let expected =
    #|[{"id":"9007199254740993","name":"ACME","amount":"9007199254740993.0100000000","live":false,"tags":["a","b"],"day":"1970-04-11","instant":"1969-12-31T23:59:59.999Z"}]
  assert_eq(object_page_row_count(observed), 1)
  assert_eq(encode_object_page_rows(observed, 4096, 100, 10), Ok(expected))
  // Emission is a projection of the same original, not destructive admission.
  assert_eq(encode_object_page_rows(observed, 4096, 100, 10), Ok(expected))
  assert_eq(object_page_rows(observed)[0].id, "9007199254740993")
}

///|
test "record row output byte bound is exact and separate from provider input bounds" {
  let observed = page(
    "{\"results\":[{\"id\":\"1\",\"archived\":false,\"properties\":{\"amount\":\"1\"}}]}",
    ["amount"],
  ).unwrap()
  let expected = "[{\"id\":\"1\",\"amount\":\"1.0000000000\"}]"
  let bytes = @utf8.encode(expected).length()
  assert_eq(encode_object_page_rows(observed, bytes, 10, 10), Ok(expected))
  assert_eq(
    encode_object_page_rows(observed, bytes - 1, 10, 10),
    Err(BudgetExceeded),
  )
  assert_eq(
    encode_object_page_rows(observed, bytes, 1, 10),
    Err(BudgetExceeded),
  )
  assert_eq(
    encode_object_page_rows(observed, bytes, 10, 1),
    Err(BudgetExceeded),
  )
  for caps in [(0, 10, 10), (bytes, 0, 10), (bytes, 10, 0)] {
    assert_eq(
      encode_object_page_rows(observed, caps.0, caps.1, caps.2),
      Err(InvalidLimits),
    )
  }
}

///|
test "record row wire retains Unicode escapes null and empty cells without a partial envelope" {
  let observed = page(
    (
      #|{"results":[{"id":"é😀","archived":false,"properties":{"name":"line\n\"é😀","amount":null,"tags":""}}]}
    ),
    ["name", "amount", "tags"],
  ).unwrap()
  let expected =
    #|[{"id":"é😀","name":"line\n\"é😀","amount":null,"tags":[]}]
  assert_eq(encode_object_page_rows(observed, 4096, 100, 10), Ok(expected))
  let empty = page("{\"results\":[]}", ["amount"]).unwrap()
  assert_eq(object_page_row_count(empty), 0)
  assert_eq(encode_object_page_rows(empty, 2, 1, 1), Ok("[]"))
}

///|
test "record property cannot replace the original top level record key" {
  let properties = catalog(
    (
      #|{"results":[{"name":"id","type":"string","fieldType":"text"}]}
    ),
  )
  let observed = project_object_page(
    @utf8.encode(
      "{\"results\":[{\"id\":\"original\",\"archived\":false,\"properties\":{\"id\":\"replacement\"}}]}",
    ),
    properties,
    ["id"],
    page_limits(),
  ).unwrap()
  assert_eq(
    encode_object_page_rows(observed, 4096, 100, 10),
    Err(DuplicateSelection("id")),
  )
  assert_eq(object_page_rows(observed)[0].id, "original")
}
