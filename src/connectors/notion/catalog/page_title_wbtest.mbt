///|
fn title_test_wire(properties : String) -> String {
  page_test_wire("{\"type\":\"workspace\",\"workspace\":true}").replace_all(
    old="{\"Title\":{\"id\":\"title\",\"type\":\"title\",\"title\":[]}}",
    new=properties,
  )
}

///|
fn title_test_page() -> OriginalNotionPage {
  project_notion_page(
    @utf8.encode(
      title_test_wire(
        "{\"Not a title name\":{\"id\":\"v\",\"type\":\"title\",\"title\":[]}}",
      ),
    ),
    "p",
    page_test_limits(),
  ).unwrap()
}

///|
test "Notion exact-page title follows the original property chain without a data-source row" {
  let page = title_test_page()
  assert_eq(page.parent, Workspace)
  let request = start_notion_page_title_property_item_request(
    page,
    property_test_limits(),
  ).unwrap()
  assert_true(notion_property_item_request_matches_page_title(request, page))
  assert_eq(
    notion_property_item_request_wire(request, 128, 8, 4),
    Ok("{\"pageId\":\"p\",\"propertyId\":\"v\",\"cursor\":null}"),
  )
  let first = project_notion_property_item_page(
    request,
    property_test_page(
      "title",
      property_test_item("title", property_test_text("\"é\\r\\n\"")),
      "\"next\"",
    ),
  ).unwrap()
  assert_eq(
    admit_notion_completed_page_title(page, first, cell_test_limits()).unwrap_err(),
    Incomplete,
  )
  let next = next_notion_property_item_request(first).unwrap()
  assert_true(notion_property_item_request_matches_page_title(next, page))
  let terminal = project_notion_property_item_page(
    next,
    property_test_page(
      "title",
      property_test_item("title", property_test_text("\"😀\"")),
      "null",
    ),
  ).unwrap()
  let (value, nodes, bytes) = admit_notion_completed_page_title(
    page,
    terminal,
    cell_test_limits(),
  ).unwrap()
  assert_eq(@admitted.canonical_scalar_text(value, 64), Some("é\r\n😀"))
  assert_eq(nodes, 1)
  assert_eq(bytes, 9)
  assert_eq(
    notion_completed_page_title_wire(
      page,
      terminal,
      cell_test_limits(),
      64,
      8,
      4,
    ),
    Ok("\"é\\r\\n😀\""),
  )
}

///|
test "Notion exact-page title refuses copied and equal newly admitted originals" {
  let page = title_test_page()
  let request = start_notion_page_title_property_item_request(
    page,
    property_test_limits(),
  ).unwrap()
  let other = title_test_page()
  let copy = { ..page, id: page.id, }
  assert_true(!notion_property_item_request_matches_page_title(request, other))
  assert_true(!notion_property_item_request_matches_page_title(request, copy))
  assert_eq(
    start_notion_page_title_property_item_request(copy, property_test_limits()).unwrap_err(),
    ForeignOriginal,
  )
  let terminal = project_notion_property_item_page(
    request,
    property_test_page("title", "", "null"),
  ).unwrap()
  assert_eq(
    admit_notion_completed_page_title(other, terminal, cell_test_limits()).unwrap_err(),
    ForeignOriginal,
  )
  let copied_request = { ..request, cursor: None, }
  assert_true(
    !notion_property_item_request_matches_page_title(copied_request, page),
  )
  let copied_terminal = { ..terminal, next_cursor: None, }
  assert_eq(
    admit_notion_completed_page_title(page, copied_terminal, cell_test_limits()).unwrap_err(),
    ForeignOriginal,
  )
}

///|
test "Notion title and data-source property origins cannot substitute for one another" {
  let page = title_test_page()
  let (binding, row, query_request) = property_test_setup(
    "title", "{\"type\":\"string\",\"nullable\":false}",
  )
  let title_request = start_notion_page_title_property_item_request(
    page,
    property_test_limits(),
  ).unwrap()
  assert_true(
    !notion_property_item_request_matches_page_title(query_request, page),
  )
  assert_true(!notion_property_item_request_matches(title_request, row, 0))
  assert_true(
    !notion_property_item_request_matches_binding(title_request, binding, 0),
  )
  let terminal = project_notion_property_item_page(
    title_request,
    property_test_page("title", "", "null"),
  ).unwrap()
  assert_eq(
    admit_notion_completed_property(binding, terminal, 0, cell_test_limits()).unwrap_err(),
    ForeignOriginal,
  )
  assert_eq(
    notion_completed_page_title_wire(
      page,
      terminal,
      cell_test_limits(),
      8,
      2,
      2,
    ),
    Ok("\"\""),
  )
}

///|
test "Notion title selection checks all actual property occurrences and never chooses by name" {
  for
    properties in [
      "{}", "{\"Title\":{\"id\":\"v\",\"type\":\"rich_text\",\"rich_text\":[]}}",
      "{\"a\":{\"id\":\"v\",\"type\":\"title\",\"title\":[]},\"b\":{\"id\":\"b\",\"type\":\"title\",\"title\":[]}}",
      "{\"a\":{\"id\":\"v\",\"type\":\"title\",\"title\":null}}", "{\"a\":{\"id\":\"v\",\"type\":\"title\",\"title\":[]},\"b\":{\"id\":\"b\"}}",
    ] {
    let page = project_notion_page(
      @utf8.encode(title_test_wire(properties)),
      "p",
      page_test_limits(),
    ).unwrap()
    assert_eq(
      start_notion_page_title_property_item_request(
        page,
        property_test_limits(),
      ).unwrap_err(),
      InvalidSelection,
    )
  }
}

///|
test "Notion title scan work and identity bounds reject before issuing a request" {
  let page = title_test_page()
  let limits = property_test_limits()
  let exact = { ..limits, max_work: page.raw.length() + 2, }
  let request = start_notion_page_title_property_item_request(page, exact).unwrap()
  assert_eq(request.limits.max_work, 1)
  assert_eq(
    start_notion_page_title_property_item_request(page, {
      ..exact,
      max_work: exact.max_work - 1,
    }).unwrap_err(),
    BudgetExceeded,
  )
  assert_eq(
    start_notion_page_title_property_item_request(page, {
      ..limits,
      metadata: { ..limits.metadata, max_properties: 0, },
    }).unwrap_err(),
    BudgetExceeded,
  )
  let long_id = project_notion_page(
    @utf8.encode(
      title_test_wire(
        "{\"a\":{\"id\":\"abcd\",\"type\":\"title\",\"title\":[]}}",
      ),
    ),
    "p",
    page_test_limits(),
  ).unwrap()
  assert_eq(
    start_notion_page_title_property_item_request(long_id, {
      ..limits,
      metadata: { ..limits.metadata, max_identity_bytes: 3, },
    }).unwrap_err(),
    BudgetExceeded,
  )
}

///|
test "Notion completed title retains response bounds Unicode bytes and fail-closed emission" {
  let page = title_test_page()
  let request = start_notion_page_title_property_item_request(
    page,
    property_test_limits(),
  ).unwrap()
  let terminal = project_notion_property_item_page(
    request,
    property_test_page(
      "title",
      property_test_item("title", property_test_text("\"😀\"")),
      "null",
    ),
  ).unwrap()
  assert_eq(
    admit_notion_completed_page_title(page, terminal, {
      ..cell_test_limits(),
      max_text_bytes: 3,
    }).unwrap_err(),
    BudgetExceeded,
  )
  assert_eq(
    admit_notion_completed_page_title(page, terminal, {
      ..cell_test_limits(),
      max_nodes: 0,
    }).unwrap_err(),
    InvalidLimits,
  )
  assert_eq(
    notion_completed_page_title_wire(
      page,
      terminal,
      cell_test_limits(),
      5,
      2,
      2,
    ).unwrap_err(),
    BudgetExceeded,
  )
  assert_eq(
    notion_completed_page_title_wire(
      page,
      terminal,
      cell_test_limits(),
      6,
      2,
      2,
    ),
    Ok("\"😀\""),
  )
  let first = project_notion_property_item_page(
    request,
    property_test_page("title", "", "\"again\""),
  ).unwrap()
  assert_eq(
    project_notion_property_item_page(
      next_notion_property_item_request(first).unwrap(),
      property_test_page("title", "", "\"again\""),
    ).unwrap_err(),
    RepeatedCursor,
  )
}
