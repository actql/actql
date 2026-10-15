///|
fn update_range() -> GridRange {
  { sheet_id: 7, start_row: 2, end_row: 4, start_column: 1, end_column: 4, }
}

///|
fn update_rows() -> Array[Array[Json]] {
  [["=é\r\n", 0, false], ["second", -2.5, true]]
}

///|
test "range overwrite preserves exact coordinates literal cells and column order" {
  let actual = update_request(
    update_range(),
    columns(),
    update_rows(),
    limits(),
  ).unwrap()
  // This independent API body deliberately supplies every cell of B3:D4.
  let expected : Json = {
    "requests": [
      {
        "updateCells": {
          "range": {
            "sheetId": 7,
            "startRowIndex": 2,
            "endRowIndex": 4,
            "startColumnIndex": 1,
            "endColumnIndex": 4,
          },
          "rows": [
            {
              "values": [
                { "userEnteredValue": { "stringValue": "=é\r\n" } },
                { "userEnteredValue": { "numberValue": 0 } },
                { "userEnteredValue": { "boolValue": false } },
              ],
            },
            {
              "values": [
                { "userEnteredValue": { "stringValue": "second" } },
                { "userEnteredValue": { "numberValue": -2.5 } },
                { "userEnteredValue": { "boolValue": true } },
              ],
            },
          ],
          "fields": "userEnteredValue",
        },
      },
    ],
  }
  assert_eq(actual, expected.stringify())
  assert_false(actual.contains("formulaValue"))
  assert_false(actual.contains("appendCells"))
}

///|
test "range overwrite refuses missing or excess rows and cells instead of clearing" {
  for rows in [[], [update_rows()[0]], [..update_rows(), update_rows()[0]]] {
    assert_true(
      update_request(update_range(), columns(), rows, limits())
      is Err(InvalidRange),
    )
  }
  for row in [[], ["only text"], ["text", 1, false, "extra"]] {
    assert_true(
      update_request(
        update_range(),
        columns(),
        [update_rows()[0], row],
        limits(),
      )
      is Err(InvalidSchema),
    )
  }
}

///|
test "range overwrite refuses null empty text wrong types and structured cells" {
  for row in [[null, 1, false], ["", 1, false], [1, 1, false], [{}, 1, false]] {
    assert_true(
      update_request(
        update_range(),
        columns(),
        [row, update_rows()[1]],
        limits(),
      )
      is Err(UnrepresentableWrite("text")),
    )
  }
  // Nullable read columns do not silently become clear operations on write.
  for row in [["text", null, false], ["text", true, false], ["text", [], false]] {
    assert_true(
      update_request(
        update_range(),
        columns(),
        [row, update_rows()[1]],
        limits(),
      )
      is Err(UnrepresentableWrite("number")),
    )
  }
  for row in [["text", 1, null], ["text", 1, "false"], ["text", 1, 0]] {
    assert_true(
      update_request(
        update_range(),
        columns(),
        [row, update_rows()[1]],
        limits(),
      )
      is Err(UnrepresentableWrite("flag")),
    )
  }
}

///|
test "range overwrite validates schema and rejects invalid or overflowing rectangles" {
  for
    range in [
      { ..update_range(), sheet_id: -1, },
      { ..update_range(), start_row: -1, },
      { ..update_range(), start_column: -1, },
      { ..update_range(), end_row: 2, },
      { ..update_range(), end_column: 1, },
      { ..update_range(), end_column: 5, },
    ] {
    assert_true(
      update_request(range, columns(), update_rows(), limits())
      is Err(InvalidRange),
    )
  }
  assert_true(
    update_request(
      { ..update_range(), end_row: 2147483647, },
      columns(),
      update_rows(),
      limits(),
    )
    is Err(BudgetExceeded),
  )
  assert_true(
    update_request(update_range(), [], update_rows(), limits())
    is Err(InvalidSchema),
  )
  assert_true(
    update_request(
      update_range(),
      [columns()[0], columns()[0], columns()[2]],
      update_rows(),
      limits(),
    )
    is Err(InvalidSchema),
  )
}

///|
test "range overwrite charges the full rectangle and complete outgoing envelope" {
  assert_true(
    update_request(update_range(), columns(), update_rows(), {
      ..limits(),
      max_cells: 6,
    })
    is Ok(_),
  )
  assert_true(
    update_request(update_range(), columns(), update_rows(), {
      ..limits(),
      max_cells: 5,
    })
    is Err(BudgetExceeded),
  )
  let body = update_request(update_range(), columns(), update_rows(), limits()).unwrap()
  let size = @utf8.encode(body).length()
  assert_true(
    update_request(update_range(), columns(), update_rows(), {
      ..limits(),
      max_bytes: size,
    })
    is Ok(_),
  )
  for
    limits in [
      { ..limits(), max_bytes: size - 1, },
      { ..limits(), max_nodes: 12, },
      { ..limits(), max_depth: 3, },
    ] {
    assert_true(
      update_request(update_range(), columns(), update_rows(), limits)
      is Err(BudgetExceeded),
    )
  }
  assert_true(
    update_request(update_range(), columns(), update_rows(), {
      ..limits(),
      max_cells: 0,
    })
    is Err(InvalidLimits),
  )
}
