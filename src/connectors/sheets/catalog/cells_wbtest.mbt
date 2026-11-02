///|
fn limits() -> Limits {
  { max_bytes: 65536, max_nodes: 4096, max_depth: 16, max_cells: 12, }
}

///|
fn columns() -> Array[Column] {
  [
    { name: "text", cell_type: Text, nullable: false, },
    { name: "number", cell_type: Number, nullable: true, },
    { name: "flag", cell_type: Boolean, nullable: true, },
  ]
}

///|
fn range() -> GridRange {
  { sheet_id: 7, start_row: 2, end_row: 6, start_column: 1, end_column: 4, }
}

///|
test "publication binds numeric grid identities rather than mutable titles" {
  let sheet : Json = {
    "properties": {
      "sheetId": 7,
      "sheetType": "GRID",
      "title": "mutable",
      "gridProperties": { "rowCount": 6, "columnCount": 4 },
    },
  }
  let body = @utf8.encode(
    ({ "spreadsheetId": "book", "sheets": [sheet] } : Json).stringify(),
  )
  assert_true(
    check_target(body, "book", range(), 7, columns(), limits()) is Ok(_),
  )
  let default_grid = @utf8.encode(
    (
      {
        "spreadsheetId": "book",
        "sheets": [
          {
            "properties": {
              "sheetId": 7,
              "gridProperties": { "rowCount": 6, "columnCount": 4 },
            },
          },
        ],
      } : Json).stringify(),
  )
  assert_true(
    check_target(default_grid, "book", range(), 7, columns(), limits()) is Ok(_),
  )
  assert_true(
    check_target(body, "other", range(), 7, columns(), limits())
    is Err(ForeignSpreadsheet),
  )
  assert_true(
    check_target(body, "book", range(), 8, columns(), limits())
    is Err(ForeignSheet),
  )
  assert_true(
    check_target(
      body,
      "book",
      { ..range(), end_column: 5, start_column: 2, },
      7,
      columns(),
      limits(),
    )
    is Err(ForeignRange),
  )
  let duplicate = @utf8.encode(
    ({ "spreadsheetId": "book", "sheets": [sheet, sheet] } : Json).stringify(),
  )
  assert_true(
    check_target(duplicate, "book", range(), 7, columns(), limits())
    is Err(InvalidResponse),
  )
  let non_grid = @utf8.encode(
    (
      {
        "spreadsheetId": "book",
        "sheets": [{ "properties": { "sheetId": 7, "sheetType": "OBJECT" } }],
      } : Json).stringify(),
  )
  assert_true(
    check_target(non_grid, "book", range(), 7, columns(), limits())
    is Err(InvalidResponse),
  )
}

///|
test "target private parse retains duplicate key numeric type and full syntax refusals" {
  for
    body in [
      "{\"spreadsheetId\":\"book\",\"sheets\":[],\"unused\":{\"x\":0,\"x\":1}}",
      "{\"spreadsheetId\":\"book\",\"sheets\":[]} trailing",
    ] {
    assert_true(
      check_target(@utf8.encode(body), "book", range(), 7, columns(), limits())
      is Err(InvalidResponse),
    )
  }
  for
    property in [
      "\"sheetId\":null", "\"sheetId\":7.5", "\"sheetId\":2147483648", "\"sheetId\":7,\"sheetType\":null",
    ] {
    let body = "{\"spreadsheetId\":\"book\",\"sheets\":[{\"properties\":{" +
      property +
      "}}]}"
    assert_true(
      check_target(@utf8.encode(body), "book", range(), 7, columns(), limits())
      is Err(InvalidResponse),
    )
  }
}

///|
fn grid(rows : Array[Json]) -> Bytes {
  @utf8.encode(
    (
      {
        "spreadsheetId": "book",
        "sheets": [
          {
            "properties": { "sheetId": 7 },
            "data": [
              { "startRow": 2, "startColumn": 1, "rowData": Json::array(rows) },
            ],
          },
        ],
      } : Json).stringify(),
  )
}

///|
test "typed effective cells preserve zero false empty text duplicates and blank exclusion" {
  let row : Json = {
    "values": [
      {
        "userEnteredValue": { "formulaValue": "=\"\"" },
        "effectiveValue": { "stringValue": "" },
      },
      { "effectiveValue": { "numberValue": 0 } },
      { "effectiveValue": { "boolValue": false } },
    ],
  }
  let page = project_grid(
    grid([{}, row, row]),
    "book",
    range(),
    columns(),
    limits(),
  ).unwrap()
  assert_eq(page_rows(page), [
    { "text": "", "number": 0, "flag": false },
    { "text": "", "number": 0, "flag": false },
  ])
  // The omitted last row is blank too, independently of nullable columns.
  assert_eq(excluded_blank_rows(page), 2)
}

///|
test "absent optional cells become null but present formula errors never do" {
  let page = project_grid(
    grid([
      {
        "values": [
          {
            "effectiveValue": { "stringValue": "é\r\n=literal" },
            "formattedValue": "not authoritative",
          },
        ],
      },
    ]),
    "book",
    range(),
    columns(),
    limits(),
  ).unwrap()
  assert_eq(page_rows(page), [
    { "text": "é\r\n=literal", "number": null, "flag": null },
  ])
  assert_true(
    project_grid(
      grid([{ "values": [{}, { "effectiveValue": { "numberValue": 1 } }] }]),
      "book",
      range(),
      columns(),
      limits(),
    )
    is Err(RequiredCell(row=2, column="text")),
  )
  assert_true(
    project_grid(
      grid([
        {
          "values": [
            {
              "effectiveValue": {
                "errorValue": { "type": "DIVIDE_BY_ZERO", "message": "private" },
              },
            },
          ],
        },
      ]),
      "book",
      range(),
      columns(),
      limits(),
    )
    is Err(CellError(row=2, column="text")),
  )
  assert_true(
    project_grid(
      grid([{ "values": [{ "userEnteredValue": { "formulaValue": "=\"\"" } }] }]),
      "book",
      range(),
      columns(),
      limits(),
    )
    is Err(MissingEffectiveValue(row=2, column="text")),
  )
}

///|
test "wrong cell union type and foreign range identity are refused" {
  assert_true(
    project_grid(
      grid([{ "values": [{ "effectiveValue": { "numberValue": 1 } }] }]),
      "book",
      range(),
      columns(),
      limits(),
    )
    is Err(InvalidCell(row=2, column="text")),
  )
  assert_true(
    project_grid(grid([]), "other", range(), columns(), limits())
    is Err(ForeignSpreadsheet),
  )
  let foreign = { ..range(), sheet_id: 8, }
  assert_true(
    project_grid(grid([]), "book", foreign, columns(), limits())
    is Err(ForeignSheet),
  )
  let shifted = { ..range(), start_row: 1, }
  assert_true(
    project_grid(grid([]), "book", shifted, columns(), {
      ..limits(),
      max_cells: 15,
    })
    is Err(ForeignRange),
  )
  assert_true(
    project_grid(
      grid([]),
      "book",
      range(),
      [columns()[0], columns()[0], columns()[2]],
      limits(),
    )
    is Err(InvalidSchema),
  )
  let malformed = @utf8.encode(
    "{\"spreadsheetId\":\"book\",\"spreadsheetId\":\"other\"}",
  )
  assert_true(
    project_grid(malformed, "book", range(), columns(), limits())
    is Err(InvalidResponse),
  )
}

///|
test "finite range and observed bytes admit exact limits and reject one short" {
  let body = grid([])
  assert_true(
    project_grid(body, "book", range(), columns(), {
      ..limits(),
      max_bytes: body.length(),
    })
    is Ok(_),
  )
  assert_true(
    project_grid(body, "book", range(), columns(), {
      ..limits(),
      max_bytes: body.length() - 1,
    })
    is Err(BudgetExceeded),
  )
  assert_true(read_request(range(), columns(), limits()) is Ok(_))
  assert_true(
    read_request(range(), columns(), { ..limits(), max_cells: 11, })
    is Err(BudgetExceeded),
  )
  let oversized = { ..range(), end_row: 2147483647, }
  assert_true(
    read_request(oversized, columns(), limits()) is Err(BudgetExceeded),
  )
}

///|
test "append literal cells preserve original text and reject unrepresentable values before send" {
  let body = append_request(7, columns(), ["=é\r\n", 0, false], limits()).unwrap()
  assert_eq(
    body,
    (
      {
        "requests": [
          {
            "appendCells": {
              "sheetId": 7,
              "rows": [
                {
                  "values": [
                    { "userEnteredValue": { "stringValue": "=é\r\n" } },
                    { "userEnteredValue": { "numberValue": 0 } },
                    { "userEnteredValue": { "boolValue": false } },
                  ],
                },
              ],
              "fields": "userEnteredValue",
            },
          },
        ],
      } : Json).stringify(),
  )
  for value in [Json::null(), Json::string("")] {
    assert_true(
      append_request(7, columns(), [value, 0, false], limits())
      is Err(UnrepresentableWrite("text")),
    )
  }
  assert_true(
    append_request(7, columns(), ["ok", null, false], limits())
    is Err(UnrepresentableWrite("number")),
  )
  let size = @utf8.encode(body).length()
  assert_true(
    append_request(7, columns(), ["=é\r\n", 0, false], {
      ..limits(),
      max_bytes: size,
    })
    is Ok(_),
  )
  assert_true(
    append_request(7, columns(), ["=é\r\n", 0, false], {
      ..limits(),
      max_bytes: size - 1,
    })
    is Err(BudgetExceeded),
  )
}

///|
test "only an exact batch acknowledgement proves append and never invents a row id" {
  let ack = @utf8.encode("{\"spreadsheetId\":\"book\",\"replies\":[{}]}")
  assert_eq(classify_append(200, ack, "book", limits()), Applied)
  for status in [0, 201, 400, 401, 403, 404, 429, 500, 503] {
    assert_eq(classify_append(status, ack, "book", limits()), Unknown)
  }
  assert_eq(classify_append(200, ack, "other", limits()), Unknown)
  for
    text in [
      "{}", "{\"spreadsheetId\":\"book\",\"replies\":[]}", "{\"spreadsheetId\":\"book\",\"replies\":[{},{}]}",
      "{\"spreadsheetId\":\"book\",\"replies\":[{\"id\":\"invented\"}]}",
    ] {
    assert_eq(
      classify_append(200, @utf8.encode(text), "book", limits()),
      Unknown,
    )
  }
}
