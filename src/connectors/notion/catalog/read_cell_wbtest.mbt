///|
fn cell_test_limits() -> @admitted.Limits {
  { max_nodes: 32, max_depth: 16, max_text_bytes: 1024, }
}

///|
fn cell_test_row(
  source : NotionDataSourceCatalog,
  native : String,
) -> OriginalNotionQueryRow {
  let page = project_notion_query_page(
    source,
    @utf8.encode(query_test_page(native, "null", "false")),
    query_test_limits(),
  ).unwrap()
  notion_query_page_row_at(page, 0).unwrap()
}

///|
fn cell_test_scalar_source(kind : String) -> NotionDataSourceCatalog {
  let body = if kind == "formula" { "{\"expression\":\"1\"}" } else { "{}" }
  let wire = "{\"object\":\"data_source\",\"id\":\"s2\",\"parent\":{\"type\":\"database_id\",\"database_id\":\"db\"},\"properties\":{\"value\":{\"id\":\"v\",\"name\":\"value\",\"type\":\"" +
    kind +
    "\",\"" +
    kind +
    "\":" +
    body +
    "}}}"
  project_notion_data_source(
    database_test_original(),
    1,
    @utf8.encode(wire),
    database_test_limits(),
  ).unwrap()
}

///|
fn cell_test_scalar_binding(
  source : NotionDataSourceCatalog,
  contract : String,
  projection : String,
) -> NotionDataSourceReadContracts {
  let declaration = "{\"id\":\"db\",\"data_source_id\":\"s2\",\"read_contracts\":{\"v\":[{\"column\":\"value\",\"projection\":\"" +
    projection +
    "\",\"contract\":" +
    contract +
    "}]}}"
  bind_notion_data_source_read_contracts(
    read_notion_database_read_declaration(
      @utf8.encode(declaration),
      read_test_limits(),
    ).unwrap(),
    source,
    read_test_limits(),
  ).unwrap()
}

///|
fn cell_test_scalar_native(kind : String, value : String) -> String {
  "{\"object\":\"page\",\"id\":\"page\",\"parent\":{\"type\":\"data_source_id\",\"data_source_id\":\"s2\"},\"properties\":{\"value\":{\"id\":\"v\",\"type\":\"" +
  kind +
  "\",\"" +
  kind +
  "\":" +
  value +
  "}}}"
}

///|
test "Notion original numeric token is admitted as exact declared Decimal not rounded binary64" {
  let source = query_test_source()
  let read = bind_notion_data_source_read_contracts(
    read_test_declaration(),
    source,
    read_test_limits(),
  ).unwrap()
  let row = cell_test_row(source, query_test_row("page"))
  let (value, nodes, text) = admit_notion_property_read_cell(
    read,
    row,
    1,
    cell_test_limits(),
    1000,
  ).unwrap()
  assert_true(
    physical_equal(
      value.contract,
      notion_data_source_read_column_at(read, 1).unwrap().contract,
    ),
  )
  assert_eq(
    @admitted.canonical_scalar_text(value, 128),
    Some("9007199254740993.25"),
  )
  assert_eq(nodes, 1)
  assert_true(text > 0)
  assert_eq(
    admit_notion_property_read_cell(read, row, 0, cell_test_limits(), 1000).unwrap_err(),
    PropertyCompletionRequired("t%3Ax"),
  )
  assert_eq(
    admit_notion_property_read_cell(
      read,
      cell_test_row(query_test_source(), query_test_row("foreign")),
      1,
      cell_test_limits(),
      1000,
    ).unwrap_err(),
    ForeignOriginal,
  )
  assert_eq(
    admit_notion_property_read_cell(read, row, 1, cell_test_limits(), 2).unwrap_err(),
    BudgetExceeded,
  )
  assert_true(
    admit_notion_property_read_cell(
      read,
      row,
      1,
      { ..cell_test_limits(), max_text_bytes: 1, },
      1000,
    )
    is Err(_),
  )
}

///|
test "Notion Decimal out of precision nonzero extra scale and native strings never round or relabel" {
  let source = cell_test_scalar_source("number")
  let read = cell_test_scalar_binding(
    source, "{\"type\":\"decimal\",\"nullable\":false,\"precision\":5,\"scale\":2}",
    "value",
  )
  let row = cell_test_row(source, cell_test_scalar_native("number", "1.230e2"))
  let (value, _, _) = admit_notion_property_read_cell(
    read,
    row,
    0,
    cell_test_limits(),
    1000,
  ).unwrap()
  assert_eq(@admitted.canonical_scalar_text(value, 32), Some("123.00"))
  for native in ["1000", "1.001", "\"1.23\"", "true", "null"] {
    let row = cell_test_row(source, cell_test_scalar_native("number", native))
    assert_true(
      admit_notion_property_read_cell(read, row, 0, cell_test_limits(), 1000)
      is Err(_),
    )
  }
}

///|
test "Notion formula discriminant and enum remain the original checked contract" {
  let source = cell_test_scalar_source("formula")
  let read = cell_test_scalar_binding(
    source, "{\"type\":\"string\",\"nullable\":true,\"enum\":[\"low\",\"medium\"]}",
    "value",
  )
  let row = cell_test_row(
    source,
    cell_test_scalar_native(
      "formula", "{\"type\":\"string\",\"string\":\"low\"}",
    ),
  )
  let (value, _, _) = admit_notion_property_read_cell(
    read,
    row,
    0,
    cell_test_limits(),
    1000,
  ).unwrap()
  assert_eq(@admitted.canonical_scalar_text(value, 32), Some("low"))
  for
    native in [
      "{\"type\":\"string\",\"string\":\"high\"}", "{\"type\":\"number\",\"number\":1}",
      "{\"type\":\"unsupported\",\"unsupported\":{}}",
    ] {
    let row = cell_test_row(source, cell_test_scalar_native("formula", native))
    assert_true(
      admit_notion_property_read_cell(read, row, 0, cell_test_limits(), 1000)
      is Err(_),
    )
  }
}

///|
test "Notion timestamp normalizes the exact original offset and never drops an undeclared range end" {
  let source = cell_test_scalar_source("date")
  let read = cell_test_scalar_binding(
    source, "{\"type\":\"timestamp\",\"nullable\":false}", "start",
  )
  let native = "{\"start\":\"2026-10-17T10:00:00+09:00\",\"end\":null,\"time_zone\":null}"
  let row = cell_test_row(source, cell_test_scalar_native("date", native))
  let (value, _, _) = admit_notion_property_read_cell(
    read,
    row,
    0,
    cell_test_limits(),
    1000,
  ).unwrap()
  assert_eq(
    @admitted.canonical_scalar_text(value, 32),
    Some("2026-10-17T01:00:00.000Z"),
  )
  assert_eq(
    notion_query_property_value_json(
      notion_query_row_property_at(row, 0).unwrap(),
      1024,
    ),
    Ok(native),
  )
  for
    native in [
      "{\"start\":\"2026-10-17T10:00:00+09:00\",\"end\":\"2026-10-18T10:00:00+09:00\",\"time_zone\":null}",
      "{\"start\":\"2026-10-17T10:00:00\",\"end\":null,\"time_zone\":\"Asia/Tokyo\"}",
      "{\"start\":\"2026-10-17T10:00:00-00:00\",\"end\":null,\"time_zone\":null}",
      "{\"start\":\"2026-10-17T10:00:00.0000000001Z\",\"end\":null,\"time_zone\":null}",
    ] {
    let row = cell_test_row(source, cell_test_scalar_native("date", native))
    assert_true(
      admit_notion_property_read_cell(read, row, 0, cell_test_limits(), 1000)
      is Err(_),
    )
  }
}

///|
test "Notion timestamp property preserves exact fractional instants and native input" {
  let source = cell_test_scalar_source("date")
  let read = cell_test_scalar_binding(
    source, "{\"type\":\"timestamp\",\"nullable\":false}", "start",
  )
  for
    (original, expected) in [
      ("2026-10-17T00:00:00.0001Z", "2026-10-17T00:00:00.0001Z"),
      ("2026-10-17T09:00:00.000000001+09:00", "2026-10-17T00:00:00.000000001Z"),
    ] {
    let native = "{\"start\":\"" +
      original +
      "\",\"end\":null,\"time_zone\":null}"
    let row = cell_test_row(source, cell_test_scalar_native("date", native))
    let (value, _, _) = admit_notion_property_read_cell(
      read,
      row,
      0,
      cell_test_limits(),
      1000,
    ).unwrap()
    assert_eq(@admitted.canonical_scalar_text(value, 32), Some(expected))
    assert_eq(
      notion_query_property_value_json(
        notion_query_row_property_at(row, 0).unwrap(),
        1024,
      ),
      Ok(native),
    )
  }
}
