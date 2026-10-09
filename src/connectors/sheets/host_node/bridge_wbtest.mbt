///|
test "Sheets bridge preserves literal Unicode and never creates a formula cell" {
  let columns = "[{\"name\":\"text\",\"type\":\"string\",\"nullable\":false}]"
  let row = "{\"text\":\"=é\\r\\n\"}"
  let result = @json.parse(
    sheets_append_request_json(columns, row, 7, 4096, 100, 12, 100),
  ) catch {
    _ => fail("Expected JSON")
  }
  guard result is Object(object) && object.get("body") is Some(String(body)) else {
    fail("Expected a typed append request")
  }
  assert_true(body.contains("stringValue"))
  assert_false(body.contains("formulaValue"))
  assert_true(body.contains("=é\\r\\n"))
  let null_row = sheets_append_request_json(
    columns, "{\"text\":null}", 7, 4096, 100, 12, 100,
  )
  assert_true(null_row.contains("UnrepresentableWrite"))
  assert_true(
    sheets_append_request_json(
      columns, "{\"text\":\"\"}", 7, 4096, 100, 12, 100,
    ).contains("UnrepresentableWrite"),
  )
}

///|
test "Sheets bridge accepts only declared scalar columns and exact row fields" {
  let columns = "[{\"name\":\"count\",\"type\":\"number\",\"nullable\":false}]"
  for row in ["{}", "{\"count\":1,\"extra\":2}", "{\"count\":1,\"count\":2}"] {
    assert_true(
      sheets_append_request_json(columns, row, 7, 4096, 100, 12, 100).contains(
        "InvalidSchema",
      ),
    )
  }
  assert_true(
    sheets_append_request_json(columns, "{\"count\":{}}", 7, 4096, 100, 12, 100).contains(
      "UnrepresentableWrite",
    ),
  )
  assert_true(
    sheets_grid_request_json(
      columns.replace(old="number", new="timestamp"),
      7,
      0,
      2,
      0,
      1,
      4096,
      100,
      12,
      100,
    ).contains("InvalidSchema"),
  )
  assert_true(
    sheets_grid_request_json(columns, 7, 0, 2, 0, 1, 4096, 100, 12, 1).contains(
      "BudgetExceeded",
    ),
  )
}

///|
test "Sheets bridge reports an acknowledgement, never a row identifier" {
  let answer = @utf8.encode("{\"spreadsheetId\":\"book\",\"replies\":[{}]}")
  assert_eq(
    sheets_append_outcome_json(200, answer, "book", 4096, 100, 12, 100),
    "{\"outcome\":\"Applied\"}",
  )
  assert_eq(
    sheets_append_outcome_json(200, answer, "other", 4096, 100, 12, 100),
    "{\"outcome\":\"Unknown\"}",
  )
  assert_eq(
    sheets_append_outcome_json(503, answer, "book", 4096, 100, 12, 100),
    "{\"outcome\":\"Unknown\"}",
  )
}
