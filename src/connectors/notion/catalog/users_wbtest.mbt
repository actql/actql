///|
fn limits() -> NotionUserListLimits {
  {
    max_bytes: 8192,
    max_nodes: 512,
    max_depth: 16,
    max_rows: 100,
    max_cursor_bytes: 64,
    max_identity_bytes: 64,
    max_value_nodes: 400,
    max_value_text_bytes: 4096,
  }
}

///|
fn project(wire : String) -> Result[NotionUserListPage, NotionUserListIssue] {
  project_notion_user_list(@utf8.encode(wire), limits())
}

///|
fn refused(wire : String) -> Unit raise {
  match project(wire) {
    Err(_) => ()
    Ok(_) => fail("Expected complete original Notion page refusal")
  }
}

///|
fn issue(
  wire : String,
  bound : NotionUserListLimits,
) -> NotionUserListIssue raise {
  match project_notion_user_list(@utf8.encode(wire), bound) {
    Err(issue) => issue
    Ok(_) => fail("Expected exact Notion refusal")
  }
}

///|
test "Notion original user variants Unicode and field order survive checked projection" {
  let wire =
    #|{"object":"list","type":"user","user":{},"results":[{"object":"user","id":"p1","type":"person","name":"観測 é","person":{"email":"a@example.test","email_verified":true}},{"object":"user","id":"b1","type":"bot","name":null,"bot":{},"person":{"email":"not a person"}},{"object":"user","id":"partial","name":"partial","person":{"email":"no inferred type"}}],"has_more":true,"next_cursor":"a+/= é","request_id":"bounded extra"}
  let page = project(wire).unwrap()
  assert_eq(page.response_sha256, @sha.hex(@utf8.encode(wire)))
  assert_eq(page.next_cursor, Some("a+/= é"))
  assert_eq(notion_user_list_row_count(page), 3)
  assert_eq(notion_user_list_ids(page), ["p1", "b1", "partial"])
  assert_eq(
    notion_user_list_rows_wire(
      page,
      notion_user_list_column_names(),
      4096,
      100,
      8,
    ).unwrap(),
    (
      #|[{"id":"p1","name":"観測 é","type":"person","email":"a@example.test"},{"id":"b1","name":null,"type":"bot","email":null},{"id":"partial","name":"partial","type":null,"email":null}]
    ),
  )
  assert_eq(
    notion_user_list_rows_wire(page, ["email", "id"], 4096, 100, 8).unwrap(),
    (
      #|[{"email":"a@example.test","id":"p1"},{"email":null,"id":"b1"},{"email":null,"id":"partial"}]
    ),
  )
}

///|
test "Notion nullable absence preserves withheld email without manufacturing user kind" {
  let page = project(
    (
      #|{"object":"list","type":"user","user":{},"results":[{"object":"user","id":"p","type":"person","person":{}},{"object":"user","id":"u","type":null}],"has_more":false,"next_cursor":null}
    ),
  ).unwrap()
  assert_eq(
    notion_user_list_rows_wire(
      page,
      notion_user_list_column_names(),
      4096,
      100,
      8,
    ).unwrap(),
    (
      #|[{"id":"p","name":null,"type":"person","email":null},{"id":"u","name":null,"type":null,"email":null}]
    ),
  )
  let ids = notion_user_list_ids(page)
  ids[0] = "copy"
  assert_eq(notion_user_list_ids(page), ["p", "u"])
}

///|
test "Notion next cursor and has_more are a checked pair even on an empty page" {
  let terminal =
    #|{"object":"list","type":"user","user":{},"results":[],"has_more":false,"next_cursor":null}
  let page = project_notion_user_list(@utf8.encode(terminal), {
    ..limits(),
    max_rows: 0,
    max_value_nodes: 0,
    max_value_text_bytes: 0,
  }).unwrap()
  assert_eq(page.next_cursor, None)
  assert_eq(notion_user_list_row_count(page), 0)
  let page = project(
    (
      #|{"object":"list","type":"user","user":{},"results":[],"has_more":true,"next_cursor":"original"}
    ),
  ).unwrap()
  assert_eq(page.next_cursor, Some("original"))
  for
    suffix in [
      "\"has_more\":true,\"next_cursor\":null}", "\"has_more\":true,\"next_cursor\":\"\"}",
      "\"has_more\":false,\"next_cursor\":\"unused\"}", "\"has_more\":false}", "\"has_more\":true,\"next_cursor\":false}",
      "\"has_more\":true,\"next_cursor\":{}}", "\"has_more\":true,\"next_cursor\":3}",
    ] {
    refused(
      "{\"object\":\"list\",\"type\":\"user\",\"user\":{},\"results\":[]," +
      suffix,
    )
  }
}

///|
test "Notion API errors partial JSON duplicate keys and wrong list kinds refuse" {
  for
    body in [
      "{}", "null", "{\"object\":\"error\",\"status\":403,\"code\":\"restricted_resource\"}",
      "{\"object\":\"list\",\"type\":\"page_or_data_source\",\"user\":{},\"results\":[],\"has_more\":false,\"next_cursor\":null}",
      "{\"object\":\"list\",\"type\":\"user\",\"user\":null,\"results\":[],\"has_more\":false,\"next_cursor\":null}",
      "{\"object\":\"list\",\"type\":\"user\",\"user\":{},\"results\":{},\"has_more\":false,\"next_cursor\":null}",
      "{\"object\":\"list\",\"type\":\"user\",\"user\":{},\"results\":[],\"has_more\":\"false\",\"next_cursor\":null}",
      "{\"object\":\"list\",\"type\":\"user\",\"user\":{},\"results\":[],\"has_more\":false,\"next_cursor\":null,\"has_more\":false}",
      "{\"object\":\"list\",\"type\":\"user\",\"user\":{},\"results\":[],\"has_more\":false,\"next_cursor\":null}{}",
    ] {
    refused(body)
  }
  assert_true(project_notion_user_list(b"\xff\x80", limits()) is Err(_))
}

///|
test "Notion validates every declared cell and original variant before output selection" {
  for
    row in [
      "null", "{}", "{\"object\":\"page\",\"id\":\"p\"}", "{\"object\":\"user\",\"id\":\"\"}",
      "{\"object\":\"user\",\"id\":null}", "{\"object\":\"user\",\"id\":1}", "{\"object\":\"user\",\"id\":\"p\",\"name\":false}",
      "{\"object\":\"user\",\"id\":\"p\",\"type\":\"future\"}", "{\"object\":\"user\",\"id\":\"p\",\"type\":\"person\"}",
      "{\"object\":\"user\",\"id\":\"p\",\"type\":\"person\",\"person\":null}", "{\"object\":\"user\",\"id\":\"p\",\"type\":\"person\",\"person\":{\"email\":false}}",
      "{\"object\":\"user\",\"id\":\"p\",\"type\":\"bot\",\"bot\":false}", "{\"object\":\"user\",\"id\":\"p\",\"id\":\"q\"}",
    ] {
    refused(
      "{\"object\":\"list\",\"type\":\"user\",\"user\":{},\"has_more\":false,\"next_cursor\":null,\"results\":[" +
      row +
      "]}",
    )
  }
}

///|
test "Notion duplicate identities and page bounds cannot become truncated success" {
  let row = "{\"object\":\"user\",\"id\":\"original\"}"
  let body = "{\"object\":\"list\",\"type\":\"user\",\"user\":{},\"has_more\":false,\"next_cursor\":null,\"results\":[" +
    row +
    "," +
    row +
    "]}"
  assert_eq(issue(body, limits()), DuplicateUser)
  let body = "{\"object\":\"list\",\"type\":\"user\",\"user\":{},\"has_more\":false,\"next_cursor\":null,\"results\":[" +
    row +
    "]}"
  assert_eq(issue(body, { ..limits(), max_rows: 0, }), BudgetExceeded)
  let mut many = "{\"object\":\"list\",\"type\":\"user\",\"user\":{},\"has_more\":false,\"next_cursor\":null,\"results\":["
  for index in 0..<101 {
    if index != 0 {
      many += ","
    }
    many += "{\"object\":\"user\",\"id\":\"" + index.to_string() + "\"}"
  }
  many += "]}"
  assert_eq(
    issue(many, { ..limits(), max_rows: 1000, max_nodes: 1000, }),
    InvalidResponse,
  )
}

///|
test "Notion exact cell text node identity and response byte boundaries retain full refusal" {
  let body =
    #|{"object":"list","type":"user","user":{},"results":[{"object":"user","id":"u","name":"N","type":"person","person":{"email":"a"}}],"has_more":false,"next_cursor":null}
  assert_true(
    project_notion_user_list(@utf8.encode(body), {
      ..limits(),
      max_value_nodes: 4,
      max_value_text_bytes: 9,
      max_bytes: @utf8.encode(body).length(),
    })
    is Ok(_),
  )
  assert_eq(issue(body, { ..limits(), max_value_nodes: 3, }), BudgetExceeded)
  assert_eq(
    issue(body, { ..limits(), max_value_text_bytes: 8, }),
    BudgetExceeded,
  )
  assert_eq(
    issue(body, { ..limits(), max_bytes: @utf8.encode(body).length() - 1, }),
    BudgetExceeded,
  )
  let cursor =
    #|{"object":"list","type":"user","user":{},"results":[],"has_more":true,"next_cursor":"é"}
  assert_true(
    project_notion_user_list(@utf8.encode(cursor), {
      ..limits(),
      max_cursor_bytes: 2,
    })
    is Ok(_),
  )
  assert_eq(issue(cursor, { ..limits(), max_cursor_bytes: 1, }), BudgetExceeded)
  let identity =
    #|{"object":"list","type":"user","user":{},"results":[{"object":"user","id":"é"}],"has_more":false,"next_cursor":null}
  assert_true(
    project_notion_user_list(@utf8.encode(identity), {
      ..limits(),
      max_identity_bytes: 2,
    })
    is Ok(_),
  )
  assert_eq(
    issue(identity, { ..limits(), max_identity_bytes: 1, }),
    BudgetExceeded,
  )
}

///|
test "Notion schema and output budgets are owned contracts not caller-selected cells" {
  let page = project(
    (
      #|{"object":"list","type":"user","user":{},"results":[{"object":"user","id":"p"}],"has_more":false,"next_cursor":null}
    ),
  ).unwrap()
  assert_eq(
    notion_user_list_rows_wire(page, ["email", "id"], 1024, 20, 8).unwrap(),
    "[{\"email\":null,\"id\":\"p\"}]",
  )
  assert_eq(
    notion_user_list_rows_wire(page, ["id", "id"], 1024, 20, 8),
    Err(InvalidSelection("id")),
  )
  assert_eq(
    notion_user_list_rows_wire(page, ["grant"], 1024, 20, 8),
    Err(InvalidSelection("grant")),
  )
  assert_eq(
    notion_user_list_rows_wire(page, ["id"], 1, 20, 8),
    Err(BudgetExceeded),
  )
  assert_eq(
    notion_user_list_schema_wire(2048, 100, 8).unwrap(),
    "{\"email\":{\"nullable\":true,\"type\":\"string\"},\"id\":{\"nullable\":false,\"type\":\"string\"},\"name\":{\"nullable\":true,\"type\":\"string\"},\"type\":{\"nullable\":true,\"type\":\"string\"}}",
  )
  assert_eq(notion_user_list_schema_wire(1, 100, 8), Err(BudgetExceeded))
}

///|
test "Notion cursor metadata uses exact bounded writer output" {
  let page = project(
    (
      #|{"object":"list","type":"user","user":{},"results":[],"has_more":true,"next_cursor":"é"}
    ),
  ).unwrap()
  let expected = "{\"nextCursor\":\"é\",\"rowCount\":0}"
  let bytes = @utf8.encode(expected).length()
  assert_eq(
    notion_user_list_metadata_wire(page, bytes, 20, 8).unwrap(),
    expected,
  )
  assert_eq(
    notion_user_list_metadata_wire(page, bytes - 1, 20, 8),
    Err(BudgetExceeded),
  )
  assert_eq(
    notion_user_list_metadata_wire(page, bytes, 1, 8),
    Err(BudgetExceeded),
  )
}

///|
test "Notion user key declaration matches the original checked id inventory" {
  assert_eq(
    notion_user_list_facts_wire(),
    "{\"relation_keys\":{\"candidate_keys\":[[\"id\"]]}}",
  )
}
