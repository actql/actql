///|
fn page_test_limits() -> NotionPageLimits {
  { metadata: database_test_limits(), max_text_bytes: 256, }
}

///|
fn page_test_wire(
  parent : String,
  flags? : String = "\"in_trash\":false",
) -> String {
  "{\"object\":\"page\",\"id\":\"p\",\"parent\":" +
  parent +
  ",\"url\":\"https://notion.example/p\",\"created_by\":{\"object\":\"user\",\"id\":\"creator\"}," +
  "\"last_edited_by\":{\"object\":\"user\",\"id\":\"editor\"}," +
  "\"created_time\":\"2026-10-17T10:00:00+09:00\",\"last_edited_time\":\"2026-10-17T00:00:00.123000Z\"," +
  flags +
  ",\"properties\":{\"Title\":{\"id\":\"title\",\"type\":\"title\",\"title\":[]}}}"
}

///|
fn page_test_original() -> String {
  page_test_wire(
    "{\"type\":\"data_source_id\",\"data_source_id\":\"source\",\"database_id\":\"database\"}",
  )
}

///|
test "Notion original page retains raw response property occurrence and exact version separately from UTC" {
  let wire = " \r\n" + page_test_original() + "\n"
  let raw = @utf8.encode(wire)
  let page = project_notion_page(raw, "p", page_test_limits()).unwrap()
  assert_eq(page.id, "p")
  assert_eq(page.parent, DataSource("source", Some("database")))
  assert_eq(page.url, "https://notion.example/p")
  assert_eq(page.created_by, "creator")
  assert_eq(page.last_edited_by, "editor")
  assert_eq(page.created_time, "2026-10-17T01:00:00.000Z")
  assert_eq(page.last_edited_time, "2026-10-17T00:00:00.123Z")
  assert_eq(page.version, "2026-10-17T00:00:00.123000Z")
  assert_eq(page.response_sha256, @sha.hex(raw))
  assert_eq(notion_page_original_json(page, raw.length()), Ok(wire))
  assert_eq(
    @decode.object_length(notion_page_properties_original(page)),
    Some(1),
  )
  assert_eq(@decode.object_length(notion_page_original(page)), Some(10))
  assert_true(!physical_equal(page.raw, raw))
  let other = project_notion_page(raw, "p", page_test_limits()).unwrap()
  assert_true(!physical_equal(page, other))
  assert_eq(other.response_sha256, page.response_sha256)
}

///|
test "Notion page preserves every documented tagged parent without representative ids" {
  for
    (wire, expected) in [
      ("{\"type\":\"workspace\",\"workspace\":true}", Workspace),
      ("{\"type\":\"page_id\",\"page_id\":\"parent\"}", Page("parent")),
      ("{\"type\":\"database_id\",\"database_id\":\"db\"}", Database("db")),
      ("{\"type\":\"block_id\",\"block_id\":\"block\"}", Block("block")),
      ("{\"type\":\"agent_id\",\"agent_id\":\"agent\"}", Agent("agent")),
      (
        "{\"type\":\"data_source_id\",\"data_source_id\":\"s\"}",
        DataSource("s", None),
      ),
      (
        "{\"type\":\"data_source_id\",\"data_source_id\":\"s\",\"database_id\":\"db\"}",
        DataSource("s", Some("db")),
      ),
    ] {
    let page = project_notion_page(
      @utf8.encode(page_test_wire(wire)),
      "p",
      page_test_limits(),
    ).unwrap()
    assert_eq(page.parent, expected)
  }
}

///|
test "Notion original page refuses malformed mixed or fabricated parent coordinates" {
  for
    parent in [
      "null", "{}", "{\"type\":\"future\",\"future\":\"id\"}", "{\"type\":\"workspace\",\"workspace\":false}",
      "{\"type\":\"workspace\",\"workspace\":true,\"id\":\"invented\"}", "{\"type\":\"page_id\",\"page_id\":\"\"}",
      "{\"type\":\"page_id\",\"page_id\":\"p\",\"block_id\":\"b\"}", "{\"type\":\"data_source_id\",\"data_source_id\":\"s\",\"database_id\":null}",
    ] {
    assert_eq(
      project_notion_page(
        @utf8.encode(page_test_wire(parent)),
        "p",
        page_test_limits(),
      ).unwrap_err(),
      InvalidParent,
    )
  }
}

///|
test "Notion page trash status is observed and deprecated alias never supplies a false default" {
  let parent = "{\"type\":\"workspace\",\"workspace\":true}"
  for
    (flags, expected) in [
      ("\"in_trash\":true", true),
      ("\"archived\":true", true),
      ("\"in_trash\":false,\"archived\":false", false),
      ("\"in_trash\":true,\"archived\":true", true),
    ] {
    let page = project_notion_page(
      @utf8.encode(page_test_wire(parent, flags~)),
      "p",
      page_test_limits(),
    ).unwrap()
    assert_eq(page.archived, expected)
  }
  for
    flags in [
      "\"unrelated\":true", "\"in_trash\":null", "\"archived\":\"false\"", "\"in_trash\":true,\"archived\":false",
    ] {
    assert_true(
      project_notion_page(
        @utf8.encode(page_test_wire(parent, flags~)),
        "p",
        page_test_limits(),
      )
      is Err(_),
    )
  }
}

///|
test "Notion page is bound to the exact requested id and rejects partial page responses" {
  let raw = @utf8.encode(page_test_original())
  assert_eq(
    project_notion_page(raw, "other", page_test_limits()).unwrap_err(),
    ForeignPage,
  )
  assert_eq(
    project_notion_page(raw, "", page_test_limits()).unwrap_err(),
    ForeignPage,
  )
  for
    wire in [
      "{\"object\":\"page\",\"id\":\"p\"}",
      page_test_original().replace_all(old="\"page\"", new="\"database\""),
      page_test_original().replace_all(
        old="\"url\":\"https://notion.example/p\"",
        new="\"url\":null",
      ),
      page_test_original().replace_all(
        old="\"created_by\":{\"object\":\"user\",\"id\":\"creator\"}",
        new="\"created_by\":{\"id\":\"creator\"}",
      ),
      page_test_original().replace_all(
        old="\"properties\":{",
        new="\"missing_properties\":{",
      ),
    ] {
    assert_true(
      project_notion_page(@utf8.encode(wire), "p", page_test_limits()) is Err(_),
    )
  }
}

///|
test "Notion page temporal conversion refuses unknown offsets precision loss and invalid dates" {
  for
    invalid in [
      "2026-10-17T00:00:00-00:00", "2026-10-17T00:00:00.0000000001Z", "2026-02-29T00:00:00Z",
      "2026-10-17T00:00:00",
    ] {
    let wire = page_test_original().replace_all(
      old="2026-10-17T00:00:00.123000Z",
      new=invalid,
    )
    assert_eq(
      project_notion_page(@utf8.encode(wire), "p", page_test_limits()).unwrap_err(),
      InvalidField("last_edited_time"),
    )
  }
}

///|
test "Notion page bounds cover raw bytes all properties identities nodes depth and output" {
  let raw = @utf8.encode(page_test_original())
  let limits = page_test_limits()
  let exact = {
    ..limits,
    metadata: { ..limits.metadata, max_bytes: raw.length(), },
  }
  let page = project_notion_page(raw, "p", exact).unwrap()
  assert_eq(
    project_notion_page(raw, "p", {
      ..exact,
      metadata: { ..exact.metadata, max_bytes: raw.length() - 1, },
    }).unwrap_err(),
    BudgetExceeded,
  )
  for
    metadata in [
      { ..limits.metadata, max_nodes: 1, },
      { ..limits.metadata, max_depth: 1, },
      { ..limits.metadata, max_identity_bytes: 1, },
      { ..limits.metadata, max_properties: 0, },
    ] {
    assert_eq(
      project_notion_page(raw, "p", { ..limits, metadata, }).unwrap_err(),
      BudgetExceeded,
    )
  }
  assert_eq(
    project_notion_page(raw, "p", { ..limits, max_text_bytes: 1, }).unwrap_err(),
    BudgetExceeded,
  )
  assert_eq(
    project_notion_page(raw, "p", { ..limits, max_text_bytes: 0, }).unwrap_err(),
    InvalidLimits,
  )
  assert_eq(
    notion_page_original_json(page, raw.length() - 1),
    Err(BudgetExceeded),
  )
  assert_eq(notion_page_original_json(page, 0), Err(InvalidLimits))
}

///|
test "Notion page preserves Unicode names exact numeric tokens and unknown property DATA without typed claims" {
  let wire = page_test_original().replace_all(
    old="\"Title\":{\"id\":\"title\",\"type\":\"title\",\"title\":[]}",
    new="\"é😀\":{\"id\":\"x\",\"type\":\"future\",\"future\":9007199254740993.25}",
  )
  let page = project_notion_page(@utf8.encode(wire), "p", page_test_limits()).unwrap()
  assert_eq(notion_page_original_json(page, 8192), Ok(wire))
  assert_eq(
    @decode.field_at(notion_page_properties_original(page), 0).unwrap().0,
    "é😀",
  )
  assert_true(
    notion_page_original_json(page, 8192)
    .unwrap()
    .contains("9007199254740993.25"),
  )
  let malformed = wire.replace_all(old="é😀", new="\\ud800")
  assert_eq(
    project_notion_page(@utf8.encode(malformed), "p", page_test_limits()).unwrap_err(),
    InvalidResponse,
  )
}

///|
test "Notion page metadata projection keeps original parent tags version and bounded output" {
  let raw = @utf8.encode(page_test_original())
  let page = project_notion_page(raw, "p", page_test_limits()).unwrap()
  let expected = "{\"id\":\"p\",\"resource\":\"p\",\"version\":\"2026-10-17T00:00:00.123000Z\",\"url\":\"https://notion.example/p\",\"created_by\":\"creator\",\"last_edited_by\":\"editor\",\"created_time\":\"2026-10-17T01:00:00.000Z\",\"last_edited_time\":\"2026-10-17T00:00:00.123Z\",\"responseSha256\":\"" +
    @sha.hex(raw) +
    "\",\"archived\":false,\"parent\":{\"type\":\"data_source_id\",\"data_source_id\":\"source\",\"database_id\":\"database\"}}"
  let bytes = @utf8.encode(expected).length()
  // The existing writer counts open containers, not scalar leaf depth.
  assert_eq(notion_page_metadata_wire(page, bytes, 15, 2), Ok(expected))
  assert_eq(
    notion_page_metadata_wire(page, bytes - 1, 15, 3),
    Err(BudgetExceeded),
  )
  assert_eq(notion_page_metadata_wire(page, bytes, 14, 3), Err(BudgetExceeded))
  assert_eq(notion_page_metadata_wire(page, bytes, 15, 1), Err(BudgetExceeded))
  assert_eq(notion_page_metadata_wire(page, 0, 15, 3), Err(InvalidLimits))
  for
    parent in [
      "{\"type\":\"workspace\",\"workspace\":true}", "{\"type\":\"page_id\",\"page_id\":\"p\"}",
      "{\"type\":\"database_id\",\"database_id\":\"db\"}", "{\"type\":\"block_id\",\"block_id\":\"b\"}",
      "{\"type\":\"agent_id\",\"agent_id\":\"a\"}", "{\"type\":\"data_source_id\",\"data_source_id\":\"s\"}",
    ] {
    let original = project_notion_page(
      @utf8.encode(page_test_wire(parent)),
      "p",
      page_test_limits(),
    ).unwrap()
    assert_true(
      notion_page_metadata_wire(original, 2048, 15, 3)
      .unwrap()
      .contains("\"parent\":" + parent),
    )
  }
}

///|
test "Notion page retained canonical time and every UTF8 property name remain bounded" {
  let limits = page_test_limits()
  let wire = page_test_original()
    .replace_all(old="https://notion.example/p", new="x")
    .replace_all(old="2026-10-17T10:00:00+09:00", new="2026-10-17T00:00:00Z")
    .replace_all(old="2026-10-17T00:00:00.123000Z", new="2026-10-17T00:00:00Z")
  assert_eq(
    project_notion_page(@utf8.encode(wire), "p", {
      ..limits,
      max_text_bytes: 20,
    }).unwrap_err(),
    BudgetExceeded,
  )
  assert_true(
    project_notion_page(@utf8.encode(wire), "p", {
      ..limits,
      max_text_bytes: 24,
    })
    is Ok(_),
  )
  let unicode = page_test_original().replace_all(
    old="\"Title\"",
    new="\"é😀\"",
  )
  assert_eq(
    project_notion_page(@utf8.encode(unicode), "p", {
      ..limits,
      metadata: { ..limits.metadata, max_name_bytes: 6, },
    }).unwrap_err(),
    BudgetExceeded,
  )
  assert_true(
    project_notion_page(@utf8.encode(unicode), "p", {
      ..limits,
      metadata: { ..limits.metadata, max_name_bytes: 7, },
    })
    is Ok(_),
  )
}

///|
test "Notion page preserves exact fractional instants and original version spelling" {
  for
    (original, expected) in [
      ("2026-10-17T00:00:00.0001Z", "2026-10-17T00:00:00.0001Z"),
      ("2026-10-17T09:00:00.000000001+09:00", "2026-10-17T00:00:00.000000001Z"),
    ] {
    let wire = page_test_original().replace_all(
      old="2026-10-17T00:00:00.123000Z",
      new=original,
    )
    let raw = @utf8.encode(wire)
    let page = project_notion_page(raw, "p", page_test_limits()).unwrap()
    assert_eq(page.last_edited_time, expected)
    assert_eq(page.version, original)
    assert_eq(notion_page_original_json(page, raw.length()), Ok(wire))
  }
}
