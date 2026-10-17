///|
fn observed_row_test_page(wire? : String = "") -> OriginalNotionPage {
  let base = if wire.is_empty() { system_test_row() } else { wire }
  let wire = base[0:base.length() - 1].to_owned() + ",\"in_trash\":false}"
  project_notion_page(@utf8.encode(wire), "page", page_test_limits()).unwrap()
}

///|
fn observed_row_test_binding() -> NotionDataSourceReadContracts {
  row_test_setup().0
}

///|
fn observed_row_test_title(
  request : NotionPropertyItemRequest,
) -> NotionPropertyItemPage {
  project_notion_property_item_page(
    request,
    @utf8.encode(
      (try! @utf8.decode(
        property_test_page(
          "title",
          property_test_item("title", property_test_text("\"é😀\"")),
          "null",
        )[:],
      )).replace_all(old="\"v\"", new="\"t%3Ax\""),
    ),
  ).unwrap()
}

///|
test "Notion observed exact GET retains the actual page and complete declared row without a synthetic query" {
  let binding = observed_row_test_binding()
  let page = observed_row_test_page()
  let row = start_notion_observed_page_read_row(
    binding,
    page,
    16,
    128,
    row_test_limits(),
  ).unwrap()
  assert_true(notion_read_row_matches_observed_page(row, binding, page))
  assert_true(
    !notion_read_row_matches_observed_page(
      row,
      binding,
      observed_row_test_page(),
    ),
  )
  assert_true(physical_equal(row.row.original, page.original))
  assert_true(physical_equal(row.row.properties[0].raw, page.raw))
  assert_eq(notion_read_row_pending_wire(row, 64, 8, 4), Ok("[0]"))
  assert_eq(finish_notion_read_row(row).unwrap_err(), Incomplete)
  let request = start_notion_read_row_property_item_request(
    row,
    0,
    property_test_limits(),
  ).unwrap()
  assert_true(notion_property_item_request_matches_binding(request, binding, 0))
  assert_eq(
    notion_property_item_request_wire(request, 256, 10, 4),
    Ok("{\"pageId\":\"page\",\"propertyId\":\"t%3Ax\",\"cursor\":null}"),
  )
  complete_notion_read_row_property(row, 0, observed_row_test_title(request)).unwrap()
  assert_eq(
    notion_read_row_wire(row, 1024, 16, 4),
    Ok("{\"amount\":\"9007199254740993.25\",\"title\":\"é😀\"}"),
  )
  let (checked, _, _) = finish_notion_read_row(row).unwrap()
  assert_true(physical_equal(checked.contract, binding.schema))
  assert_eq(
    start_notion_read_row_property_item_request(row, 0, property_test_limits()).unwrap_err(),
    InvalidSelection,
  )
}

///|
test "Notion observed row property completion rejects another observation even with equal ids bytes and schema" {
  let binding = observed_row_test_binding()
  let page = observed_row_test_page()
  let row = start_notion_observed_page_read_row(
    binding,
    page,
    16,
    128,
    row_test_limits(),
  ).unwrap()
  let other = start_notion_observed_page_read_row(
    binding,
    page,
    16,
    128,
    row_test_limits(),
  ).unwrap()
  let request = start_notion_read_row_property_item_request(
    other,
    0,
    property_test_limits(),
  ).unwrap()
  assert_eq(
    complete_notion_read_row_property(row, 0, observed_row_test_title(request)),
    Err(ForeignOriginal),
  )
  assert_eq(finish_notion_read_row(row).unwrap_err(), Incomplete)
  let copy = { ..row, work: row.work, }
  assert_true(!notion_read_row_matches_observed_page(copy, binding, page))
  assert_eq(
    start_notion_read_row_property_item_request(copy, 0, property_test_limits()).unwrap_err(),
    ForeignOriginal,
  )
  let foreign_binding = bind_notion_data_source_read_contracts(
    read_test_declaration(),
    binding.source,
    read_test_limits(),
  ).unwrap()
  assert_true(
    !notion_read_row_matches_observed_page(row, foreign_binding, page),
  )
  assert_eq(
    start_notion_read_row_property_item_request(row, -1, property_test_limits()).unwrap_err(),
    InvalidSelection,
  )
  assert_eq(
    start_notion_read_row_property_item_request(row, 2, property_test_limits()).unwrap_err(),
    InvalidSelection,
  )
  assert_eq(
    start_notion_read_row_property_item_request(row, 1, property_test_limits()).unwrap_err(),
    InvalidSelection,
  )
}

///|
test "Notion observed row binds the actual selected data source parent and every original property" {
  let binding = observed_row_test_binding()
  for
    (old, replacement) in [
      ("\"data_source_id\":\"s2\"", "\"data_source_id\":\"other\""),
      ("\"database_id\":\"db\"", "\"database_id\":\"other\""),
      (
        "\"type\":\"data_source_id\"", "\"type\":\"page_id\",\"page_id\":\"other\"",
      ),
      ("\"id\":\"t%3Ax\"", "\"id\":\"changed\""),
      ("\"title\":[]", "\"title\":[],\"type\":\"rich_text\""),
    ] {
    // A changed title kind is authored without a duplicate JSON member.
    let wire = if old == "\"title\":[]" {
      system_test_row().replace(
        old="\"type\":\"title\"",
        new="\"type\":\"rich_text\"",
      )
    } else {
      system_test_row().replace(old~, new=replacement)
    }
    if old == "\"type\":\"data_source_id\"" {
      // Exact page parent validation independently refuses mixed coordinates.
      let wire = wire
        .replace(old="\"data_source_id\":\"s2\",", new="")
        .replace(old=",\"database_id\":\"db\"", new="")
      let page = observed_row_test_page(wire~)
      assert_true(
        start_notion_observed_page_read_row(
          binding,
          page,
          16,
          128,
          row_test_limits(),
        )
        is Err(Observation(_)),
      )
    } else {
      let page = observed_row_test_page(wire~)
      assert_true(
        start_notion_observed_page_read_row(
          binding,
          page,
          16,
          128,
          row_test_limits(),
        )
        is Err(Observation(_)),
      )
    }
  }
  for
    wire in [
      system_test_row().replace(
        old=",\"amount\":{\"id\":\"n\",\"type\":\"number\",\"number\":9007199254740993.25}",
        new="",
      ),
      system_test_row().replace(
        old="\"properties\":{",
        new="\"properties\":{\"extra\":{\"id\":\"extra\",\"type\":\"checkbox\",\"checkbox\":true},",
      ),
    ] {
    let page = observed_row_test_page(wire~)
    assert_true(
      start_notion_observed_page_read_row(
        binding,
        page,
        16,
        128,
        row_test_limits(),
      )
      is Err(Observation(_)),
    )
  }
}

///|
test "Notion observed row conservatively charges original scans before assembly and keeps legacy query behavior" {
  let binding = observed_row_test_binding()
  let page = observed_row_test_page()
  for
    limits in [
      { ..row_test_limits(), max_work: page.raw.length() - 1, },
      { ..row_test_limits(), max_work: page.raw.length(), },
      { ..row_test_limits(), max_columns: 1, },
      { ..row_test_limits(), values: { ..cell_test_limits(), max_nodes: 2, }, },
    ] {
    assert_eq(
      start_notion_observed_page_read_row(binding, page, 16, 128, limits).unwrap_err(),
      BudgetExceeded,
    )
  }
  assert_eq(
    start_notion_observed_page_read_row(
      binding,
      page,
      1,
      128,
      row_test_limits(),
    ).unwrap_err(),
    BudgetExceeded,
  )
  assert_eq(
    start_notion_observed_page_read_row(
      binding,
      page,
      -1,
      128,
      row_test_limits(),
    ).unwrap_err(),
    InvalidLimits,
  )
  let (binding, query) = row_test_setup()
  let query_row = start_notion_read_row(binding, query, 0, row_test_limits()).unwrap()
  assert_true(!notion_read_row_matches_observed_page(query_row, binding, page))
  let request = start_notion_read_row_property_item_request(
    query_row,
    0,
    property_test_limits(),
  ).unwrap()
  complete_notion_read_row_property(
    query_row,
    0,
    observed_row_test_title(request),
  ).unwrap()
  assert_eq(
    notion_read_row_wire(query_row, 1024, 16, 4),
    Ok("{\"amount\":\"9007199254740993.25\",\"title\":\"é😀\"}"),
  )
  let get_row = start_notion_observed_page_read_row(
    binding,
    page,
    16,
    128,
    row_test_limits(),
  ).unwrap()
  assert_eq(
    notion_read_page_rows_wire(
      binding,
      query,
      [get_row],
      cell_test_limits(),
      100000,
      4096,
      64,
      8,
    ).unwrap_err(),
    ForeignOriginal,
  )
}

///|
test "Notion observed page row retains exact system metadata and original version with completed properties" {
  let binding = with_notion_source_system_contracts(
    observed_row_test_binding(),
    read_test_limits(),
  ).unwrap()
  let page = observed_row_test_page(
    wire=system_test_row(edited="\"2026-10-18T10:21:30+09:00\""),
  )
  let row = start_notion_observed_page_read_row(
    binding,
    page,
    16,
    128,
    row_test_limits(),
  ).unwrap()
  let request = start_notion_read_row_property_item_request(
    row,
    0,
    property_test_limits(),
  ).unwrap()
  complete_notion_read_row_property(row, 0, observed_row_test_title(request)).unwrap()
  let wire = notion_read_row_wire(row, 4096, 64, 8).unwrap()
  assert_true(
    wire.contains("\"last_edited_time\":\"2026-10-18T01:21:30.000Z\""),
  )
  assert_true(wire.contains("\"version\":\"2026-10-18T10:21:30+09:00\""))
  assert_true(wire.contains("\"amount\":\"9007199254740993.25\""))
  assert_true(wire.contains("\"resource\":\"page\""))
  assert_true(notion_read_row_matches_observed_page(row, binding, page))
}
