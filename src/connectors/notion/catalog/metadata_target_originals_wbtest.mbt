///|
test "Notion metadata schema target requires the original selection itself not copied retained fields" {
  let declaration = read_test_declaration()
  let database = database_test_original()
  let original = select_notion_read_source(declaration, database, 100).unwrap()
  let source = project_notion_selected_read_source(
    original,
    query_test_source().raw,
    database_test_limits(),
  ).unwrap()
  let contracts = bind_notion_selected_read_contracts(
    original,
    source,
    read_test_limits(),
  ).unwrap()
  let copy = { ..original, }
  assert_true(
    !notion_read_source_selection_matches(copy, declaration, database),
  )
  assert_eq(
    project_notion_selected_read_source(copy, b"{}", database_test_limits()).unwrap_err(),
    ForeignOriginal,
  )
  assert_eq(
    bind_notion_selected_read_contracts(copy, source, read_test_limits()).unwrap_err(),
    ForeignOriginal,
  )
  assert_eq(
    capture_notion_database_read_snapshot(
      copy,
      source,
      contracts,
      snapshot_test_limits(),
    ).unwrap_err(),
    NotionReadSnapshotIssue::ForeignOriginal,
  )
  assert_true(
    notion_read_source_selection_matches(original, declaration, database),
  )
  assert_true(
    capture_notion_database_read_snapshot(
      original,
      source,
      contracts,
      snapshot_test_limits(),
    )
    is Ok(_),
  )
}
