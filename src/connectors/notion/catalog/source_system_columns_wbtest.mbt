///|
fn system_test_row(
  id? : String = "page",
  created? : String = "\"2026-10-18T10:20:30+09:00\"",
  edited? : String = "\"2026-10-18T01:21:30.000Z\"",
  created_by? : String = "{\"object\":\"user\",\"id\":\"maker\"}",
  url? : String = "\"https://notion.test/page\"",
) -> String {
  let base = query_test_row(id)
  base[0:base.length() - 1].to_owned() +
  ",\"url\":" +
  url +
  ",\"created_time\":" +
  created +
  ",\"created_by\":" +
  created_by +
  ",\"last_edited_time\":" +
  edited +
  ",\"last_edited_by\":{\"object\":\"user\",\"id\":\"editor\"}}"
}

///|
fn system_test_setup(
  wire : String,
) -> (NotionDataSourceReadContracts, OriginalNotionQueryPage) {
  let (original, _) = row_test_setup()
  let binding = with_notion_source_system_contracts(
    original,
    read_test_limits(),
  ).unwrap()
  let page = project_notion_query_page(
    binding.source,
    @utf8.encode(query_test_page(wire, "null", "false")),
    query_test_limits(),
  ).unwrap()
  (binding, page)
}

///|
test "Notion system columns retain the same property originals and exact page coordinates" {
  let (property, _) = row_test_setup()
  let original_schema = notion_data_source_read_schema_wire(
    property, 4096, 100, 16,
  ).unwrap()
  let binding = with_notion_source_system_contracts(
    property,
    read_test_limits(),
  ).unwrap()
  assert_eq(binding.columns.length(), 2)
  assert_eq(binding.system_columns.length(), 8)
  assert_true(physical_equal(binding.declaration, property.declaration))
  assert_true(physical_equal(binding.source, property.source))
  assert_true(
    physical_equal(binding.columns[0].contract, property.columns[0].contract),
  )
  assert_eq(
    notion_data_source_read_schema_wire(property, 4096, 100, 16),
    Ok(original_schema),
  )
  assert_eq(
    with_notion_source_system_contracts(binding, read_test_limits()).unwrap_err(),
    InvalidDeclaration,
  )
  let (binding, page) = system_test_setup(system_test_row())
  let row = start_notion_read_row(binding, page, 0, row_test_limits()).unwrap()
  assert_eq(notion_read_row_pending_wire(row, 64, 8, 4), Ok("[0]"))
  complete_notion_read_row_property(row, 0, row_test_title(binding, page)).unwrap()
  assert_eq(
    notion_read_row_wire(row, 1024, 32, 8),
    Ok(
      "{\"amount\":\"9007199254740993.25\",\"created_by\":\"maker\",\"created_time\":\"2026-10-18T01:20:30.000Z\",\"id\":\"page\",\"last_edited_by\":\"editor\",\"last_edited_time\":\"2026-10-18T01:21:30.000Z\",\"resource\":\"page\",\"title\":\"é😀\",\"url\":\"https://notion.test/page\",\"version\":\"2026-10-18T01:21:30.000Z\"}",
    ),
  )
  assert_eq(
    complete_notion_read_row_property(row, 2, row_test_title(binding, page)),
    Err(InvalidColumn),
  )
}

///|
test "Notion system timestamp normalization preserves the original version spelling" {
  let (binding, page) = system_test_setup(
    system_test_row(edited="\"2026-10-18T10:21:30+09:00\""),
  )
  let row = start_notion_read_row(binding, page, 0, row_test_limits()).unwrap()
  complete_notion_read_row_property(row, 0, row_test_title(binding, page)).unwrap()
  let wire = notion_read_row_wire(row, 1024, 32, 8).unwrap()
  assert_true(
    wire.contains("\"last_edited_time\":\"2026-10-18T01:21:30.000Z\""),
  )
  assert_true(wire.contains("\"version\":\"2026-10-18T10:21:30+09:00\""))
  for
    malformed in [
      "\"2026-10-18T01:21:30-00:00\"", "\"2026-10-18T01:21:30.0000000001Z\"", "null",
      "13",
    ] {
    let (binding, page) = system_test_setup(system_test_row(edited=malformed))
    assert_true(
      start_notion_read_row(binding, page, 0, row_test_limits())
      is Err(InvalidSystemField("last_edited_time")),
    )
  }
}

///|
test "Notion finer system timestamps preserve exact instants and original versions" {
  for
    (original, canonical) in [
      ("2026-10-18T01:21:30.0001Z", "2026-10-18T01:21:30.0001Z"),
      ("2026-10-18T10:21:30.000100+09:00", "2026-10-18T01:21:30.0001Z"),
      ("2026-10-18T10:21:30.123456789+09:00", "2026-10-18T01:21:30.123456789Z"),
    ] {
    let original_json = original.to_json().stringify()
    let canonical_json = canonical.to_json().stringify()
    let (binding, page) = system_test_setup(
      system_test_row(created=original_json, edited=original_json),
    )
    let row = start_notion_read_row(binding, page, 0, row_test_limits()).unwrap()
    complete_notion_read_row_property(row, 0, row_test_title(binding, page)).unwrap()
    assert_eq(
      notion_read_row_wire(row, 1024, 32, 8),
      Ok(
        "{\"amount\":\"9007199254740993.25\",\"created_by\":\"maker\",\"created_time\":" +
        canonical_json +
        ",\"id\":\"page\",\"last_edited_by\":\"editor\",\"last_edited_time\":" +
        canonical_json +
        ",\"resource\":\"page\",\"title\":\"é😀\",\"url\":\"https://notion.test/page\",\"version\":" +
        original_json +
        "}",
      ),
    )
  }
}

///|
test "Notion missing malformed or foreign system originals cannot produce a full Source row" {
  for
    wire in [
      query_test_row("page"),
      system_test_row(url="null"),
      system_test_row(created_by="{\"object\":\"page\",\"id\":\"maker\"}"),
      system_test_row(created_by="{\"object\":\"user\",\"id\":null}"),
      system_test_row(created="\"bad\""),
    ] {
    let (binding, page) = system_test_setup(wire)
    assert_true(
      start_notion_read_row(binding, page, 0, row_test_limits()) is Err(_),
    )
  }
  let (binding, _) = system_test_setup(system_test_row())
  let (_, foreign) = system_test_setup(system_test_row())
  assert_eq(
    start_notion_read_row(binding, foreign, 0, row_test_limits()).unwrap_err(),
    ForeignOriginal,
  )
}

///|
test "Notion system schema and row holdings retain exact structural exhaustion" {
  let (property, _) = row_test_setup()
  assert_eq(
    with_notion_source_system_contracts(property, {
      ..read_test_limits(),
      max_columns: 9,
    }).unwrap_err(),
    BudgetExceeded,
  )
  assert_eq(
    with_notion_source_system_contracts(property, {
      ..read_test_limits(),
      max_work: 1,
    }).unwrap_err(),
    BudgetExceeded,
  )
  let (binding, page) = system_test_setup(system_test_row())
  assert_eq(
    start_notion_read_row(binding, page, 0, {
      ..row_test_limits(),
      max_work: 1,
    }).unwrap_err(),
    BudgetExceeded,
  )
  assert_eq(
    start_notion_read_row(binding, page, 0, {
      ..row_test_limits(),
      values: { ..cell_test_limits(), max_nodes: 10, },
    }).unwrap_err(),
    BudgetExceeded,
  )
  let row = start_notion_read_row(binding, page, 0, row_test_limits()).unwrap()
  complete_notion_read_row_property(row, 0, row_test_title(binding, page)).unwrap()
  let wire = notion_read_row_wire(row, 1024, 32, 8).unwrap()
  assert_eq(
    notion_read_row_wire(row, @utf8.encode(wire).length() - 1, 32, 8),
    Err(BudgetExceeded),
  )
  assert_eq(
    notion_read_page_rows_wire(
      binding,
      page,
      [row],
      cell_test_limits(),
      100000,
      1024,
      32,
      8,
    ),
    Ok("[" + wire + "]"),
  )
}

///|
test "Notion original property aliases cannot overwrite a system Source column" {
  let source = query_test_source()
  let wire = read_test_wire().replace_all(
    old="\"column\":\"title\"",
    new="\"column\":\"id\"",
  )
  let declaration = read_notion_database_read_declaration(
    @utf8.encode(wire),
    read_test_limits(),
  ).unwrap()
  let original = bind_notion_data_source_read_contracts(
    declaration,
    source,
    read_test_limits(),
  ).unwrap()
  assert_eq(
    with_notion_source_system_contracts(original, read_test_limits()).unwrap_err(),
    InvalidColumn("names"),
  )
}
