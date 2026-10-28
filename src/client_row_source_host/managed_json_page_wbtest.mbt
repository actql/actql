///|
test "managed JSON page keeps exact original selected row wire and cursor DATA" {
  let rows = "[ {\"wide\":9007199254740993,\"negative\":-0,\"é\":\"é\"} ]"
  let body = @utf8.encode(
    "{\"data\":{\"items\":" + rows + "},\"next\":\"é\"}",
  )
  let page = project_managed_json_page(
    body,
    ["data", "items"],
    Some(["next"]),
    1024,
    64,
    4,
    1,
    8,
  ).unwrap()
  assert_eq(managed_json_page_rows_wire(page), rows)
  assert_eq(managed_json_page_row_count(page), 1)
  assert_eq(managed_json_page_next_cursor(page), Some("é"))
}

///|
test "managed JSON page retains existing duplicate UTF8 and whole-body parser refusal" {
  for
    body in [
      b"{\"items\":[],\"items\":[1]}", b"{\"items\":[],\"ignored\":{\"a\":1,\"a\":2}}",
      b"{\"items\":[],\"ignored\":\"\xff\"}", b"{\"items\":[]} trailing",
    ] {
    assert_true(
      project_managed_json_page(body, ["items"], None, 1024, 64, 4, 2, 8)
      is Err(Parse(_)),
    )
  }
}

///|
test "managed JSON page refuses shape and bounds without manufacturing defaults" {
  assert_true(
    project_managed_json_page(b"{}", ["items"], None, 64, 16, 2, 2, 8)
    is Err(ItemsPath),
  )
  assert_true(
    project_managed_json_page(
      b"{\"items\":{}}",
      ["items"],
      None,
      64,
      16,
      2,
      2,
      8,
    )
    is Err(ItemsShape),
  )
  assert_true(
    project_managed_json_page(b"[1,2]", [], None, 64, 16, 2, 1, 8)
    is Err(RowLimit),
  )
  assert_true(
    project_managed_json_page(
      b"{\"items\":[],\"next\":1}",
      ["items"],
      Some(["next"]),
      64,
      16,
      2,
      2,
      8,
    )
    is Err(CursorShape),
  )
  assert_true(
    project_managed_json_page(
      b"{\"items\":[],\"next\":\"abc\"}",
      ["items"],
      Some(["next"]),
      64,
      16,
      2,
      2,
      2,
    )
    is Err(CursorLimit),
  )
}

///|
test "managed JSON page supports empty root arrays and exact empty cursors" {
  let root = project_managed_json_page(b"[]", [], None, 2, 1, 1, 0, 0).unwrap()
  assert_eq(managed_json_page_rows_wire(root), "[]")
  assert_eq(managed_json_page_row_count(root), 0)
  assert_eq(managed_json_page_next_cursor(root), None)
  let page = project_managed_json_page(
    b"{\"items\":[],\"next\":\"\"}",
    ["items"],
    Some(["next"]),
    64,
    8,
    2,
    0,
    0,
  ).unwrap()
  assert_eq(managed_json_page_next_cursor(page), Some(""))
}
