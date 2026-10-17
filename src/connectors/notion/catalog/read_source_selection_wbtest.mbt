///|
test "Notion declaration source identity retains exact raw bytes and never changes its semantic domain" {
  let source = b"\"db\"".copy()
  let declaration = read_notion_database_read_declaration(
    source,
    read_test_limits(),
  ).unwrap()
  assert_eq(
    notion_database_read_declaration_source_cid(declaration),
    "sha256:41a21b0d157a935f20927c113a08a883fe32359b747efa20b52a4622d6c41519",
  )
  assert_eq(notion_database_read_declaration_source_bytes(declaration), 4)
  source[1] = b'x'
  assert_eq(declaration.database_id, "db")
  assert_eq(
    notion_database_read_declaration_source_cid(declaration),
    "sha256:41a21b0d157a935f20927c113a08a883fe32359b747efa20b52a4622d6c41519",
  )
  let exact = read_notion_database_read_declaration(
    b" \r\n{\"id\":\"db\",\"data_source_id\":\"s2\"} \n",
    read_test_limits(),
  ).unwrap()
  assert_eq(
    notion_database_read_declaration_source_cid(exact),
    "sha256:c4cfa3984b5b746042656a3ae8986fb28db91ed922bf50234d042e5cb3afed57",
  )
  assert_eq(notion_database_read_declaration_source_bytes(exact), 38)
  let unicode = read_notion_database_read_declaration(
    @utf8.encode("{\"id\":\"é\",\"data_source_id\":\"s😀\"}"),
    read_test_limits(),
  ).unwrap()
  assert_eq(
    notion_database_read_declaration_source_cid(unicode),
    "sha256:6c627b920500c375f769f37af60226d7018a503718af6f51a55f626473acb146",
  )
  assert_eq(unicode.database_id, "é")
  assert_eq(
    read_notion_database_read_declaration(b"\"db\"", {
      ..read_test_limits(),
      metadata: { ..database_test_limits(), max_bytes: 3, },
    }).unwrap_err(),
    Metadata(BudgetExceeded),
  )
}

///|
test "Notion read source selection retains declaration and actual database occurrence nominally" {
  let database = database_test_original()
  let declaration = read_test_declaration()
  let selected = select_notion_read_source(declaration, database, 100).unwrap()
  assert_eq(notion_read_source_selection_id(selected), "s2")
  assert_true(
    notion_read_source_selection_matches(selected, declaration, database),
  )
  assert_true(
    !notion_read_source_selection_matches(
      selected,
      read_test_declaration(),
      database,
    ),
  )
  assert_true(
    !notion_read_source_selection_matches(
      selected,
      declaration,
      database_test_original(),
    ),
  )
  assert_eq(
    select_notion_read_source(declaration, database, 0).unwrap_err(),
    InvalidLimits,
  )
  assert_eq(
    select_notion_read_source(declaration, database, 1).unwrap_err(),
    BudgetExceeded,
  )
  // database ids2+2, sources each1+id2+selected2: exact total14.
  assert_true(select_notion_read_source(declaration, database, 14) is Ok(_))
  assert_eq(
    select_notion_read_source(declaration, database, 13).unwrap_err(),
    BudgetExceeded,
  )
}

///|
test "Notion selection admits scalar singleton only and never infers first or display names" {
  let declaration = read_notion_database_read_declaration(
    b"\"db\"",
    read_test_limits(),
  ).unwrap()
  for
    body in [
      b"{\"object\":\"database\",\"id\":\"db\",\"data_sources\":[]}", b"{\"object\":\"database\",\"id\":\"db\",\"data_sources\":[{\"id\":\"s1\",\"name\":\"s2\"},{\"id\":\"s2\",\"name\":\"s1\"}]}",
    ] {
    let db = project_notion_database(body, database_test_limits()).unwrap()
    assert_eq(
      select_notion_read_source(declaration, db, 100).unwrap_err(),
      InvalidSelection,
    )
  }
  let db = project_notion_database(
    b"{\"object\":\"database\",\"id\":\"db\",\"data_sources\":[{\"id\":\"s2\",\"name\":\"other\"}]}",
    database_test_limits(),
  ).unwrap()
  assert_eq(
    notion_read_source_selection_id(
      select_notion_read_source(declaration, db, 100).unwrap(),
    ),
    "s2",
  )
  let wrong = read_notion_database_read_declaration(
    b"{\"id\":\"db\",\"data_source_id\":\"missing\"}",
    read_test_limits(),
  ).unwrap()
  assert_eq(
    select_notion_read_source(wrong, db, 100).unwrap_err(),
    InvalidSelection,
  )
}

///|
test "Notion schema projection and contract binding consume only the same selected original" {
  let declaration = read_test_declaration()
  let database = database_test_original()
  let selected = select_notion_read_source(declaration, database, 100).unwrap()
  let source = project_notion_selected_read_source(
    selected,
    @utf8.encode(
      "{\"object\":\"data_source\",\"id\":\"s2\",\"parent\":{\"type\":\"database_id\",\"database_id\":\"db\"},\"properties\":{\"é\":{\"id\":\"t%3Ax\",\"name\":\"é\",\"type\":\"title\",\"title\":{}},\"amount\":{\"id\":\"n\",\"name\":\"amount\",\"type\":\"number\",\"number\":{\"format\":\"number\"}}}}",
    ),
    database_test_limits(),
  ).unwrap()
  assert_true(notion_data_source_matches_database(source, database))
  let contracts = bind_notion_selected_read_contracts(
    selected,
    source,
    read_test_limits(),
  ).unwrap()
  assert_true(notion_data_source_read_matches(contracts, declaration, source))
  assert_eq(
    bind_notion_selected_read_contracts(
      selected,
      query_test_source(),
      read_test_limits(),
    ).unwrap_err(),
    ForeignOriginal,
  )
  assert_true(
    project_notion_selected_read_source(selected, b"{}", database_test_limits())
    is Err(_),
  )
}
