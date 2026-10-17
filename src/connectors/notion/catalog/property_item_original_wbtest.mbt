///|
test "Notion copied pagination control cannot upgrade an incomplete original" {
  let (binding, _, request) = property_test_setup(
    "rich_text", "{\"type\":\"string\",\"nullable\":false}",
  )
  let first = project_notion_property_item_page(
    request,
    property_test_page(
      "rich_text",
      property_test_item("rich_text", property_test_text("\"partial\"")),
      "\"next\"",
    ),
  ).unwrap()
  assert_true(!notion_property_item_page_complete(first))
  // Whitebox construction models copied FFI control data, not a vendor reply.
  // The original response still requires another request; no partial cell may
  // become complete merely by changing the copied pagination flag.
  let copied = { ..first, next_cursor: None, }
  assert_eq(
    admit_notion_completed_property(binding, copied, 0, cell_test_limits()).unwrap_err(),
    ForeignOriginal,
  )
}

///|
test "Notion property requests and terminal pages retain their issued identity" {
  let (binding, row, request) = property_test_setup(
    "rich_text", "{\"type\":\"string\",\"nullable\":false}",
  )
  let copied_request = { ..request, cursor: request.cursor, }
  assert_true(!notion_property_item_request_matches(copied_request, row, 0))
  assert_true(
    !notion_property_item_request_matches_binding(copied_request, binding, 0),
  )
  assert_eq(
    notion_property_item_request_wire(copied_request, 256, 8, 4).unwrap_err(),
    ForeignOriginal,
  )
  let response = property_test_page("rich_text", "", "null")
  assert_eq(
    project_notion_property_item_page(copied_request, response).unwrap_err(),
    ForeignOriginal,
  )
  let terminal = project_notion_property_item_page(request, response).unwrap()
  let copied_page = { ..terminal, next_cursor: terminal.next_cursor, }
  assert_true(notion_property_item_page_complete(terminal))
  assert_true(!notion_property_item_page_complete(copied_page))
  assert_true(next_notion_property_item_request(copied_page) is None)
  assert_eq(
    notion_property_item_page_original(copied_page).unwrap_err(),
    ForeignOriginal,
  )
  assert_eq(
    notion_property_item_page_original_wire(copied_page, 8192).unwrap_err(),
    ForeignOriginal,
  )
  assert_eq(
    admit_notion_completed_property(binding, copied_page, 0, cell_test_limits()).unwrap_err(),
    ForeignOriginal,
  )
  let (value, _, _) = admit_notion_completed_property(
    binding,
    terminal,
    0,
    cell_test_limits(),
  ).unwrap()
  assert_eq(@admitted.canonical_scalar_text(value, 16), Some(""))
}
