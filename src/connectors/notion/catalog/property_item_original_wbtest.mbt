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
  let copied = { ..first, next_cursor: None }
  assert_eq(
    admit_notion_completed_property(binding, copied, 0, cell_test_limits()).unwrap_err(),
    ForeignOriginal,
  )
}
