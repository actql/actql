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
        false, "{\"database_response\":\"\\r\\n{\\\"object\\\":\\\"database\\\",\\\"id\\\":\\\"db\\\",\\\"data_sources\\\":[{\\\"name\\\":\\\"é😀\\\",\\\"id\\\":\\\"s\\\"}],\\\"unknown\\\":9007199254740993.25}\\n\",\"declaration_source\":\" \\r\\n\\\"db\\\"\\n\",\"schema_cid\":\"sha256:51761e43cc6461058c7a4e4ed9a957bb1a076a3cd34564c2d882190e2814b932\",\"schema_wire\":\"{\\\"fields\\\":{},\\\"nullable\\\":false,\\\"type\\\":\\\"object\\\"}\",\"selected_data_source_response\":\" {\\\"object\\\":\\\"data_source\\\",\\\"id\\\":\\\"s\\\",\\\"parent\\\":{\\\"type\\\":\\\"database_id\\\",\\\"database_id\\\":\\\"db\\\"},\\\"properties\\\":{}} \",\"system_columns\":false,\"version\":\"actql-notion-database-read-snapshot/0.1\"}",
        "sha256:4ee2aef8f7cd4a0fdf0636c9196688b676d0fa70b488131aded24a69b5472f1f",
      ),
      (
        true, "{\"database_response\":\"\\r\\n{\\\"object\\\":\\\"database\\\",\\\"id\\\":\\\"db\\\",\\\"data_sources\\\":[{\\\"name\\\":\\\"é😀\\\",\\\"id\\\":\\\"s\\\"}],\\\"unknown\\\":9007199254740993.25}\\n\",\"declaration_source\":\" \\r\\n\\\"db\\\"\\n\",\"schema_cid\":\"sha256:3ffa826063458960878e34d07471b2866cc209df3e813cdff97f8de9c28279ef\",\"schema_wire\":\"{\\\"fields\\\":{\\\"created_by\\\":{\\\"min_length\\\":1,\\\"nullable\\\":false,\\\"type\\\":\\\"string\\\"},\\\"created_time\\\":{\\\"nullable\\\":false,\\\"type\\\":\\\"timestamp\\\"},\\\"id\\\":{\\\"min_length\\\":1,\\\"nullable\\\":false,\\\"type\\\":\\\"string\\\"},\\\"last_edited_by\\\":{\\\"min_length\\\":1,\\\"nullable\\\":false,\\\"type\\\":\\\"string\\\"},\\\"last_edited_time\\\":{\\\"nullable\\\":false,\\\"type\\\":\\\"timestamp\\\"},\\\"resource\\\":{\\\"min_length\\\":1,\\\"nullable\\\":false,\\\"type\\\":\\\"string\\\"},\\\"url\\\":{\\\"min_length\\\":1,\\\"nullable\\\":false,\\\"type\\\":\\\"string\\\"},\\\"version\\\":{\\\"min_length\\\":1,\\\"nullable\\\":false,\\\"type\\\":\\\"string\\\"}},\\\"nullable\\\":false,\\\"type\\\":\\\"object\\\"}\",\"selected_data_source_response\":\" {\\\"object\\\":\\\"data_source\\\",\\\"id\\\":\\\"s\\\",\\\"parent\\\":{\\\"type\\\":\\\"database_id\\\",\\\"database_id\\\":\\\"db\\\"},\\\"properties\\\":{}} \",\"system_columns\":true,\"version\":\"actql-notion-database-read-snapshot/0.1\"}",
        "sha256:0a37eaacdcada4d73a15c04d848cc9820df0c40db122b31e6465a9902ad2d729",
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
        "{\"database_response\":\"\\r\\n{\\\"object\\\":\\\"database\\\",\\\"id\\\":\\\"db\\\",\\\"data_sources\\\":[{\\\"name\\\":\\\"é😀\\\",\\\"id\\\":\\\"s\\\"}],\\\"unknown\\\":9007199254740993.25}\\n\",\"declaration_source\":\" \\r\\n\\\"db\\\"\\n\",\"schema_cid\":\"sha256:51761e43cc6461058c7a4e4ed9a957bb1a076a3cd34564c2d882190e2814b932\",\"schema_wire\":\"{\\\"fields\\\":{},\\\"nullable\\\":false,\\\"type\\\":\\\"object\\\"}\",\"selected_data_source_response\":\" {\\\"object\\\":\\\"data_source\\\",\\\"id\\\":\\\"s\\\",\\\"parent\\\":{\\\"type\\\":\\\"database_id\\\",\\\"database_id\\\":\\\"db\\\"},\\\"properties\\\":{}} \",\"system_columns\":false,\"unknown\":false,\"version\":\"actql-notion-database-read-snapshot/0.1\"}",
        "sha256:9c7f0f59ac2c03138a0a49d6701090072fe9feda0f09b13e260f188217269d6c",
      ),
      (
        "{\"database_response\":\"\\r\\n{\\\"object\\\":\\\"database\\\",\\\"id\\\":\\\"db\\\",\\\"data_sources\\\":[{\\\"name\\\":\\\"é😀\\\",\\\"id\\\":\\\"s\\\"}],\\\"unknown\\\":9007199254740993.25}\\n\",\"declaration_source\":\" \\r\\n\\\"db\\\"\\n\",\"schema_cid\":\"sha256:51761e43cc6461058c7a4e4ed9a957bb1a076a3cd34564c2d882190e2814b932\",\"schema_wire\":\"{\\\"fields\\\":{},\\\"nullable\\\":false,\\\"type\\\":\\\"object\\\"}\",\"selected_data_source_response\":\" {\\\"object\\\":\\\"data_source\\\",\\\"id\\\":\\\"s\\\",\\\"parent\\\":{\\\"type\\\":\\\"database_id\\\",\\\"database_id\\\":\\\"db\\\"},\\\"properties\\\":{}} \",\"system_columns\":false,\"version\":\"other\"}",
        "sha256:4e9ec43b860d4507b1a2814497ff2da183b1cfb98577f3c47241afb68b677a86",
      ),
      (
        "{\"database_response\":\"\\r\\n{\\\"object\\\":\\\"database\\\",\\\"id\\\":\\\"db\\\",\\\"data_sources\\\":[{\\\"name\\\":\\\"é😀\\\",\\\"id\\\":\\\"s\\\"}],\\\"unknown\\\":9007199254740993.25}\\n\",\"declaration_source\":\" \\r\\n\\\"db\\\"\\n\",\"schema_cid\":\"sha256:51761e43cc6461058c7a4e4ed9a957bb1a076a3cd34564c2d882190e2814b932\",\"schema_wire\":\"{\\\"fields\\\":{},\\\"nullable\\\":false,\\\"type\\\":\\\"object\\\"}\",\"selected_data_source_response\":\" {\\\"object\\\":\\\"data_source\\\",\\\"id\\\":\\\"s\\\",\\\"parent\\\":{\\\"type\\\":\\\"database_id\\\",\\\"database_id\\\":\\\"db\\\"},\\\"properties\\\":{}} \",\"system_columns\":null,\"version\":\"actql-notion-database-read-snapshot/0.1\"}",
        "sha256:6e71e9bff2177325dff2d95d56c2e8ee1a6017439a9e84d8f0049d77afbb3398",
      ),
      (
        "{\"database_response\":\"\\r\\n{\\\"object\\\":\\\"database\\\",\\\"id\\\":\\\"db\\\",\\\"data_sources\\\":[{\\\"name\\\":\\\"é😀\\\",\\\"id\\\":\\\"s\\\"}],\\\"unknown\\\":9007199254740993.25}\\n\",\"declaration_source\":\" \\r\\n\\\"db\\\"\\n\",\"schema_cid\":\"sha256:51761e43cc6461058c7a4e4ed9a957bb1a076a3cd34564c2d882190e2814b932\",\"schema_wire\":\"{\\\"fields\\\":{},\\\"nullable\\\":true,\\\"type\\\":\\\"object\\\"}\",\"selected_data_source_response\":\" {\\\"object\\\":\\\"data_source\\\",\\\"id\\\":\\\"s\\\",\\\"parent\\\":{\\\"type\\\":\\\"database_id\\\",\\\"database_id\\\":\\\"db\\\"},\\\"properties\\\":{}} \",\"system_columns\":false,\"version\":\"actql-notion-database-read-snapshot/0.1\"}",
        "sha256:24baa8ba1b6e60455cdbdfe7696c64dd16f777029b452c1b5314027474de4941",
      ),
      (
        "{\"database_response\":\"\\r\\n{\\\"object\\\":\\\"database\\\",\\\"id\\\":\\\"db\\\",\\\"data_sources\\\":[{\\\"name\\\":\\\"é😀\\\",\\\"id\\\":\\\"s\\\"}],\\\"unknown\\\":9007199254740993.25}\\n\",\"declaration_source\":\" \\r\\n\\\"db\\\"\\n\",\"schema_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"schema_wire\":\"{\\\"fields\\\":{},\\\"nullable\\\":false,\\\"type\\\":\\\"object\\\"}\",\"selected_data_source_response\":\" {\\\"object\\\":\\\"data_source\\\",\\\"id\\\":\\\"s\\\",\\\"parent\\\":{\\\"type\\\":\\\"database_id\\\",\\\"database_id\\\":\\\"db\\\"},\\\"properties\\\":{}} \",\"system_columns\":false,\"version\":\"actql-notion-database-read-snapshot/0.1\"}",
        "sha256:0c0db001eb2c58d1bef5921c39d83e7201ee46855be95a103e2d22e834798b64",
      ),
      (
        "{\"database_response\":\"\\r\\n{\\\"object\\\":\\\"database\\\",\\\"id\\\":\\\"db\\\",\\\"data_sources\\\":[{\\\"name\\\":\\\"é😀\\\",\\\"id\\\":\\\"s\\\"}],\\\"unknown\\\":9007199254740993.25}\\n\",\"declaration_source\":\" \\r\\n\\\"db\\\"\\n\",\"schema_cid\":\"sha256:51761e43cc6461058c7a4e4ed9a957bb1a076a3cd34564c2d882190e2814b932\",\"selected_data_source_response\":\" {\\\"object\\\":\\\"data_source\\\",\\\"id\\\":\\\"s\\\",\\\"parent\\\":{\\\"type\\\":\\\"database_id\\\",\\\"database_id\\\":\\\"db\\\"},\\\"properties\\\":{}} \",\"system_columns\":false,\"version\":\"actql-notion-database-read-snapshot/0.1\"}",
        "sha256:78022e7a723ab27f7ecc60d5f082c07e4a39c98d39a44acbc7b2715000276b34",
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
