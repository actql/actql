///|
test "Local Project selects the original CSV single and multiple table declarations" {
  let one = "{\"version\":\"actql-connectors/0.1\",\"connections\":{\"local\":{\"connector\":\"local\",\"root\":\"./data\",\"tables\":{\"small\":{\"path\":\"small.csv\",\"key\":[\"id\"],\"columns\":{\"id\":\"int64\",\"name\":\"string\"}}}}}}"
  let original = admit_client_project_connections(one).unwrap()
  let selection = original.local_files(0, 100, 2).unwrap()
  assert_eq(original.original_wire(), one)
  assert_eq(selection.root, "./data")
  assert_false(selection.content_version)
  assert_eq(selection.csv_tables.length(), 1)
  let table = selection.csv_tables[0]
  assert_eq(table.path, "small.csv")
  assert_eq(table.column_names, ["id", "name"])
  assert_eq(table.integer_columns, [true, false])
  assert_eq(table.keys, ["id"])
  assert_eq(
    table.view.schema_cid,
    "sha256:cb2f3b3b1ae90e17599f0ae3f8991a68796d8a94527353dbf832eb8eb4ebfe0c",
  )
  assert_eq(
    table.view.facts_wire,
    Some("{\"relation_keys\":{\"candidate_keys\":[[\"id\"]]}}"),
  )
  assert_true(
    original.local_files(1, 100, 2) is Err(InvalidLocalFilesConnection),
  )

  let two = "{\"version\":\"actql-connectors/0.1\",\"connections\":{\"local\":{\"connector\":\"local\",\"root\":\"./data\",\"tables\":{\"small\":{\"path\":\"small.csv\",\"key\":[\"id\"],\"columns\":{\"id\":\"int64\",\"name\":\"string\"}},\"other\":{\"path\":\"other.csv\",\"key\":[\"id\"],\"columns\":{\"id\":\"int64\",\"name\":\"string\"}}}}}}"
  let selection = admit_client_project_connections(two)
    .unwrap()
    .local_files(0, 100, 2)
    .unwrap()
  assert_eq(selection.csv_tables.map(table => table.view.resource), [
    "small", "other",
  ])
}

///|
test "Local Project refuses a selected invalid second CSV declaration" {
  let wire = "{\"version\":\"actql-connectors/0.1\",\"connections\":{\"local\":{\"connector\":\"local\",\"root\":\"./data\",\"tables\":{\"small\":{\"path\":\"small.csv\",\"key\":[\"id\"],\"columns\":{\"id\":\"int64\",\"name\":\"string\"}},\"other\":{\"path\":\"other.csv\",\"key\":[\"id\"],\"columns\":{\"id\":\"int64\",\"name\":\"invalid\"}}}}}}"
  let original = admit_client_project_connections(wire).unwrap()
  assert_true(
    original.local_files(0, 100, 2) is Err(CsvTable(InvalidLocalCsvColumns)),
  )
}
