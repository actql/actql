///|
fn update_columns_wire() -> String {
  "[{\"name\":\"text\",\"type\":\"string\",\"nullable\":false},{\"name\":\"flag\",\"type\":\"boolean\",\"nullable\":true}]"
}

///|
fn update_wire(rows : String) -> String {
  sheets_update_request_json(
    update_columns_wire(),
    rows,
    7,
    2,
    4,
    1,
    3,
    65536,
    4096,
    16,
    4,
  )
}

///|
test "Sheets update bridge uses declared column order and preserves literal text" {
  let result = @json.parse(
    update_wire(
      "[{\"flag\":false,\"text\":\"=é\\r\\n\"},{\"text\":\"second\",\"flag\":true}]",
    ),
  ) catch {
    _ => fail("Expected JSON")
  }
  guard result is Object(object) && object.get("body") is Some(String(body)) else {
    fail("Expected a typed range request")
  }
  let expected : Json = {
    "requests": [
      {
        "updateCells": {
          "range": {
            "sheetId": 7,
            "startRowIndex": 2,
            "endRowIndex": 4,
            "startColumnIndex": 1,
            "endColumnIndex": 3,
          },
          "rows": [
            {
              "values": [
                { "userEnteredValue": { "stringValue": "=é\r\n" } },
                { "userEnteredValue": { "boolValue": false } },
              ],
            },
            {
              "values": [
                { "userEnteredValue": { "stringValue": "second" } },
                { "userEnteredValue": { "boolValue": true } },
              ],
            },
          ],
          "fields": "userEnteredValue",
        },
      },
    ],
  }
  assert_eq(body, expected.stringify())
}

///|
test "Sheets update bridge refuses open duplicate missing or malformed input rows" {
  for
    rows in [
      "{}", "[null]", "[[]]", "[{\"text\":\"a\"}]", "[{\"text\":\"a\",\"flag\":true,\"extra\":1}]",
      "[{\"text\":\"a\",\"text\":\"b\",\"flag\":true}]", "[{\"text\":\"a\",\"flag\":true}",
    ] {
    assert_true(update_wire(rows).contains("InvalidSchema"))
  }
  for
    rows in [
      "[]", "[{\"text\":\"a\",\"flag\":true}]", "[{\"text\":\"a\",\"flag\":true},{\"text\":\"b\",\"flag\":true},{\"text\":\"c\",\"flag\":true}]",
    ] {
    assert_true(update_wire(rows).contains("InvalidRange"))
  }
}

///|
test "Sheets update bridge refuses clear-like values and nested cells" {
  for
    rows in [
      "[{\"text\":null,\"flag\":true},{\"text\":\"b\",\"flag\":true}]", "[{\"text\":\"\",\"flag\":true},{\"text\":\"b\",\"flag\":true}]",
      "[{\"text\":{},\"flag\":true},{\"text\":\"b\",\"flag\":true}]", "[{\"text\":\"a\",\"flag\":null},{\"text\":\"b\",\"flag\":true}]",
      "[{\"text\":\"a\",\"flag\":[]},{\"text\":\"b\",\"flag\":true}]",
    ] {
    assert_true(update_wire(rows).contains("UnrepresentableWrite"))
  }
}
