///|
test "Notion public database map retains exact ordered alias and declaration source spans" {
  let value = "{\r\n  \"marker\":\"actql_request\", \"id\":\"db\", \"unique\":\"external_id\"\r\n}"
  let wire = " {\r\n \"tasks\" : " + value + ", \"accounts\":\"db2\" }\r\n"
  let declarations = read_notion_database_read_declarations(
    @utf8.encode(wire),
    read_test_limits(),
    2,
  ).unwrap()
  assert_eq(notion_database_read_declarations_count(declarations), Some(2))
  assert_eq(
    notion_database_read_declarations_alias_at(declarations, 0),
    Some("tasks"),
  )
  assert_eq(
    notion_database_read_declarations_alias_at(declarations, 1),
    Some("accounts"),
  )
  let first = notion_database_read_declarations_at(declarations, 0).unwrap()
  assert_eq(
    notion_database_read_declaration_original_json(first, 4096),
    Ok(value),
  )
  assert_eq(
    notion_database_read_declaration_source_cid(first),
    "sha256:" + @sha.hex(@utf8.encode(value)),
  )
  assert_eq(
    notion_database_read_declarations_source_cid(declarations),
    Some("sha256:" + @sha.hex(@utf8.encode(wire))),
  )
  assert_eq(
    notion_database_read_declaration_original_json(
      notion_database_read_declarations_at(declarations, 1).unwrap(),
      4096,
    ),
    Ok("\"db2\""),
  )
  assert_true(notion_database_read_declarations_matches(declarations, 0, first))
  let equal = read_notion_database_read_declaration(
    @utf8.encode(value),
    read_test_limits(),
  ).unwrap()
  assert_true(
    !notion_database_read_declarations_matches(declarations, 0, equal),
  )
  let copy = { ..declarations, }
  assert_true(notion_database_read_declarations_count(copy) is None)
  assert_true(notion_database_read_declarations_at(copy, 0) is None)
  assert_true(notion_database_read_declarations_alias_at(copy, 0) is None)
  assert_true(notion_database_read_declarations_source_cid(copy) is None)
  assert_true(!notion_database_read_declarations_matches(copy, 0, first))
  assert_true(notion_database_read_declarations_at(declarations, -1) is None)
  assert_true(notion_database_read_declarations_at(declarations, 2) is None)
}

///|
test "Notion public database map keeps Unicode spelling empty maps and escaped value bytes" {
  let wire = "{\"é\":\"d\\u0062\",\"é\":\"db2\",\"😀\":\"db3\"}"
  let declarations = read_notion_database_read_declarations(
    @utf8.encode(wire),
    read_test_limits(),
    3,
  ).unwrap()
  assert_eq(
    notion_database_read_declarations_alias_at(declarations, 0),
    Some("é"),
  )
  assert_eq(
    notion_database_read_declarations_alias_at(declarations, 1),
    Some("é"),
  )
  assert_eq(
    notion_database_read_declarations_alias_at(declarations, 2),
    Some("😀"),
  )
  let declaration = notion_database_read_declarations_at(declarations, 0).unwrap()
  assert_eq(declaration.database_id, "db")
  assert_eq(
    notion_database_read_declaration_original_json(declaration, 4096),
    Ok("\"d\\u0062\""),
  )
  assert_eq(
    notion_database_read_declarations_count(
      read_notion_database_read_declarations(b"{}", read_test_limits(), 0).unwrap(),
    ),
    Some(0),
  )
}

///|
test "Notion public database map checks every unused member and exact alias duplication" {
  for
    wire in [
      "null", "[]", "\"db\"", "{\"a\":null}", "{\"\":\"db\"}", "{\"a\":\"db\",\"a\":\"db2\"}",
      "{\"a\":\"db\",\"\\u0061\":\"db2\"}", "{\"a\":\"db\",\"unused\":{\"id\":\"db2\",\"marker\":null}}",
      "{\"a\":\"db\",\"unused\":{\"id\":\"db2\",\"read_contracts\":{\"p\":[{\"column\":\"x\",\"projection\":\"value\",\"contract\":{\"type\":\"bad\",\"nullable\":false}}]}}}",
      "{\"a\":\"db\",\"unused\":{\"id\":\"db2\",\"extra\":true}}", "{} false", "{\"\\ud800\":\"db\"}",
    ] {
    assert_true(
      read_notion_database_read_declarations(
        @utf8.encode(wire),
        read_test_limits(),
        8,
      )
      is Err(_),
    )
  }
}

///|
test "Notion public database map shares aggregate work and keeps whole input bounds" {
  let wire = b"{\"a\":\"db\",\"b\":\"db2\"}"
  // Whole source bytes, aliases 2+2, value spans 4+5: exact work 33.
  let work = wire.length() + 2 + 2 + 4 + 5
  assert_true(
    read_notion_database_read_declarations(
      wire,
      { ..read_test_limits(), max_work: work, },
      2,
    )
    is Ok(_),
  )
  assert_true(
    read_notion_database_read_declarations(
      wire,
      { ..read_test_limits(), max_work: work - 1, },
      2,
    )
    is Err(BudgetExceeded),
  )
  assert_true(
    read_notion_database_read_declarations(wire, read_test_limits(), 1)
    is Err(BudgetExceeded),
  )
  assert_true(
    read_notion_database_read_declarations(wire, read_test_limits(), -1)
    is Err(InvalidLimits),
  )
  let limits = read_test_limits()
  assert_true(
    read_notion_database_read_declarations(
      wire,
      { ..limits, metadata: { ..limits.metadata, max_bytes: wire.length(), }, },
      2,
    )
    is Ok(_),
  )
  assert_true(
    read_notion_database_read_declarations(
      wire,
      {
        ..limits,
        metadata: { ..limits.metadata, max_bytes: wire.length() - 1, },
      },
      2,
    )
    is Err(Metadata(BudgetExceeded)),
  )
  assert_true(
    read_notion_database_read_declarations(
      wire,
      { ..limits, metadata: { ..limits.metadata, max_nodes: 1, }, },
      2,
    )
    is Err(_),
  )
  assert_true(
    read_notion_database_read_declarations(
      wire,
      { ..limits, metadata: { ..limits.metadata, max_depth: 1, }, },
      2,
    )
    is Ok(_),
  )
  let nested = b"{\"a\":{\"id\":\"db\"}}"
  assert_true(
    read_notion_database_read_declarations(
      nested,
      { ..limits, metadata: { ..limits.metadata, max_depth: 1, }, },
      1,
    )
    is Err(_),
  )
  assert_true(
    read_notion_database_read_declarations(
      nested,
      { ..limits, metadata: { ..limits.metadata, max_depth: 2, }, },
      1,
    )
    is Ok(_),
  )
}

///|
test "Notion public database map never resets checked Contract node and text budgets per alias" {
  let value = "{\"id\":\"db\",\"read_contracts\":{\"p\":[{\"column\":\"x\",\"projection\":\"value\",\"contract\":{\"type\":\"string\",\"nullable\":false,\"enum\":[\"ab\"]}}]}}"
  let limits = read_test_limits()
  let single = read_notion_database_read_declaration(
    @utf8.encode(value),
    limits,
  ).unwrap()
  let wire = "{\"a\":" + value + ",\"b\":" + value + "}"
  let declarations = read_notion_database_read_declarations(
    @utf8.encode(wire),
    limits,
    2,
  ).unwrap()
  let first = notion_database_read_declarations_at(declarations, 0).unwrap()
  assert_true(
    @contract.type_equal(
      first.columns[0].contract,
      single.columns[0].contract,
      1000,
    ),
  )
  let one_contract_nodes = 3
  assert_true(
    read_notion_database_read_declaration(@utf8.encode(value), {
      ..limits,
      contracts: { ..limits.contracts, max_nodes: one_contract_nodes, },
    })
    is Ok(_),
  )
  assert_true(
    read_notion_database_read_declarations(
      @utf8.encode(wire),
      {
        ..limits,
        contracts: { ..limits.contracts, max_nodes: one_contract_nodes, },
      },
      2,
    )
    is Err(_),
  )
  assert_true(
    read_notion_database_read_declaration(@utf8.encode(value), {
      ..limits,
      contracts: { ..limits.contracts, max_text_bytes: 8, },
    })
    is Ok(_),
  )
  assert_true(
    read_notion_database_read_declarations(
      @utf8.encode(wire),
      { ..limits, contracts: { ..limits.contracts, max_text_bytes: 8, }, },
      2,
    )
    is Err(_),
  )
}
