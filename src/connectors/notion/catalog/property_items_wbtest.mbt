///|
fn property_test_limits() -> NotionPropertyItemLimits {
  {
    metadata: database_test_limits(),
    max_pages: 8,
    max_items: 32,
    max_total_bytes: 16384,
    max_total_nodes: 2048,
    max_total_text_bytes: 8192,
    max_cursor_bytes: 64,
    max_work: 100000,
  }
}

///|
fn property_test_setup(
  kind : String,
  contract : String,
) -> (
  NotionDataSourceReadContracts,
  OriginalNotionQueryRow,
  NotionPropertyItemRequest,
) {
  let source = cell_test_scalar_source(kind)
  let binding = cell_test_scalar_binding(source, contract, "value")
  let row = cell_test_row(source, cell_test_scalar_native(kind, "[]"))
  let request = start_notion_property_item_request(
    row,
    0,
    property_test_limits(),
  ).unwrap()
  (binding, row, request)
}

///|
fn property_test_item(kind : String, native : String) -> String {
  "{\"object\":\"property_item\",\"id\":\"v\",\"type\":\"" +
  kind +
  "\",\"" +
  kind +
  "\":" +
  native +
  "}"
}

///|
fn property_test_page(kind : String, items : String, cursor : String) -> Bytes {
  let more = if cursor == "null" { "false" } else { "true" }
  let url = if cursor == "null" {
    "null"
  } else {
    "\"https://api.notion.com/v1/pages/page/properties/v?opaque=vendor-value\""
  }
  @utf8.encode(
    "{\"object\":\"list\",\"type\":\"property_item\",\"results\":[" +
    items +
    "],\"has_more\":" +
    more +
    ",\"next_cursor\":" +
    cursor +
    ",\"property_item\":{\"id\":\"v\",\"type\":\"" +
    kind +
    "\",\"" +
    kind +
    "\":{},\"next_url\":" +
    url +
    "}}",
  )
}

///|
fn property_test_text(text : String) -> String {
  // Input is independently authored JSON text, including its original escapes.
  "{\"type\":\"text\",\"text\":{\"content\":" +
  text +
  "},\"plain_text\":" +
  text +
  "}"
}

///|
test "Notion property item chain admits only complete ordered original rich text" {
  let (binding, row, request) = property_test_setup(
    "rich_text", "{\"type\":\"string\",\"nullable\":false}",
  )
  assert_true(notion_property_item_request_matches(request, row, 0))
  assert_true(!notion_property_item_request_matches(request, row, 1))
  assert_eq(
    notion_property_item_request_wire(request, 256, 8, 4),
    Ok("{\"pageId\":\"page\",\"propertyId\":\"v\",\"cursor\":null}"),
  )
  let first = project_notion_property_item_page(
    request,
    property_test_page(
      "rich_text",
      property_test_item("rich_text", property_test_text("\"é\\r\\n\"")),
      "\"opaque+/= cursor\"",
    ),
  ).unwrap()
  assert_eq(
    admit_notion_completed_property(binding, first, 0, cell_test_limits()).unwrap_err(),
    Incomplete,
  )
  let next = next_notion_property_item_request(first).unwrap()
  assert_true(notion_property_item_request_matches(next, row, 0))
  assert_eq(
    notion_property_item_request_wire(next, 256, 8, 4),
    Ok(
      "{\"pageId\":\"page\",\"propertyId\":\"v\",\"cursor\":\"opaque+/= cursor\"}",
    ),
  )
  let terminal = project_notion_property_item_page(
    next,
    property_test_page(
      "rich_text",
      property_test_item("rich_text", property_test_text("\"😀\"")),
      "null",
    ),
  ).unwrap()
  assert_true(next_notion_property_item_request(terminal) is None)
  let (value, nodes, text) = admit_notion_completed_property(
    binding,
    terminal,
    0,
    cell_test_limits(),
  ).unwrap()
  assert_eq(@admitted.canonical_scalar_text(value, 128), Some("é\r\n😀"))
  assert_eq(nodes, 1)
  assert_eq(text, 9)
  assert_true(physical_equal(value.contract, binding.columns[0].contract))
  assert_eq(
    notion_completed_property_wire(
      binding,
      terminal,
      0,
      cell_test_limits(),
      128,
      8,
      4,
    ),
    Ok("\"é\\r\\n😀\""),
  )
}

///|
test "Notion property repeats are values not invented unique property-item keys" {
  for kind in ["people", "relation"] {
    let (binding, _, request) = property_test_setup(
      kind, "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"string\",\"nullable\":false}}",
    )
    let native = if kind == "people" {
      "{\"object\":\"user\",\"id\":\"U1\"}"
    } else {
      "{\"id\":\"P1\"}"
    }
    let item = property_test_item(kind, native)
    let first = project_notion_property_item_page(
      request,
      property_test_page(kind, item, "\"next\""),
    ).unwrap()
    let terminal = project_notion_property_item_page(
      next_notion_property_item_request(first).unwrap(),
      property_test_page(kind, item + "," + item, "null"),
    ).unwrap()
    let expected = if kind == "people" {
      "[\"U1\",\"U1\",\"U1\"]"
    } else {
      "[\"P1\",\"P1\",\"P1\"]"
    }
    assert_eq(
      notion_completed_property_wire(
        binding,
        terminal,
        0,
        cell_test_limits(),
        128,
        8,
        4,
      ),
      Ok(expected),
    )
    assert_eq(
      admit_notion_completed_property(binding, terminal, 0, {
        ..cell_test_limits(),
        max_nodes: 3,
      }).unwrap_err(),
      BudgetExceeded,
    )
  }
}

///|
test "Notion property empty continuation is incomplete while empty terminal is the original empty value" {
  for kind in ["title", "rich_text", "people", "relation"] {
    let contract = if kind == "title" || kind == "rich_text" {
      "{\"type\":\"string\",\"nullable\":false}"
    } else {
      "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"string\",\"nullable\":false}}"
    }
    let (binding, _, request) = property_test_setup(kind, contract)
    let first = project_notion_property_item_page(
      request,
      property_test_page(kind, "", "\"next\""),
    ).unwrap()
    assert_eq(
      admit_notion_completed_property(binding, first, 0, cell_test_limits()).unwrap_err(),
      Incomplete,
    )
    let terminal = project_notion_property_item_page(
      next_notion_property_item_request(first).unwrap(),
      property_test_page(kind, "", "null"),
    ).unwrap()
    assert_eq(
      notion_completed_property_wire(
        binding,
        terminal,
        0,
        cell_test_limits(),
        128,
        8,
        4,
      ),
      Ok(if kind == "title" || kind == "rich_text" { "\"\"" } else { "[]" }),
    )
  }
}

///|
test "Notion property completion retains original row schema and checked enum as a whole" {
  let (binding, row, request) = property_test_setup(
    "title", "{\"type\":\"string\",\"nullable\":false,\"enum\":[\"ab\"]}",
  )
  let first = project_notion_property_item_page(
    request,
    property_test_page(
      "title",
      property_test_item("title", property_test_text("\"a\"")),
      "\"next\"",
    ),
  ).unwrap()
  let terminal = project_notion_property_item_page(
    next_notion_property_item_request(first).unwrap(),
    property_test_page(
      "title",
      property_test_item("title", property_test_text("\"b\"")),
      "null",
    ),
  ).unwrap()
  assert_eq(
    notion_completed_property_wire(
      binding,
      terminal,
      0,
      cell_test_limits(),
      128,
      8,
      4,
    ),
    Ok("\"ab\""),
  )
  let (foreign, foreign_row, _) = property_test_setup(
    "title", "{\"type\":\"string\",\"nullable\":false,\"enum\":[\"ab\"]}",
  )
  assert_true(!notion_property_item_request_matches(request, foreign_row, 0))
  assert_eq(
    admit_notion_completed_property(foreign, terminal, 0, cell_test_limits()).unwrap_err(),
    ForeignOriginal,
  )
  assert_eq(
    admit_notion_property_read_cell(binding, row, 0, cell_test_limits(), 1000).unwrap_err(),
    PropertyCompletionRequired("v"),
  )
  let rejected = project_notion_property_item_page(
    request,
    property_test_page(
      "title",
      property_test_item("title", property_test_text("\"other\"")),
      "null",
    ),
  ).unwrap()
  assert_true(
    admit_notion_completed_property(binding, rejected, 0, cell_test_limits())
    is Err(Admission(_)),
  )
  assert_eq(
    admit_notion_completed_property(binding, terminal, 0, {
      ..cell_test_limits(),
      max_text_bytes: 1,
    }).unwrap_err(),
    BudgetExceeded,
  )
}

///|
test "Notion property repeated cursor refuses cycles without treating values as keys" {
  let (_, _, request) = property_test_setup(
    "title", "{\"type\":\"string\",\"nullable\":false}",
  )
  let first = project_notion_property_item_page(
    request,
    property_test_page("title", "", "\"c1\""),
  ).unwrap()
  let next = next_notion_property_item_request(first).unwrap()
  assert_eq(
    project_notion_property_item_page(
      next,
      property_test_page("title", "", "\"c1\""),
    ).unwrap_err(),
    RepeatedCursor,
  )
  let second = project_notion_property_item_page(
    next,
    property_test_page("title", "", "\"c2\""),
  ).unwrap()
  assert_eq(
    project_notion_property_item_page(
      next_notion_property_item_request(second).unwrap(),
      property_test_page("title", "", "\"c1\""),
    ).unwrap_err(),
    RepeatedCursor,
  )
}

///|
test "Notion property discriminants cursor pairing and native items refuse partial success" {
  let (_, _, request) = property_test_setup(
    "title", "{\"type\":\"string\",\"nullable\":false}",
  )
  let wire = @utf8.decode(
    property_test_page(
      "title",
      property_test_item("title", property_test_text("\"a\"")),
      "null",
    ),
  )
  for
    changed in [
      wire.replace(old="\"id\":\"v\"", new="\"id\":\"foreign\""),
      wire.replace(old="\"type\":\"title\"", new="\"type\":\"relation\""),
      wire.replace(old="\"has_more\":false", new="\"has_more\":true"),
      wire.replace(old="\"next_url\":null", new="\"next_url\":\"foreign\""),
      wire.replace(old="\"plain_text\":\"a\"", new="\"plain_text\":null"),
      wire.replace(old="\"object\":\"list\"", new="\"object\":\"error\""),
      wire.replace(old="\"title\":{},", new="\"title\":{\"unknown\":true},"),
    ] {
    assert_true(
      project_notion_property_item_page(request, @utf8.encode(changed))
      is Err(_),
    )
  }
  assert_true(project_notion_property_item_page(request, b"null") is Err(_))
}

///|
test "Notion property aggregate originals and decoded node text bounds remain exact" {
  let (binding, row, _) = property_test_setup(
    "rich_text", "{\"type\":\"string\",\"nullable\":false}",
  )
  let one = property_test_page(
    "rich_text",
    property_test_item("rich_text", property_test_text("\"a\"")),
    "\"next\"",
  )
  let two = property_test_page(
    "rich_text",
    property_test_item("rich_text", property_test_text("\"b\"")),
    "null",
  )
  let all = one.length() + two.length()
  let limits = { ..property_test_limits(), max_total_bytes: all, }
  let request = start_notion_property_item_request(row, 0, limits).unwrap()
  let first = project_notion_property_item_page(request, one).unwrap()
  let terminal = project_notion_property_item_page(
    next_notion_property_item_request(first).unwrap(),
    two,
  ).unwrap()
  assert_eq(terminal.total_bytes, all)
  assert_eq(
    notion_completed_property_wire(
      binding,
      terminal,
      0,
      cell_test_limits(),
      128,
      8,
      4,
    ),
    Ok("\"ab\""),
  )
  for
    limits in [
      { ..property_test_limits(), max_total_bytes: all - 1, },
      { ..property_test_limits(), max_total_nodes: terminal.total_nodes - 1, },
      {
        ..property_test_limits(),
        max_total_text_bytes: terminal.total_text - 1,
      },
      { ..property_test_limits(), max_pages: 1, },
      { ..property_test_limits(), max_items: 1, },
    ] {
    let request = start_notion_property_item_request(row, 0, limits).unwrap()
    let first = project_notion_property_item_page(request, one).unwrap()
    assert_eq(
      project_notion_property_item_page(
        next_notion_property_item_request(first).unwrap(),
        two,
      ).unwrap_err(),
      BudgetExceeded,
    )
    assert_eq(first.total_items, 1)
  }
}

///|
test "Notion property selection work and output exhaustion never promote inline values" {
  let (binding, row, request) = property_test_setup(
    "title", "{\"type\":\"string\",\"nullable\":false}",
  )
  assert_eq(
    start_notion_property_item_request(row, 1, property_test_limits()).unwrap_err(),
    InvalidSelection,
  )
  assert_eq(
    start_notion_property_item_request(row, 0, {
      ..property_test_limits(),
      max_work: 0,
    }).unwrap_err(),
    InvalidLimits,
  )
  let bytes = property_test_page("title", "", "null")
  let low = start_notion_property_item_request(row, 0, {
    ..property_test_limits(),
    max_work: bytes.length(),
  }).unwrap()
  assert_eq(
    project_notion_property_item_page(low, bytes).unwrap_err(),
    BudgetExceeded,
  )
  let terminal = project_notion_property_item_page(request, bytes).unwrap()
  assert_eq(
    notion_completed_property_wire(
      binding,
      terminal,
      0,
      cell_test_limits(),
      1,
      8,
      4,
    ).unwrap_err(),
    BudgetExceeded,
  )
  assert_eq(
    notion_property_item_request_wire(request, 1, 8, 4).unwrap_err(),
    BudgetExceeded,
  )
  let source = cell_test_scalar_source("rollup")
  let row = cell_test_row(source, cell_test_scalar_native("rollup", "{}"))
  assert_eq(
    start_notion_property_item_request(row, 0, property_test_limits()).unwrap_err(),
    UnsupportedProperty("rollup"),
  )
}
