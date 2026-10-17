///|
fn read_test_limits() -> NotionReadContractLimits {
  {
    metadata: database_test_limits(),
    contracts: { max_nodes: 100, max_depth: 16, max_text_bytes: 1024, },
    max_columns: 16,
    max_work: 10000,
  }
}

///|
fn read_test_wire() -> String {
  (
    #|{"id":"db","data_source_id":"s2","read_contracts":{"t%3Ax":[{"column":"title","projection":"value","contract":{"type":"string","nullable":false}}],"n":[{"column":"amount","projection":"value","contract":{"type":"decimal","nullable":true,"precision":20,"scale":2}}]}}
  )
}

///|
fn read_test_declaration() -> NotionDatabaseReadDeclaration {
  read_notion_database_read_declaration(
    @utf8.encode(read_test_wire()),
    read_test_limits(),
  ).unwrap()
}

///|
test "Notion original read declaration supplies exact Common decimal contract and explicit Unicode alias" {
  let declaration = read_test_declaration()
  let source = query_test_source()
  let read = bind_notion_data_source_read_contracts(
    declaration,
    source,
    read_test_limits(),
  ).unwrap()
  assert_true(notion_data_source_read_matches(read, declaration, source))
  assert_true(
    !notion_data_source_read_matches(read, read_test_declaration(), source),
  )
  assert_true(
    !notion_data_source_read_matches(read, declaration, query_test_source()),
  )
  assert_eq(
    notion_database_read_source_index(declaration, database_test_original()),
    Ok(1),
  )
  assert_eq(notion_data_source_read_column_count(read), 2)
  let title = notion_data_source_read_column_at(read, 0).unwrap()
  assert_eq((title.name, title.projection), ("title", Value))
  assert_eq(title.property.name, "é")
  assert_true(physical_equal(title.property, source.properties[0]))
  let amount = notion_data_source_read_column_at(read, 1).unwrap()
  assert_eq(amount.name, "amount")
  assert_true(amount.contract.shape is Decimal(precision=20, scale=2))
  assert_true(amount.contract.nullable)
  assert_true(notion_data_source_read_column_at(read, -1) is None)
  assert_true(notion_data_source_read_column_at(read, 2) is None)
  let rendered = @contract.stringify_checked(
    notion_data_source_read_schema(read),
    4096,
    100,
    16,
  )
  assert_true(rendered.contains("\"precision\":20"))
  assert_true(rendered.contains("\"scale\":2"))
  assert_eq(
    @decode.object_length(
      notion_database_read_declaration_original(declaration),
    ),
    Some(3),
  )
}

///|
test "Notion singleton shorthand never selects the first of multiple original sources" {
  let declaration = read_notion_database_read_declaration(
    b"\"db\"",
    read_test_limits(),
  ).unwrap()
  assert_eq(
    notion_database_read_source_index(declaration, database_test_original()),
    Err(InvalidSelection),
  )
  let one = project_notion_database(
    b"{\"object\":\"database\",\"id\":\"db\",\"data_sources\":[{\"id\":\"only\",\"name\":\"tasks\"}]}",
    database_test_limits(),
  ).unwrap()
  assert_eq(notion_database_read_source_index(declaration, one), Ok(0))
  let source = project_notion_data_source(
    one,
    0,
    b"{\"object\":\"data_source\",\"id\":\"only\",\"parent\":{\"type\":\"database_id\",\"database_id\":\"db\"},\"properties\":{\"done\":{\"id\":\"check\",\"name\":\"done\",\"type\":\"checkbox\",\"checkbox\":{}}}}",
    database_test_limits(),
  ).unwrap()
  let read = bind_notion_data_source_read_contracts(
    declaration,
    source,
    read_test_limits(),
  ).unwrap()
  assert_true(
    notion_data_source_read_column_at(read, 0).unwrap().contract.shape
    is Boolean,
  )
  assert_true(
    !notion_data_source_read_column_at(read, 0).unwrap().contract.nullable,
  )
  assert_eq(
    notion_database_read_source_index(read_test_declaration(), one),
    Err(InvalidSelection),
  )
  let foreign = read_notion_database_read_declaration(
    b"\"foreign\"",
    read_test_limits(),
  ).unwrap()
  assert_eq(
    notion_database_read_source_index(foreign, one),
    Err(ForeignDatabase),
  )
}

///|
test "Notion ambiguous number never acquires precision from its display format" {
  let source = query_test_source()
  let declaration = read_notion_database_read_declaration(
    b"{\"id\":\"db\",\"data_source_id\":\"s2\"}",
    read_test_limits(),
  ).unwrap()
  assert_eq(
    bind_notion_data_source_read_contracts(
      declaration,
      source,
      read_test_limits(),
    ).unwrap_err(),
    MissingContract("n"),
  )
  let wrong = read_test_wire().replace(
    old="\"type\":\"decimal\",\"nullable\":true,\"precision\":20,\"scale\":2",
    new="\"type\":\"number\",\"nullable\":true",
  )
  let declaration = read_notion_database_read_declaration(
    @utf8.encode(wrong),
    read_test_limits(),
  ).unwrap()
  assert_eq(
    bind_notion_data_source_read_contracts(
      declaration,
      source,
      read_test_limits(),
    ).unwrap_err(),
    InvalidProperty("n"),
  )
}

///|
test "Notion read declaration checks unused contracts closed fields and all original ids" {
  for
    bytes in [
      b"null", b"[]", b"{}", b"{\"id\":\"db\",\"extra\":false}", b"{\"id\":\"db\",\"data_source_id\":null}",
      b"{\"id\":\"db\",\"read_contracts\":null}", b"{\"id\":\"db\",\"read_contracts\":{\"n\":[]}}",
      b"{\"id\":\"db\",\"read_contracts\":{\"unused\":[{\"column\":\"x\",\"projection\":\"value\",\"contract\":{\"type\":\"not-a-type\",\"nullable\":true}}]}}",
      b"{\"id\":\"db\",\"read_contracts\":{\"\":[{\"column\":\"x\",\"projection\":\"value\",\"contract\":{\"type\":\"string\",\"nullable\":true}}]}}",
      b"{\"id\":\"db\",\"unique\":null}", b"{\"id\":\"db\",\"marker\":false}",
    ] {
    assert_true(
      read_notion_database_read_declaration(bytes, read_test_limits()) is Err(_),
    )
  }
  let unknown = read_test_wire().replace(old="\"n\":[", new="\"unknown\":[")
  let declaration = read_notion_database_read_declaration(
    @utf8.encode(unknown),
    read_test_limits(),
  ).unwrap()
  assert_true(
    bind_notion_data_source_read_contracts(
      declaration,
      query_test_source(),
      read_test_limits(),
    )
    is Err(_),
  )
  let duplicate = read_test_wire().replace(
    old="\"column\":\"amount\"",
    new="\"column\":\"title\"",
  )
  let declaration = read_notion_database_read_declaration(
    @utf8.encode(duplicate),
    read_test_limits(),
  ).unwrap()
  assert_eq(
    bind_notion_data_source_read_contracts(
      declaration,
      query_test_source(),
      read_test_limits(),
    ).unwrap_err(),
    InvalidColumn("names"),
  )
}

///|
test "Notion explicit date range columns retain contracts and reject mixed shape or end-only" {
  let database = database_test_original()
  let source = project_notion_data_source(
    database,
    1,
    b"{\"object\":\"data_source\",\"id\":\"s2\",\"parent\":{\"type\":\"database_id\",\"database_id\":\"db\"},\"properties\":{\"Due\":{\"id\":\"date\",\"name\":\"Due\",\"type\":\"date\",\"date\":{}}}}",
    database_test_limits(),
  ).unwrap()
  let wire =
    #|{"id":"db","data_source_id":"s2","read_contracts":{"date":[{"column":"due_start","projection":"start","contract":{"type":"date","nullable":false}},{"column":"due_end","projection":"end","contract":{"type":"date","nullable":true}}]}}
  let declaration = read_notion_database_read_declaration(
    @utf8.encode(wire),
    read_test_limits(),
  ).unwrap()
  let bound = bind_notion_data_source_read_contracts(
    declaration,
    source,
    read_test_limits(),
  ).unwrap()
  assert_eq(notion_data_source_read_column_count(bound), 2)
  assert_eq(
    notion_data_source_read_column_at(bound, 1).unwrap().projection,
    End,
  )
  assert_true(
    notion_data_source_read_column_at(bound, 1).unwrap().contract.nullable,
  )
  for
    changed in [
      wire.replace(old="\"projection\":\"end\"", new="\"projection\":\"start\""),
      wire.replace(
        old="\"type\":\"date\",\"nullable\":true",
        new="\"type\":\"timestamp\",\"nullable\":true",
      ),
    ] {
    let declaration = read_notion_database_read_declaration(
      @utf8.encode(changed),
      read_test_limits(),
    ).unwrap()
    assert_true(
      bind_notion_data_source_read_contracts(
        declaration,
        source,
        read_test_limits(),
      )
      is Err(_),
    )
  }
}

///|
test "Notion original read declaration and binding use aggregate finite limits" {
  let wire = @utf8.encode(read_test_wire())
  for
    limits in [
      { ..read_test_limits(), max_columns: 1, },
      { ..read_test_limits(), max_work: 1, },
      {
        ..read_test_limits(),
        contracts: { ..read_test_limits().contracts, max_nodes: 1, },
      },
      {
        ..read_test_limits(),
        metadata: { ..database_test_limits(), max_bytes: wire.length() - 1, },
      },
    ] {
    assert_true(read_notion_database_read_declaration(wire, limits) is Err(_))
  }
  assert_eq(
    bind_notion_data_source_read_contracts(
      read_test_declaration(),
      query_test_source(),
      { ..read_test_limits(), max_work: 1, },
    ).unwrap_err(),
    BudgetExceeded,
  )
}
