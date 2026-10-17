///|
fn row_test_limits() -> NotionReadRowLimits {
  { values: cell_test_limits(), max_columns: 16, max_work: 100000, }
}

///|
fn row_test_setup() -> (NotionDataSourceReadContracts, OriginalNotionQueryPage) {
  let source = query_test_source()
  let binding = bind_notion_data_source_read_contracts(
    read_test_declaration(),
    source,
    read_test_limits(),
  ).unwrap()
  let page = project_notion_query_page(
    source,
    @utf8.encode(query_test_page(query_test_row("page"), "null", "false")),
    query_test_limits(),
  ).unwrap()
  (binding, page)
}

///|
fn row_test_title(
  binding : NotionDataSourceReadContracts,
  page : OriginalNotionQueryPage,
  row_index? : Int = 0,
) -> NotionPropertyItemPage {
  let request = start_notion_column_property_item_request(
    binding,
    notion_query_page_row_at(page, row_index).unwrap(),
    0,
    property_test_limits(),
  ).unwrap()
  let response = property_test_page(
    "title",
    property_test_item("title", property_test_text("\"é😀\"")),
    "null",
  )
  project_notion_property_item_page(
    request,
    @utf8.encode(
      (try! @utf8.decode(response[:])).replace_all(old="\"v\"", new="\"t%3Ax\""),
    ),
  ).unwrap()
}

///|
test "Notion complete page bounds include every original row and its outer array" {
  let (binding, _) = row_test_setup()
  let page = project_notion_query_page(
    binding.source,
    @utf8.encode(
      query_test_page(
        query_test_row("one") + "," + query_test_row("two"),
        "null",
        "false",
      ),
    ),
    query_test_limits(),
  ).unwrap()
  let rows = []
  for index in 0..<2 {
    let row = start_notion_read_row(binding, page, index, row_test_limits()).unwrap()
    complete_notion_read_row_property(
      row,
      0,
      row_test_title(binding, page, row_index=index),
    ).unwrap()
    rows.push(row)
  }
  let expected = "[{\"amount\":\"9007199254740993.25\",\"title\":\"é😀\"},{\"amount\":\"9007199254740993.25\",\"title\":\"é😀\"}]"
  let limits : @admitted.Limits = {
    max_nodes: 7,
    max_depth: 2,
    max_text_bytes: 72,
  }
  let bytes = @utf8.encode(expected).length()
  assert_eq(
    notion_read_page_rows_wire(binding, page, rows, limits, 10000, bytes, 7, 2),
    Ok(expected),
  )
  for
    short in [
      { ..limits, max_nodes: 6, },
      { ..limits, max_depth: 1, },
      { ..limits, max_text_bytes: 71, },
    ] {
    assert_eq(
      notion_read_page_rows_wire(binding, page, rows, short, 10000, bytes, 7, 2),
      Err(BudgetExceeded),
    )
  }
  assert_eq(
    notion_read_page_rows_wire(
      binding,
      page,
      rows,
      limits,
      10000,
      bytes - 1,
      7,
      2,
    ),
    Err(BudgetExceeded),
  )
  assert_eq(
    notion_read_page_rows_wire(binding, page, rows, limits, 10000, bytes, 6, 2),
    Err(BudgetExceeded),
  )
  assert_eq(
    notion_read_page_rows_wire(binding, page, rows, limits, 1, bytes, 7, 2),
    Err(BudgetExceeded),
  )
  assert_eq(
    notion_read_page_rows_wire(
      binding,
      page,
      [rows[1], rows[0]],
      limits,
      10000,
      bytes,
      7,
      2,
    ),
    Err(ForeignOriginal),
  )
  assert_eq(
    notion_read_page_rows_wire(
      binding,
      page,
      [rows[0]],
      limits,
      10000,
      bytes,
      7,
      2,
    ),
    Err(ForeignOriginal),
  )
  assert_eq(
    notion_read_page_rows_wire(
      binding,
      page,
      [rows[0], rows[0]],
      limits,
      10000,
      bytes,
      7,
      2,
    ),
    Err(ForeignOriginal),
  )
}

///|
test "Notion full checked property row retains original Decimal and completed text" {
  let (binding, page) = row_test_setup()
  let row = start_notion_read_row(binding, page, 0, row_test_limits()).unwrap()
  assert_eq(notion_read_row_pending_wire(row, 64, 8, 4), Ok("[0]"))
  assert_eq(finish_notion_read_row(row).unwrap_err(), Incomplete)
  assert_eq(
    complete_notion_read_row_property(row, 0, row_test_title(binding, page)),
    Ok(()),
  )
  let (checked, nodes, text) = finish_notion_read_row(row).unwrap()
  assert_true(physical_equal(checked.contract, binding.schema))
  assert_eq(nodes, 3)
  // Runtime recheck counts the exact 18-digit Decimal coefficient, not a Double.
  assert_eq(text, 6 + 5 + 7 + 18)
  assert_eq(notion_read_row_pending_wire(row, 64, 8, 4), Ok("[]"))
  assert_eq(
    notion_read_row_wire(row, 256, 32, 8),
    Ok("{\"amount\":\"9007199254740993.25\",\"title\":\"é😀\"}"),
  )
  assert_eq(
    complete_notion_read_row_property(row, 0, row_test_title(binding, page)),
    Err(AlreadySupplied),
  )
  assert_eq(notion_read_row_wire(row, 1, 32, 8), Err(BudgetExceeded))
  assert_true(notion_read_row_wire(row, 256, 32, 8) is Ok(_))
}

///|
test "Notion row refuses a completion from a different original observation with the same page id" {
  let (binding, page) = row_test_setup()
  let row = start_notion_read_row(binding, page, 0, row_test_limits()).unwrap()
  let equal = project_notion_query_page(
    binding.source,
    @utf8.encode(query_test_page(query_test_row("page"), "null", "false")),
    query_test_limits(),
  ).unwrap()
  assert_eq(
    complete_notion_read_row_property(row, 0, row_test_title(binding, equal)),
    Err(ForeignOriginal),
  )
  let (foreign, other) = row_test_setup()
  assert_eq(
    complete_notion_read_row_property(row, 0, row_test_title(foreign, other)),
    Err(ForeignOriginal),
  )
  assert_eq(finish_notion_read_row(row).unwrap_err(), Incomplete)
  assert_eq(
    complete_notion_read_row_property(row, 0, row_test_title(binding, page)),
    Ok(()),
  )
  assert_true(finish_notion_read_row(row) is Ok(_))
}

///|
test "Notion row refuses copied assembly and uncompleted property controls" {
  let (binding, page) = row_test_setup()
  let row = start_notion_read_row(binding, page, 0, row_test_limits()).unwrap()
  let copied = { ..row, work: row.work, }
  assert_eq(
    notion_read_row_pending_wire(copied, 64, 8, 4),
    Err(ForeignOriginal),
  )
  assert_eq(finish_notion_read_row(copied).unwrap_err(), ForeignOriginal)
  assert_eq(
    complete_notion_read_row_property(copied, 0, row_test_title(binding, page)),
    Err(ForeignOriginal),
  )
  let request = start_notion_column_property_item_request(
    binding,
    page.rows[0],
    0,
    property_test_limits(),
  ).unwrap()
  let response = property_test_page("title", "", "\"next\"")
  let incomplete = project_notion_property_item_page(
    request,
    @utf8.encode(
      (try! @utf8.decode(response[:])).replace_all(old="\"v\"", new="\"t%3Ax\""),
    ),
  ).unwrap()
  assert_eq(
    complete_notion_read_row_property(row, 0, incomplete),
    Err(Property(Incomplete)),
  )
  assert_eq(
    complete_notion_read_row_property(row, 0, {
      ..incomplete,
      next_cursor: None,
    }),
    Err(ForeignOriginal),
  )
  assert_eq(finish_notion_read_row(row).unwrap_err(), Incomplete)
}

///|
test "Notion row aggregate depth nodes text columns and work refuse without partial row output" {
  let (binding, page) = row_test_setup()
  for
    limits in [
      { ..row_test_limits(), max_columns: 1, },
      { ..row_test_limits(), values: { ..cell_test_limits(), max_nodes: 2, }, },
      { ..row_test_limits(), values: { ..cell_test_limits(), max_depth: 1, }, },
      {
        ..row_test_limits(),
        values: { ..cell_test_limits(), max_text_bytes: 5, },
      },
      { ..row_test_limits(), max_work: 1, },
    ] {
    assert_true(start_notion_read_row(binding, page, 0, limits) is Err(_))
  }
  assert_true(
    start_notion_read_row(binding, page, 1, row_test_limits()) is Err(_),
  )
  let (foreign, _) = row_test_setup()
  assert_true(
    start_notion_read_row(foreign, page, 0, row_test_limits()) is Err(_),
  )
  let row = start_notion_read_row(binding, page, 0, row_test_limits()).unwrap()
  assert_eq(
    complete_notion_read_row_property(row, -1, row_test_title(binding, page)),
    Err(InvalidColumn),
  )
  assert_eq(
    complete_notion_read_row_property(row, 1, row_test_title(binding, page)),
    Err(AlreadySupplied),
  )
}

///|
test "Notion row aggregate canonical text budget counts Decimal coefficient rather than input punctuation" {
  let (binding, page) = row_test_setup()
  // The complete runtime object has names amount/title (11 bytes), an exact
  // 18-digit coefficient and seven UTF-8 bytes in the original completed title.
  let limits = {
    ..row_test_limits(),
    values: { ..cell_test_limits(), max_nodes: 3, max_text_bytes: 36, },
  }
  let row = start_notion_read_row(binding, page, 0, limits).unwrap()
  assert_eq(
    complete_notion_read_row_property(row, 0, row_test_title(binding, page)),
    Ok(()),
  )
  let (_, nodes, text) = finish_notion_read_row(row).unwrap()
  assert_eq((nodes, text), (3, 36))
  let short = start_notion_read_row(binding, page, 0, {
    ..limits,
    values: { ..limits.values, max_text_bytes: 35, },
  }).unwrap()
  assert_eq(
    complete_notion_read_row_property(short, 0, row_test_title(binding, page)),
    Err(BudgetExceeded),
  )
}
