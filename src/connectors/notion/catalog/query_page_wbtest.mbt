///|
fn query_test_source() -> NotionDataSourceCatalog {
  project_notion_data_source(
    database_test_original(),
    1,
    @utf8.encode(
      (
        #|{"object":"data_source","id":"s2","parent":{"type":"database_id","database_id":"db"},"properties":{"é":{"id":"t%3Ax","name":"é","type":"title","title":{}},"amount":{"id":"n","name":"amount","type":"number","number":{"format":"number"}}}}
      ),
    ),
    database_test_limits(),
  ).unwrap()
}

///|
fn query_test_limits() -> NotionQueryLimits {
  { metadata: database_test_limits(), max_rows: 100, max_cursor_bytes: 64, }
}

///|
fn query_test_row(id : String) -> String {
  "{\"object\":\"page\",\"id\":\"" +
  id +
  "\",\"parent\":{\"type\":\"data_source_id\",\"data_source_id\":\"s2\",\"database_id\":\"db\"},\"properties\":{\"é\":{\"id\":\"t%3Ax\",\"type\":\"title\",\"title\":[]},\"amount\":{\"id\":\"n\",\"type\":\"number\",\"number\":9007199254740993.25}}}"
}

///|
fn query_test_page(rows : String, cursor : String, has_more : String) -> String {
  "{\"object\":\"list\",\"type\":\"page_or_data_source\",\"page_or_data_source\":{},\"results\":[" +
  rows +
  "],\"has_more\":" +
  has_more +
  ",\"next_cursor\":" +
  cursor +
  "}"
}

///|
test "Notion query retains the selected original source complete properties and exact numeric token" {
  let source = query_test_source()
  let wire = query_test_page(query_test_row("page"), "\"next-token\"", "true")
  let bytes = @utf8.encode(wire)
  let page = project_notion_query_page(source, bytes, query_test_limits()).unwrap()
  assert_true(notion_query_page_matches_source(page, source))
  assert_true(!notion_query_page_matches_source(page, query_test_source()))
  assert_eq(page.response_sha256, @sha.hex(bytes))
  assert_eq(page.next_cursor, Some("next-token"))
  assert_eq(notion_query_page_row_count(page), 1)
  assert_true(notion_query_page_row_at(page, -1) is None)
  assert_true(notion_query_page_row_at(page, 1) is None)
  let row = notion_query_page_row_at(page, 0).unwrap()
  assert_true(notion_query_row_matches_source(row, source))
  assert_true(!notion_query_row_matches_source(row, query_test_source()))
  assert_eq(row.id, "page")
  assert_eq(notion_query_row_property_count(row), 2)
  let title = notion_query_row_property_at(row, 0).unwrap()
  assert_eq((title.metadata.name, title.metadata.id), ("é", "t%3Ax"))
  assert_eq(notion_query_property_value_json(title, 2), Ok("[]"))
  let amount = notion_query_row_property_at(row, 1).unwrap()
  assert_eq(
    notion_query_property_value_json(amount, 19),
    Ok("9007199254740993.25"),
  )
  assert_eq(notion_query_property_value_json(amount, 17), Err(BudgetExceeded))
  assert_eq(notion_query_page_original_json(page, bytes.length()), Ok(wire))
  assert_eq(notion_query_page_original_json(page, bytes.length()), Ok(wire))
  assert_eq(
    notion_query_property_value_json(amount, 19),
    Ok("9007199254740993.25"),
  )
  assert_eq(
    notion_query_page_metadata_wire(page, 128, 10, 4),
    Ok("{\"ids\":[\"page\"],\"nextCursor\":\"next-token\"}"),
  )
}

///|
test "Notion query distinguishes present null from missing and preserves complete native values" {
  let source = query_test_source()
  let row = query_test_row("page").replace(
    old="9007199254740993.25",
    new="null",
  )
  let page = project_notion_query_page(
    source,
    @utf8.encode(query_test_page(row, "null", "false")),
    query_test_limits(),
  ).unwrap()
  let value = notion_query_row_property_at(
    notion_query_page_row_at(page, 0).unwrap(),
    1,
  ).unwrap()
  assert_eq(notion_query_property_value_json(value, 4), Ok("null"))
  assert_true(
    @decode.field(
      @decode.open_object(notion_query_property_original(value)).unwrap(),
      "number",
    )
    is ExplicitNull,
  )
  assert_true(
    project_notion_query_page(
      source,
      @utf8.encode(
        query_test_page(
          row.replace(old=",\"number\":null", new=""),
          "null",
          "false",
        ),
      ),
      query_test_limits(),
    )
    is Err(_),
  )
  let incomplete = query_test_row("page").replace(
    old="\"title\":[]",
    new="\"title\":[{\"type\":\"text\",\"plain_text\":\"é\\r\\n\",\"text\":{\"content\":\"é\\r\\n\"}}],\"has_more\":true",
  )
  let original = project_notion_query_page(
    source,
    @utf8.encode(query_test_page(incomplete, "null", "false")),
    query_test_limits(),
  ).unwrap()
  let title = notion_query_row_property_at(
    notion_query_page_row_at(original, 0).unwrap(),
    0,
  ).unwrap()
  assert_eq(
    @decode.boolean(
      @decode.lookup(
        @decode.open_object(notion_query_property_original(title)).unwrap(),
        "has_more",
      ).unwrap(),
    ),
    Ok(true),
  )
  // DATA preserves truncation: this projection does not issue a complete
  // property, logical Value or permission to treat inline text as all text.
}

///|
test "Notion query rejects foreign parents duplicate pages and changed property originals" {
  let source = query_test_source()
  let row = query_test_row("page")
  assert_eq(
    project_notion_query_page(
      source,
      @utf8.encode(query_test_page(row + "," + row, "null", "false")),
      query_test_limits(),
    ).unwrap_err(),
    DuplicatePage("page"),
  )
  for
    changed in [
      row.replace(
        old="\"data_source_id\":\"s2\"",
        new="\"data_source_id\":\"s1\"",
      ),
      row.replace(
        old="\"database_id\":\"db\"",
        new="\"database_id\":\"foreign\"",
      ),
      row.replace(old="\"type\":\"data_source_id\"", new="\"type\":\"page_id\""),
      row.replace(old="\"id\":\"n\"", new="\"id\":\"foreign\""),
      row.replace(old="\"type\":\"number\"", new="\"type\":\"formula\""),
      row.replace(old="\"é\":", new="\"é\":"),
      row.replace(
        old="\"number\":9007199254740993.25",
        new="\"wrong\":9007199254740993.25",
      ),
    ] {
    assert_true(
      project_notion_query_page(
        source,
        @utf8.encode(query_test_page(changed, "null", "false")),
        query_test_limits(),
      )
      is Err(_),
    )
  }
}

///|
test "Notion query cursor terminal empty and malformed pairing are exact" {
  let source = query_test_source()
  let empty = project_notion_query_page(
    source,
    @utf8.encode(query_test_page("", "null", "false")),
    { ..query_test_limits(), max_rows: 0, },
  ).unwrap()
  assert_eq(notion_query_page_row_count(empty), 0)
  assert_eq(empty.next_cursor, None)
  for
    (cursor, more) in [
      ("null", "true"),
      ("\"\"", "true"),
      ("\"next\"", "false"),
      ("false", "true"),
      ("{}", "true"),
    ] {
    assert_eq(
      project_notion_query_page(
        source,
        @utf8.encode(query_test_page("", cursor, more)),
        query_test_limits(),
      ).unwrap_err(),
      InvalidCursor,
    )
  }
  assert_eq(
    project_notion_query_page(
      source,
      @utf8.encode(query_test_page("", "\"abcd\"", "true")),
      { ..query_test_limits(), max_cursor_bytes: 3, },
    ).unwrap_err(),
    BudgetExceeded,
  )
}

///|
test "Notion query budgets include all bytes nodes unknown metadata rows and output" {
  let source = query_test_source()
  let bytes = @utf8.encode(
    query_test_page(query_test_row("page"), "null", "false"),
  )
  let page = project_notion_query_page(source, bytes, {
    ..query_test_limits(),
    metadata: { ..database_test_limits(), max_bytes: bytes.length(), },
  }).unwrap()
  for
    metadata in [
      { ..database_test_limits(), max_bytes: bytes.length() - 1, },
      { ..database_test_limits(), max_nodes: 1, },
      { ..database_test_limits(), max_depth: 1, },
      { ..database_test_limits(), max_identity_bytes: 1, },
      { ..database_test_limits(), max_properties: 1, },
    ] {
    assert_eq(
      project_notion_query_page(source, bytes, {
        ..query_test_limits(),
        metadata,
      }).unwrap_err(),
      BudgetExceeded,
    )
  }
  assert_eq(
    project_notion_query_page(source, bytes, {
      ..query_test_limits(),
      max_rows: 0,
    }).unwrap_err(),
    BudgetExceeded,
  )
  for
    limits in [
      { ..query_test_limits(), max_rows: -1, },
      { ..query_test_limits(), max_cursor_bytes: 0, },
    ] {
    assert_eq(
      project_notion_query_page(source, bytes, limits).unwrap_err(),
      InvalidLimits,
    )
  }
  let metadata = notion_query_page_metadata_wire(page, 128, 10, 4).unwrap()
  assert_eq(
    notion_query_page_metadata_wire(
      page,
      @utf8.encode(metadata).length() - 1,
      10,
      4,
    ),
    Err(BudgetExceeded),
  )
  assert_eq(
    notion_query_page_metadata_wire(page, 128, 1, 4),
    Err(BudgetExceeded),
  )
  assert_eq(
    notion_query_page_original_json(page, bytes.length() - 1),
    Err(BudgetExceeded),
  )
}

///|
test "Notion query refuses malformed errors and unsupported nested source without partial rows" {
  let source = query_test_source()
  for
    bytes in [
      b"{}", b"null", b"\xff\x80", b"{\"object\":\"error\",\"status\":403}",
    ] {
    assert_true(
      project_notion_query_page(source, bytes, query_test_limits()) is Err(_),
    )
  }
  let nested = query_test_page(
    query_test_row("page") + ",{\"object\":\"data_source\",\"id\":\"nested\"}",
    "null",
    "false",
  )
  assert_eq(
    project_notion_query_page(source, @utf8.encode(nested), query_test_limits()).unwrap_err(),
    UnsupportedEntry("data_source"),
  )
  let missing = query_test_page("", "null", "false").replace(
    old="\"next_cursor\":null",
    new="\"other\":null",
  )
  assert_eq(
    project_notion_query_page(
      source,
      @utf8.encode(missing),
      query_test_limits(),
    ).unwrap_err(),
    InvalidCursor,
  )
}

///|
test "Notion capped status is refused before early or final query rows" {
  let source = query_test_source()
  for (cursor, more) in [("null", "false"), ("\"next\"", "true")] {
    for
      status in [
        "{\"type\":\"incomplete\",\"incomplete_reason\":\"query_result_limit_reached\"}",
        "{\"type\":\"incomplete\"}",
      ] {
      let wire = query_test_page(query_test_row("page"), cursor, more)
      let wire = wire[:wire.length() - 1].to_owned() +
        ",\"request_status\":" +
        status +
        "}"
      assert_true(
        project_notion_query_page(
          source,
          @utf8.encode(wire),
          query_test_limits(),
        )
        is Err(_),
      )
    }
  }
}

///|
test "Notion query status is optional typed provider DATA not a cursor alias" {
  let source = query_test_source()
  let base = query_test_page(query_test_row("page"), "null", "false")
  assert_true(
    project_notion_query_page(source, @utf8.encode(base), query_test_limits())
    is Ok(_),
  )
  for
    status in [
      "{\"type\":\"complete\"}", "{\"type\":\"complete\",\"incomplete_reason\":\"query_result_limit_reached\"}",
    ] {
    let wire = base[:base.length() - 1].to_owned() +
      ",\"request_status\":" +
      status +
      "}"
    let page = project_notion_query_page(
      source,
      @utf8.encode(wire),
      query_test_limits(),
    ).unwrap()
    assert_eq(notion_query_page_row_count(page), 1)
    assert_eq(
      notion_query_page_original_json(page, wire.length() * 3),
      Ok(wire),
    )
  }
  for
    status in [
      "null", "true", "[]", "\"complete\"", "{}", "{\"type\":null}", "{\"type\":\"future\"}",
      "{\"incomplete_reason\":\"query_result_limit_reached\"}", "{\"type\":\"complete\",\"incomplete_reason\":null}",
      "{\"type\":\"complete\",\"incomplete_reason\":\"future\"}", "{\"type\":\"complete\",\"extra\":true}",
    ] {
    let wire = base[:base.length() - 1].to_owned() +
      ",\"request_status\":" +
      status +
      "}"
    assert_true(
      project_notion_query_page(source, @utf8.encode(wire), query_test_limits())
      is Err(_),
    )
  }
}
