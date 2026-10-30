///|
fn tabs_error(value : Result[SheetTabsPage, SheetTabsIssue]) -> SheetTabsIssue {
  match value {
    Err(issue) => issue
    Ok(_) => abort("expected original Sheets tab refusal")
  }
}

///|
fn tabs_limits() -> SheetTabsLimits {
  { max_bytes: 16384, max_nodes: 512, max_depth: 16, max_rows: 4,
    max_value_nodes: 100, max_value_text_bytes: 4096, }
}

///|
fn tabs_original() -> String {
  #|{"spreadsheetId":"book","sheets":[{"properties":{"sheetId":0,"title":"é\r\n😀","index":0,"gridProperties":{"rowCount":100,"columnCount":3}}},{"properties":{"sheetId":2147483647,"title":"Chart","index":1,"sheetType":"OBJECT"}},{"properties":{"sheetId":3,"title":"Data","index":2,"sheetType":"DATA_SOURCE","gridProperties":{"rowCount":0,"columnCount":1}}}]}
}

///|
test "Sheets tabs preserve all tab kinds original identities exact titles and typed full rows" {
  let original = tabs_original()
  let page = project_sheet_tabs(@utf8.encode(original), "book", tabs_limits()).unwrap()
  assert_eq(page.response_sha256, @sha.hex(@utf8.encode(original)))
  assert_eq(page.spreadsheet_id, "book")
  assert_eq(sheet_tabs_row_count(page), 3)
  assert_eq(sheet_tabs_rows_wire(page, sheet_tabs_column_names(), 8192, 100, 8).unwrap(),
    #|[{"id":"0","title":"é\r\n😀","index":"0","row_count":"100","column_count":"3"},{"id":"2147483647","title":"Chart","index":"1","row_count":null,"column_count":null},{"id":"3","title":"Data","index":"2","row_count":"0","column_count":"1"}]
  )
  let schema = sheet_tabs_schema_wire(4096, 100, 8).unwrap()
  assert_true(schema.contains("\"id\":{\"nullable\":false,\"type\":\"int64\"}"))
  assert_true(schema.contains("\"row_count\":{\"nullable\":true,\"type\":\"int64\"}"))
  assert_true(schema.contains("\"title\":{\"nullable\":false,\"type\":\"string\"}"))
}

///|
test "Sheets tabs reject original numeric fractions foreign identity duplicates and absent selected cells" {
  let original = tabs_original()
  for token in ["-1", "2147483648", "0.999999999999999999999", "null", "\"0\"", "true"] {
    assert_eq(tabs_error(project_sheet_tabs(@utf8.encode(original.replace(old="\"sheetId\":0", new="\"sheetId\":" + token)), "book", tabs_limits())), InvalidCell("id"))
  }
  assert_eq(tabs_error(project_sheet_tabs(@utf8.encode(original), "foreign", tabs_limits())), ForeignSpreadsheet)
  assert_eq(tabs_error(project_sheet_tabs(@utf8.encode(original.replace(old="\"sheetId\":3", new="\"sheetId\":0")), "book", tabs_limits())), DuplicateSheet(0))
  for token in ["null", "-1", "1.5", "\"1\""] {
    assert_eq(tabs_error(project_sheet_tabs(@utf8.encode(original.replace(old="\"rowCount\":100", new="\"rowCount\":" + token)), "book", tabs_limits())), InvalidCell("row_count"))
  }
  assert_eq(tabs_error(project_sheet_tabs(@utf8.encode(original.replace(old="\"title\":\"Chart\",", new="")), "book", tabs_limits())), InvalidCell("title"))
}

///|
test "Sheets tabs bound whole inventory typed material and final output before selection" {
  let original = @utf8.encode(tabs_original())
  let limits = tabs_limits()
  assert_eq(tabs_error(project_sheet_tabs(original, "book", { ..limits, max_rows: 2 })), BudgetExceeded)
  assert_eq(tabs_error(project_sheet_tabs(original, "book", { ..limits, max_value_nodes: 14 })), BudgetExceeded)
  assert_eq(tabs_error(project_sheet_tabs(original, "book", { ..limits, max_bytes: original.length() - 1 })), BudgetExceeded)
  let page = project_sheet_tabs(original, "book", limits).unwrap()
  assert_eq(sheet_tabs_rows_wire(page, ["title", "title"], 8192, 100, 8), Err(InvalidSelection("title")))
  assert_eq(sheet_tabs_rows_wire(page, ["foreign"], 8192, 100, 8), Err(InvalidSelection("foreign")))
  assert_eq(sheet_tabs_rows_wire(page, ["title"], 1, 100, 8), Err(BudgetExceeded))
  assert_eq(sheet_tabs_row_count(project_sheet_tabs(b"{\"spreadsheetId\":\"book\"}", "book", limits).unwrap()), 0)
  assert_eq(tabs_error(project_sheet_tabs(b"{\"spreadsheetId\":\"book\",\"sheets\":null}", "book", limits)), ForeignSpreadsheet)
}
