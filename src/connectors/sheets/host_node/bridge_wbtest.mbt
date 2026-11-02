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
test "append private parser keeps exact field names and original scalar refusals" {
  let columns = "[{\"name\":\"é\",\"type\":\"string\",\"nullable\":false}]"
  let accepted = sheets_append_request_json(
    columns, "{\"é\":\"same\"}", 7, 4096, 100, 12, 100,
  )
  assert_true(accepted.contains("body"))
  for
    row in [
      "{\"é\":\"same\"}", "{\"é\":1,\"é\":2}", "{\"é\":\"same\",\"extra\":0}",
      "{\"é\":",
    ] {
    let refused = sheets_append_request_json(
      columns, row, 7, 4096, 100, 12, 100,
    )
    assert_true(refused.contains("InvalidSchema"))
  }
  for row in ["{\"é\":[]}", "{\"é\":{}}"] {
    let refused = sheets_append_request_json(
      columns, row, 7, 4096, 100, 12, 100,
    )
    assert_true(refused.contains("UnrepresentableWrite"))
  }
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

///|
test "Sheets native append profile covers original escaped request and genuine absent GET output" {
  let columns = "[{\"name\":\"text\",\"type\":\"string\",\"nullable\":false}]"
  let original = sheets_append_construction_profile(
    @utf8.encode(columns).length(),
    1,
    4096,
    4096,
    8192,
    100,
    12,
  ).unwrap()
  assert_eq(original.length(), 4)
  let (empty, input, output) = original[1]
  assert_true(input is None && output is None)
  assert_eq(@execution.execution_capacity_retained_bytes(empty), 0L)
  assert_eq(@execution.execution_capacity_execution_bytes(empty), 0L)
  let row : Json = { "text": "\u{1}".repeat(128) + "é😀" }
  let exported = sheets_append_request_json(
    columns,
    row.stringify(),
    7,
    4096,
    100,
    12,
    100,
  )
  assert_true(@source.parse_json(exported, original[0].2.unwrap()) is Ok(_))
  assert_true(exported.contains("body"))
  let growth = sheets_append_construction_profile(
    @utf8.encode(columns).length(),
    1,
    8192,
    4096,
    8192,
    100,
    12,
  ).unwrap()
  assert_true(
    @execution.execution_capacity_retained_bytes(growth[0].0) >
    @execution.execution_capacity_retained_bytes(original[0].0),
  )
  assert_eq(
    @execution.execution_capacity_retained_bytes(growth[3].0),
    @execution.execution_capacity_retained_bytes(original[3].0),
  )
}

///|
test "Sheets append export byte bound covers controls quotes backslashes and original UTF8" {
  let columns = "[{\"name\":\"text\",\"type\":\"string\",\"nullable\":false}]"
  for
    text in [
      "\u{1}".repeat(128),
      "\"\\".repeat(128),
      "é😀é".repeat(128),
      "=SUM(A1:A2)",
    ] {
    let row : Json = { "text": text }
    let row = row.stringify()
    let profile = sheets_append_construction_profile(
      @utf8.encode(columns).length(),
      1,
      @utf8.encode(row).length(),
      32768,
      8192,
      1000,
      12,
    ).unwrap()
    let exported = sheets_append_request_json(
      columns, row, 7, 32768, 1000, 12, 100,
    )
    assert_true(exported.contains("body"))
    let quoted = profile[0].2.unwrap()
    assert_true(@utf8.encode(exported).length() <= quoted.max_input_bytes)
    assert_true(@source.parse_json(exported, quoted) is Ok(_))
  }
}

///|
test "Sheets constructor profile retains invalid input response and over-quota refusal paths" {
  let columns = "[{\"name\":\"text\",\"type\":\"string\",\"nullable\":false}]"
  let profile = sheets_append_construction_profile(
    @utf8.encode(columns).length(),
    1,
    4096,
    256,
    8192,
    100,
    12,
  ).unwrap()
  let row : Json = { "text": "x".repeat(256) }
  let refused = sheets_append_request_json(
    columns,
    row.stringify(),
    7,
    256,
    100,
    12,
    100,
  )
  assert_true(refused.contains("InvalidSchema"))
  assert_true(@source.parse_json(refused, profile[0].2.unwrap()) is Ok(_))
  for status in [200, 503] {
    let answer = sheets_append_outcome_json(
      status, b"{}", "book", 8192, 100, 12, 100,
    )
    assert_true(@source.parse_json(answer, profile[2].2.unwrap()) is Ok(_))
  }
  assert_true(sheets_append_construction_profile(1, 0, 1, 1, 1, 1, 1) is None)
  assert_true(sheets_append_construction_profile(1, 65, 1, 1, 1, 1, 1) is None)
  assert_true(
    sheets_append_construction_profile(1, 1, 2147483647, 1, 1, 1, 1) is None,
  )
}

///|
test "Sheets original native profile composes through the actual standard Host constructor owner" {
  let native = sheets_append_construction_profile(
    32768, 64, 1000000, 300000, 2000000, 200000, 32,
  )
  let combined = @client_host.installed_standard_create_constructor_capacities(
    native,
  ).unwrap()
  let original = native.unwrap()
  assert_eq(combined.length(), 4)
  assert_eq(@execution.execution_capacity_retained_bytes(combined[1]), 0L)
  for index in [0, 2, 3] {
    assert_true(
      @execution.execution_capacity_retained_bytes(combined[index]) >
      @execution.execution_capacity_retained_bytes(original[index].0),
    )
  }
  // These are constructor DATA quantities, not an admitted whole Run/Host,
  // native heap observation, minimum, cleanup report or performance target.
  for index, capacity in combined {
    println(
      "sheets-constructor[" +
      index.to_string() +
      "]=" +
      @execution.execution_capacity_retained_bytes(capacity).to_string() +
      "/" +
      @execution.execution_capacity_execution_bytes(capacity).to_string(),
    )
  }
}
