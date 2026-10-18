///|
fn public_connection_wire(databases : String) -> String {
  "{\"connector\":\"notion\",\"databases\":" +
  databases +
  ",\"credentials\":{\"integration_token\":{\"env\":\"N\"}}}"
}

///|
test "Notion public connection retains original map and credential reference without normalization" {
  let declaration = "{\r\n \"id\": \"d\\u0062\", \"unique\":\"external_id\"\r\n}"
  let map = "{ \"é\":" + declaration + ", \"é\":\"db2\" }"
  let wire = " \r\n" + public_connection_wire(map) + "\n"
  let connection = read_notion_public_connection(
    @utf8.encode(wire),
    read_test_limits(),
    2,
    128,
  ).unwrap()
  assert_eq(notion_public_connection_original_json(connection, 4096), Ok(wire))
  assert_eq(
    notion_public_connection_source_cid(connection),
    Ok("sha256:" + @sha.hex(@utf8.encode(wire))),
  )
  assert_eq(notion_public_connection_credential_kind(connection), Ok("env"))
  assert_eq(notion_public_connection_credential_reference(connection), Ok("N"))
  let databases = notion_public_connection_databases(connection)
    .unwrap()
    .unwrap()
  assert_eq(notion_database_read_declarations_count(databases), Some(2))
  assert_eq(
    notion_database_read_declarations_alias_at(databases, 0),
    Some("é"),
  )
  assert_eq(
    notion_database_read_declarations_alias_at(databases, 1),
    Some("é"),
  )
  assert_eq(
    notion_database_read_declarations_source_cid(databases),
    Some("sha256:" + @sha.hex(@utf8.encode(map))),
  )
  let first = notion_database_read_declarations_at(databases, 0).unwrap()
  assert_eq(
    notion_database_read_declaration_original_json(first, 4096),
    Ok(declaration),
  )
  assert_eq(
    notion_database_read_declaration_source_cid(first),
    "sha256:" + @sha.hex(@utf8.encode(declaration)),
  )
  let equal = read_notion_public_connection(
    @utf8.encode(wire),
    read_test_limits(),
    2,
    128,
  ).unwrap()
  assert_true(
    !notion_database_read_declarations_matches(
      notion_public_connection_databases(equal).unwrap().unwrap(),
      0,
      first,
    ),
  )
  let copied = { ..connection, }
  assert_eq(notion_public_connection_source_cid(copied), Err(ForeignOriginal))
  assert_true(
    notion_public_connection_databases(copied) is Err(ForeignOriginal),
  )
  assert_eq(
    notion_public_connection_credential_kind(copied),
    Err(ForeignOriginal),
  )
  assert_eq(
    notion_public_connection_credential_reference(copied),
    Err(ForeignOriginal),
  )
  assert_eq(
    notion_public_connection_original_json(copied, 4096),
    Err(ForeignOriginal),
  )
}

///|
test "Notion public connection preserves absent and empty databases and exact file reference" {
  let absent = read_notion_public_connection(
    @utf8.encode(
      "{\"connector\":\"notion\",\"credentials\":{\"integration_token\":{\"path\":\"./keys/notion.token\"}}}",
    ),
    read_test_limits(),
    0,
    128,
  ).unwrap()
  assert_true(notion_public_connection_databases(absent) is Ok(None))
  assert_eq(notion_public_connection_credential_kind(absent), Ok("path"))
  assert_eq(
    notion_public_connection_credential_reference(absent),
    Ok("./keys/notion.token"),
  )
  let empty = read_notion_public_connection(
    @utf8.encode(public_connection_wire("{}")),
    read_test_limits(),
    0,
    128,
  ).unwrap()
  assert_eq(
    notion_database_read_declarations_count(
      notion_public_connection_databases(empty).unwrap().unwrap(),
    ),
    Some(0),
  )
}

///|
test "Notion public connection rejects inline secret ambiguous reference and every invalid unused member" {
  for
    wire in [
      "{\"connector\":\"Notion\",\"credentials\":{\"integration_token\":{\"env\":\"N\"}}}",
      "{\"connector\":\"notion\"}",
      "{\"connector\":\"notion\",\"credentials\":{}}",
      "{\"connector\":\"notion\",\"credentials\":{\"integration_token\":\"secret\"}}",
      "{\"connector\":\"notion\",\"credentials\":{\"integration_token\":{\"env\":\"N\",\"path\":\"file\"}}}",
      "{\"connector\":\"notion\",\"credentials\":{\"integration_token\":{\"env\":null}}}",
      "{\"connector\":\"notion\",\"credentials\":{\"integration_token\":{\"env\":\"\"}}}",
      "{\"connector\":\"notion\",\"credentials\":{\"integration_token\":{\"env\":\"N\\u0000X\"}}}",
      "{\"connector\":\"notion\",\"credentials\":{\"integration_token\":{\"env\":\"N\"},\"other\":{\"env\":\"X\"}}}",
      "{\"connector\":\"notion\",\"credentials\":{\"integration_token\":{\"env\":\"N\"}},\"extra\":true}",
      public_connection_wire("null"),
      public_connection_wire("{\"a\":\"db\",\"a\":\"db2\"}"),
      public_connection_wire(
        "{\"a\":\"db\",\"unused\":{\"id\":\"db2\",\"marker\":null}}",
      ),
    ] {
    assert_true(
      read_notion_public_connection(
        @utf8.encode(wire),
        read_test_limits(),
        2,
        128,
      )
      is Err(_),
    )
  }
}

///|
test "Notion public connection charges exact work and complete input bounds before map admission" {
  let map = "{\"a\":\"db\"}"
  let wire = public_connection_wire(map)
  let bytes = @utf8.encode(wire)
  let limits = read_test_limits()
  let work = bytes.length() + 2 + @utf8.encode(map).length() + 2 + 4
  assert_true(
    read_notion_public_connection(bytes, { ..limits, max_work: work, }, 1, 1)
    is Ok(_),
  )
  assert_true(
    read_notion_public_connection(
      bytes,
      { ..limits, max_work: work - 1, },
      1,
      1,
    )
    is Err(BudgetExceeded),
  )
  assert_true(read_notion_public_connection(bytes, limits, 0, 1) is Err(_))
  assert_true(
    read_notion_public_connection(bytes, limits, 1, 0) is Err(InvalidLimits),
  )
  assert_true(
    read_notion_public_connection(
      bytes,
      {
        ..limits,
        metadata: { ..limits.metadata, max_bytes: bytes.length() - 1, },
      },
      1,
      1,
    )
    is Err(_),
  )
  assert_true(
    read_notion_public_connection(
      bytes,
      { ..limits, metadata: { ..limits.metadata, max_nodes: 1, }, },
      1,
      1,
    )
    is Err(_),
  )
  assert_true(
    read_notion_public_connection(
      bytes,
      { ..limits, metadata: { ..limits.metadata, max_depth: 2, }, },
      1,
      1,
    )
    is Err(_),
  )
  assert_true(
    read_notion_public_connection(
      bytes,
      { ..limits, metadata: { ..limits.metadata, max_depth: 3, }, },
      1,
      1,
    )
    is Ok(_),
  )
  let astral = "{\"connector\":\"notion\",\"credentials\":{\"integration_token\":{\"env\":\"N😀\"}}}"
  assert_true(
    read_notion_public_connection(@utf8.encode(astral), limits, 0, 4) is Err(_),
  )
  assert_true(
    read_notion_public_connection(@utf8.encode(astral), limits, 0, 5) is Ok(_),
  )
}

///|
test "Notion public connection retains the same aggregate checked Contract budget across aliases" {
  let declaration = "{\"id\":\"db\",\"read_contracts\":{\"p\":[{\"column\":\"x\",\"projection\":\"value\",\"contract\":{\"type\":\"string\",\"nullable\":false,\"enum\":[\"ab\"]}}]}}"
  let wire = public_connection_wire(
    "{\"a\":" + declaration + ",\"b\":" + declaration + "}",
  )
  let limits = read_test_limits()
  assert_true(
    read_notion_public_connection(@utf8.encode(wire), limits, 2, 128) is Ok(_),
  )
  assert_true(
    read_notion_public_connection(
      @utf8.encode(wire),
      { ..limits, contracts: { ..limits.contracts, max_nodes: 3, }, },
      2,
      128,
    )
    is Err(_),
  )
  assert_true(
    read_notion_public_connection(
      @utf8.encode(wire),
      { ..limits, contracts: { ..limits.contracts, max_text_bytes: 8, }, },
      2,
      128,
    )
    is Err(_),
  )
}
