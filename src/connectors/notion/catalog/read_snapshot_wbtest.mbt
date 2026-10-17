///|
fn snapshot_test_limits() -> NotionReadSnapshotLimits {
  { max_bytes: 32768, max_nodes: 2048, max_depth: 32, }
}

///|
fn snapshot_test_empty(system? : Bool = false) -> NotionDatabaseReadSnapshot {
  let declaration = read_notion_database_read_declaration(
    @utf8.encode(" \r\n\"db\"\n"),
    read_test_limits(),
  ).unwrap()
  let database = project_notion_database(
    @utf8.encode(
      "\r\n{\"object\":\"database\",\"id\":\"db\",\"data_sources\":[{\"name\":\"é😀\",\"id\":\"s\"}],\"unknown\":9007199254740993.25}\n",
    ),
    database_test_limits(),
  ).unwrap()
  let selection = select_notion_read_source(
    declaration,
    database,
    read_test_limits().max_work,
  ).unwrap()
  let source = project_notion_selected_read_source(
    selection,
    @utf8.encode(
      " {\"object\":\"data_source\",\"id\":\"s\",\"parent\":{\"type\":\"database_id\",\"database_id\":\"db\"},\"properties\":{}} ",
    ),
    database_test_limits(),
  ).unwrap()
  let properties = bind_notion_selected_read_contracts(
    selection,
    source,
    read_test_limits(),
  ).unwrap()
  let binding = if system {
    with_notion_source_system_contracts(properties, read_test_limits()).unwrap()
  } else {
    properties
  }
  capture_notion_database_read_snapshot(
    selection,
    source,
    binding,
    snapshot_test_limits(),
  ).unwrap()
}

///|
test "Notion read snapshot independent exact raw body and schema vectors round trip both original bindings" {
  for
    (full, wire, cid) in [
      (
        false, "{\"database_response\":\"\\r\\n{\\\"object\\\":\\\"database\\\",\\\"id\\\":\\\"db\\\",\\\"data_sources\\\":[{\\\"name\\\":\\\"é😀\\\",\\\"id\\\":\\\"s\\\"}],\\\"unknown\\\":9007199254740993.25}\\n\",\"declaration_source\":\" \\r\\n\\\"db\\\"\\n\",\"schema_cid\":\"sha256:f89257995d800e6fda8e5c4ea89ec10e01702a86253b6ef701930d4be9aac7fb\",\"schema_wire\":\"{\\\"additional_properties\\\":false,\\\"fields\\\":{},\\\"nullable\\\":false,\\\"type\\\":\\\"object\\\"}\",\"selected_data_source_response\":\" {\\\"object\\\":\\\"data_source\\\",\\\"id\\\":\\\"s\\\",\\\"parent\\\":{\\\"type\\\":\\\"database_id\\\",\\\"database_id\\\":\\\"db\\\"},\\\"properties\\\":{}} \",\"system_columns\":false,\"version\":\"actql-notion-database-read-snapshot/0.1\"}",
        "sha256:f5c58fa78a83ede52bd3bbc73b43c0cd936c2ca205351bdc94e5ff39ac80447f",
      ),
      (
        true, "{\"database_response\":\"\\r\\n{\\\"object\\\":\\\"database\\\",\\\"id\\\":\\\"db\\\",\\\"data_sources\\\":[{\\\"name\\\":\\\"é😀\\\",\\\"id\\\":\\\"s\\\"}],\\\"unknown\\\":9007199254740993.25}\\n\",\"declaration_source\":\" \\r\\n\\\"db\\\"\\n\",\"schema_cid\":\"sha256:5fe543c492706b7e60053058d1749f23afb9c8dce1fb191b49b41c1b8f9adb4d\",\"schema_wire\":\"{\\\"additional_properties\\\":false,\\\"fields\\\":{\\\"created_by\\\":{\\\"min_length\\\":1,\\\"nullable\\\":false,\\\"type\\\":\\\"string\\\"},\\\"created_time\\\":{\\\"nullable\\\":false,\\\"type\\\":\\\"timestamp\\\"},\\\"id\\\":{\\\"min_length\\\":1,\\\"nullable\\\":false,\\\"type\\\":\\\"string\\\"},\\\"last_edited_by\\\":{\\\"min_length\\\":1,\\\"nullable\\\":false,\\\"type\\\":\\\"string\\\"},\\\"last_edited_time\\\":{\\\"nullable\\\":false,\\\"type\\\":\\\"timestamp\\\"},\\\"resource\\\":{\\\"min_length\\\":1,\\\"nullable\\\":false,\\\"type\\\":\\\"string\\\"},\\\"url\\\":{\\\"min_length\\\":1,\\\"nullable\\\":false,\\\"type\\\":\\\"string\\\"},\\\"version\\\":{\\\"min_length\\\":1,\\\"nullable\\\":false,\\\"type\\\":\\\"string\\\"}},\\\"nullable\\\":false,\\\"type\\\":\\\"object\\\"}\",\"selected_data_source_response\":\" {\\\"object\\\":\\\"data_source\\\",\\\"id\\\":\\\"s\\\",\\\"parent\\\":{\\\"type\\\":\\\"database_id\\\",\\\"database_id\\\":\\\"db\\\"},\\\"properties\\\":{}} \",\"system_columns\":true,\"version\":\"actql-notion-database-read-snapshot/0.1\"}",
        "sha256:f5f12bd1345926d73059f6fb15b518a6d6f85d239051f2a5c489bef85d6eac83",
      ),
    ] {
    let snapshot = snapshot_test_empty(system=full)
    assert_eq(notion_database_read_snapshot_wire(snapshot), Ok(wire))
    assert_eq(notion_database_read_snapshot_source_cid(snapshot), Ok(cid))
    let restored = read_notion_database_read_snapshot(
      @utf8.encode(wire),
      cid,
      read_test_limits(),
      snapshot_test_limits(),
    ).unwrap()
    assert_eq(notion_database_read_snapshot_wire(restored), Ok(wire))
    assert_eq(notion_database_read_snapshot_source_cid(restored), Ok(cid))
    assert_true(
      !physical_equal(
        restored.selection.declaration,
        snapshot.selection.declaration,
      ),
    )
    assert_true(!physical_equal(restored.source, snapshot.source))
    assert_true(
      notion_database_read_snapshot_matches(
        restored,
        restored.selection,
        restored.source,
        restored.read_contracts,
      ),
    )
    assert_true(
      !notion_database_read_snapshot_matches(
        restored,
        snapshot.selection,
        snapshot.source,
        snapshot.read_contracts,
      ),
    )
    assert_eq(
      restored.read_contracts.system_columns.length(),
      if full {
        8
      } else {
        0
      },
    )
    assert_eq(
      notion_database_original_json(restored.selection.database, 8192),
      Ok(
        "\r\n{\"object\":\"database\",\"id\":\"db\",\"data_sources\":[{\"name\":\"é😀\",\"id\":\"s\"}],\"unknown\":9007199254740993.25}\n",
      ),
    )
    assert_eq(
      notion_data_source_original_json(restored.source, 8192),
      Ok(
        " {\"object\":\"data_source\",\"id\":\"s\",\"parent\":{\"type\":\"database_id\",\"database_id\":\"db\"},\"properties\":{}} ",
      ),
    )
    assert_eq(
      notion_database_read_declaration_original_json(
        restored.selection.declaration,
        8192,
      ),
      Ok(" \r\n\"db\"\n"),
    )
  }
}

///|
test "Notion read snapshot capture refuses copied equal foreign selection source and checked contracts" {
  let snapshot = snapshot_test_empty()
  let other = snapshot_test_empty()
  assert_eq(
    capture_notion_database_read_snapshot(
      other.selection,
      snapshot.source,
      snapshot.read_contracts,
      snapshot_test_limits(),
    ).unwrap_err(),
    ForeignOriginal,
  )
  assert_eq(
    capture_notion_database_read_snapshot(
      snapshot.selection,
      other.source,
      snapshot.read_contracts,
      snapshot_test_limits(),
    ).unwrap_err(),
    ForeignOriginal,
  )
  assert_eq(
    capture_notion_database_read_snapshot(
      snapshot.selection,
      snapshot.source,
      other.read_contracts,
      snapshot_test_limits(),
    ).unwrap_err(),
    ForeignOriginal,
  )
  let copy = { ..snapshot, }
  assert_eq(notion_database_read_snapshot_wire(copy), Err(ForeignOriginal))
  assert_eq(
    notion_database_read_snapshot_source_cid(copy),
    Err(ForeignOriginal),
  )
  assert_true(
    !notion_database_read_snapshot_matches(
      copy,
      snapshot.selection,
      snapshot.source,
      snapshot.read_contracts,
    ),
  )
  assert_eq(
    notion_database_read_snapshot_declaration(copy).unwrap_err(),
    ForeignOriginal,
  )
  assert_eq(
    notion_database_read_snapshot_source(copy).unwrap_err(),
    ForeignOriginal,
  )
  assert_eq(
    notion_database_read_snapshot_contracts(copy).unwrap_err(),
    ForeignOriginal,
  )
}

///|
test "Notion read snapshot exact output and reader bounds fail without partial originals" {
  let snapshot = snapshot_test_empty()
  let wire = snapshot.wire
  let bytes = @utf8.encode(wire).length()
  let exact = { ..snapshot_test_limits(), max_bytes: bytes, }
  assert_eq(
    notion_database_read_snapshot_wire(
      capture_notion_database_read_snapshot(
        snapshot.selection,
        snapshot.source,
        snapshot.read_contracts,
        exact,
      ).unwrap(),
    ),
    Ok(wire),
  )
  assert_eq(
    capture_notion_database_read_snapshot(
      snapshot.selection,
      snapshot.source,
      snapshot.read_contracts,
      { ..exact, max_bytes: bytes - 1, },
    ).unwrap_err(),
    BudgetExceeded,
  )
  assert_eq(
    read_notion_database_read_snapshot(
      @utf8.encode(wire),
      snapshot.source_cid,
      read_test_limits(),
      { ..exact, max_bytes: bytes - 1, },
    ).unwrap_err(),
    BudgetExceeded,
  )
  assert_eq(
    read_notion_database_read_snapshot(
      @utf8.encode(wire),
      snapshot.source_cid,
      read_test_limits(),
      { ..exact, max_nodes: 1, },
    ).unwrap_err(),
    Metadata(BudgetExceeded),
  )
  assert_eq(
    read_notion_database_read_snapshot(
      @utf8.encode(wire),
      snapshot.source_cid,
      read_test_limits(),
      { ..exact, max_depth: 0, },
    ).unwrap_err(),
    InvalidLimits,
  )
  assert_eq(
    read_notion_database_read_snapshot(
      @utf8.encode(wire),
      snapshot.source_cid,
      { ..read_test_limits(), max_work: 1, },
      exact,
    ).unwrap_err(),
    Declaration(BudgetExceeded),
  )
  assert_eq(notion_database_read_snapshot_wire(snapshot), Ok(wire))
}

///|
test "Notion read snapshot source identity refuses alternate exact bytes before re-admission" {
  let snapshot = snapshot_test_empty()
  assert_eq(
    read_notion_database_read_snapshot(
      @utf8.encode(" " + snapshot.wire),
      snapshot.source_cid,
      read_test_limits(),
      snapshot_test_limits(),
    ).unwrap_err(),
    IdentityMismatch,
  )
  assert_eq(
    read_notion_database_read_snapshot(
      @utf8.encode(snapshot.wire),
      "sha256:" + "0".repeat(64),
      read_test_limits(),
      snapshot_test_limits(),
    ).unwrap_err(),
    IdentityMismatch,
  )
  let alternate = " " + snapshot.wire
  assert_eq(
    read_notion_database_read_snapshot(
      @utf8.encode(alternate),
      "sha256:" + @sha.hex(@utf8.encode(alternate)),
      read_test_limits(),
      snapshot_test_limits(),
    ).unwrap_err(),
    InvalidSnapshot,
  )
}

///|
test "Notion read snapshot closed body and recomputed schema refuse malformed or substituted facts" {
  for
    (wire, cid) in [
      (
        "{\"database_response\":\"\\r\\n{\\\"object\\\":\\\"database\\\",\\\"id\\\":\\\"db\\\",\\\"data_sources\\\":[{\\\"name\\\":\\\"é😀\\\",\\\"id\\\":\\\"s\\\"}],\\\"unknown\\\":9007199254740993.25}\\n\",\"declaration_source\":\" \\r\\n\\\"db\\\"\\n\",\"schema_cid\":\"sha256:f89257995d800e6fda8e5c4ea89ec10e01702a86253b6ef701930d4be9aac7fb\",\"schema_wire\":\"{\\\"additional_properties\\\":false,\\\"fields\\\":{},\\\"nullable\\\":false,\\\"type\\\":\\\"object\\\"}\",\"selected_data_source_response\":\" {\\\"object\\\":\\\"data_source\\\",\\\"id\\\":\\\"s\\\",\\\"parent\\\":{\\\"type\\\":\\\"database_id\\\",\\\"database_id\\\":\\\"db\\\"},\\\"properties\\\":{}} \",\"system_columns\":false,\"unknown\":false,\"version\":\"actql-notion-database-read-snapshot/0.1\"}",
        "sha256:271b1560616b34b414f70ab67b4b5d6d702e6ef68e2812b4b2e2a2c66fa5d3a7",
      ),
      (
        "{\"database_response\":\"\\r\\n{\\\"object\\\":\\\"database\\\",\\\"id\\\":\\\"db\\\",\\\"data_sources\\\":[{\\\"name\\\":\\\"é😀\\\",\\\"id\\\":\\\"s\\\"}],\\\"unknown\\\":9007199254740993.25}\\n\",\"declaration_source\":\" \\r\\n\\\"db\\\"\\n\",\"schema_cid\":\"sha256:f89257995d800e6fda8e5c4ea89ec10e01702a86253b6ef701930d4be9aac7fb\",\"schema_wire\":\"{\\\"additional_properties\\\":false,\\\"fields\\\":{},\\\"nullable\\\":false,\\\"type\\\":\\\"object\\\"}\",\"selected_data_source_response\":\" {\\\"object\\\":\\\"data_source\\\",\\\"id\\\":\\\"s\\\",\\\"parent\\\":{\\\"type\\\":\\\"database_id\\\",\\\"database_id\\\":\\\"db\\\"},\\\"properties\\\":{}} \",\"system_columns\":false,\"version\":\"other\"}",
        "sha256:86ac7a2a8e13826fed016338cddf1ff261f67b05d8c258e8c7f120203be1117c",
      ),
      (
        "{\"database_response\":\"\\r\\n{\\\"object\\\":\\\"database\\\",\\\"id\\\":\\\"db\\\",\\\"data_sources\\\":[{\\\"name\\\":\\\"é😀\\\",\\\"id\\\":\\\"s\\\"}],\\\"unknown\\\":9007199254740993.25}\\n\",\"declaration_source\":\" \\r\\n\\\"db\\\"\\n\",\"schema_cid\":\"sha256:f89257995d800e6fda8e5c4ea89ec10e01702a86253b6ef701930d4be9aac7fb\",\"schema_wire\":\"{\\\"additional_properties\\\":false,\\\"fields\\\":{},\\\"nullable\\\":false,\\\"type\\\":\\\"object\\\"}\",\"selected_data_source_response\":\" {\\\"object\\\":\\\"data_source\\\",\\\"id\\\":\\\"s\\\",\\\"parent\\\":{\\\"type\\\":\\\"database_id\\\",\\\"database_id\\\":\\\"db\\\"},\\\"properties\\\":{}} \",\"system_columns\":null,\"version\":\"actql-notion-database-read-snapshot/0.1\"}",
        "sha256:1195c565a409a5a5a4124819835f2443234f85ec3972369f6974e69d81f7c9e7",
      ),
      (
        "{\"database_response\":\"\\r\\n{\\\"object\\\":\\\"database\\\",\\\"id\\\":\\\"db\\\",\\\"data_sources\\\":[{\\\"name\\\":\\\"é😀\\\",\\\"id\\\":\\\"s\\\"}],\\\"unknown\\\":9007199254740993.25}\\n\",\"declaration_source\":\" \\r\\n\\\"db\\\"\\n\",\"schema_cid\":\"sha256:f89257995d800e6fda8e5c4ea89ec10e01702a86253b6ef701930d4be9aac7fb\",\"schema_wire\":\"{\\\"additional_properties\\\":false,\\\"fields\\\":{},\\\"nullable\\\":true,\\\"type\\\":\\\"object\\\"}\",\"selected_data_source_response\":\" {\\\"object\\\":\\\"data_source\\\",\\\"id\\\":\\\"s\\\",\\\"parent\\\":{\\\"type\\\":\\\"database_id\\\",\\\"database_id\\\":\\\"db\\\"},\\\"properties\\\":{}} \",\"system_columns\":false,\"version\":\"actql-notion-database-read-snapshot/0.1\"}",
        "sha256:c360adf599d908239b772a33eab59945f0bf2cd601b1116a012abd37c5e4befa",
      ),
      (
        "{\"database_response\":\"\\r\\n{\\\"object\\\":\\\"database\\\",\\\"id\\\":\\\"db\\\",\\\"data_sources\\\":[{\\\"name\\\":\\\"é😀\\\",\\\"id\\\":\\\"s\\\"}],\\\"unknown\\\":9007199254740993.25}\\n\",\"declaration_source\":\" \\r\\n\\\"db\\\"\\n\",\"schema_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"schema_wire\":\"{\\\"additional_properties\\\":false,\\\"fields\\\":{},\\\"nullable\\\":false,\\\"type\\\":\\\"object\\\"}\",\"selected_data_source_response\":\" {\\\"object\\\":\\\"data_source\\\",\\\"id\\\":\\\"s\\\",\\\"parent\\\":{\\\"type\\\":\\\"database_id\\\",\\\"database_id\\\":\\\"db\\\"},\\\"properties\\\":{}} \",\"system_columns\":false,\"version\":\"actql-notion-database-read-snapshot/0.1\"}",
        "sha256:5f43976bb5e929587a6e148d3d83d3cd34bd6258c95c97f77b62fac749434be6",
      ),
      (
        "{\"database_response\":\"\\r\\n{\\\"object\\\":\\\"database\\\",\\\"id\\\":\\\"db\\\",\\\"data_sources\\\":[{\\\"name\\\":\\\"é😀\\\",\\\"id\\\":\\\"s\\\"}],\\\"unknown\\\":9007199254740993.25}\\n\",\"declaration_source\":\" \\r\\n\\\"db\\\"\\n\",\"schema_cid\":\"sha256:f89257995d800e6fda8e5c4ea89ec10e01702a86253b6ef701930d4be9aac7fb\",\"selected_data_source_response\":\" {\\\"object\\\":\\\"data_source\\\",\\\"id\\\":\\\"s\\\",\\\"parent\\\":{\\\"type\\\":\\\"database_id\\\",\\\"database_id\\\":\\\"db\\\"},\\\"properties\\\":{}} \",\"system_columns\":false,\"version\":\"actql-notion-database-read-snapshot/0.1\"}",
        "sha256:6a6d5e426729444accedf0ffc68f305c66e0ad817b4c2ae67d7ebf819101d74a",
      ),
    ] {
    assert_true(
      read_notion_database_read_snapshot(
        @utf8.encode(wire),
        cid,
        read_test_limits(),
        snapshot_test_limits(),
      )
      is Err(_),
    )
  }
}
