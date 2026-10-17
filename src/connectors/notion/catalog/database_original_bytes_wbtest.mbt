///|
fn original_database_test_wire() -> String {
  " \r\n{\"extra\":{\"n\":9007199254740993.25,\"escaped\":\"\\u0061\",\"unicode\":\"é😀\"}," +
  "\"object\":\"database\",\"id\":\"db\",\"data_sources\":[{\"name\":\"same\",\"id\":\"s1\"},{\"name\":\"same\",\"id\":\"s2\"}]}\n"
}

///|
test "Notion database keeps exact UTF8 whitespace numeric lexeme and escape bytes independently" {
  let wire = original_database_test_wire()
  let input = @utf8.encode(wire)
  let database = project_notion_database(input, database_test_limits()).unwrap()
  let original_hash = database.response_sha256
  assert_true(!physical_equal(database.raw, input))
  assert_eq(
    notion_database_original_json(database, @utf8.encode(wire).length()),
    Ok(wire),
  )
  assert_eq(database.response_sha256, original_hash)
  assert_eq(database.id, "db")
  assert_eq(notion_database_source_at(database, 1), Some(("s2", "same")))
  assert_eq(
    notion_database_original_json(database, @utf8.encode(wire).length() - 1),
    Err(BudgetExceeded),
  )
  assert_eq(notion_database_original_json(database, -1), Err(BudgetExceeded))
}

///|
test "Notion data source keeps its own exact snapshot and original selected database independently" {
  let database = project_notion_database(
    @utf8.encode(original_database_test_wire()),
    database_test_limits(),
  ).unwrap()
  let wire = "\r\n" + database_test_schema() + " \n"
  let input = @utf8.encode(wire)
  let source = project_notion_data_source(
    database,
    1,
    input,
    database_test_limits(),
  ).unwrap()
  let original_hash = source.response_sha256
  assert_true(!physical_equal(source.raw, input))
  assert_eq(
    notion_data_source_original_json(source, @utf8.encode(wire).length()),
    Ok(wire),
  )
  assert_eq(source.response_sha256, original_hash)
  assert_true(physical_equal(source.database, database))
  assert_eq(source.id, "s2")
  assert_eq(
    notion_data_source_original_json(source, @utf8.encode(wire).length() - 1),
    Err(BudgetExceeded),
  )
  let other = project_notion_database(
    @utf8.encode(original_database_test_wire()),
    database_test_limits(),
  ).unwrap()
  assert_eq(other.response_sha256, database.response_sha256)
  assert_true(!notion_data_source_matches_database(source, other))
}

///|
test "Notion declaration raw text retains old source identity and never canonicalizes its checked contracts" {
  for wire in [" \r\n\"db\"\n", " \r\n" + read_test_wire() + " \n"] {
    let input = @utf8.encode(wire)
    let declaration = read_notion_database_read_declaration(
      input,
      read_test_limits(),
    ).unwrap()
    let expected = "sha256:" + @sha.hex(@utf8.encode(wire))
    assert_eq(
      notion_database_read_declaration_source_cid(declaration),
      expected,
    )
    assert_eq(
      notion_database_read_declaration_original_json(
        declaration,
        @utf8.encode(wire).length(),
      ),
      Ok(wire),
    )
    assert_eq(
      notion_database_read_declaration_original_json(
        declaration,
        @utf8.encode(wire).length() - 1,
      ),
      Err(BudgetExceeded),
    )
  }
}

///|
test "Notion metadata raw snapshot still refuses byte node depth and invalid selection limits" {
  let wire = @utf8.encode(original_database_test_wire())
  for
    limits in [
      { ..database_test_limits(), max_bytes: wire.length() - 1, },
      { ..database_test_limits(), max_nodes: 1, },
      { ..database_test_limits(), max_depth: 1, },
    ] {
    assert_eq(
      project_notion_database(wire, limits).unwrap_err(),
      BudgetExceeded,
    )
  }
  assert_eq(
    project_notion_database(wire, { ..database_test_limits(), max_bytes: 0, }).unwrap_err(),
    InvalidLimits,
  )
  let database = database_test_original()
  assert_eq(
    project_notion_data_source(
      database,
      -1,
      Bytes::make(8193, 0),
      database_test_limits(),
    ).unwrap_err(),
    InvalidSelection,
  )
  assert_eq(
    project_notion_data_source(
      database,
      1,
      Bytes::make(8193, 0),
      database_test_limits(),
    ).unwrap_err(),
    BudgetExceeded,
  )
  assert_eq(
    project_notion_data_source(database, 1, b"{", database_test_limits()).unwrap_err(),
    InvalidResponse,
  )
}
