///|
// Independent view-map/body vector, not produced by the Catalog emitter.
fn snapshot_relations_expected() -> String {
  "{\"views\":[{\"resource\":\"tasks-é😀\",\"resource_kind\":\"notion_database\",\"schema_cid\":\"sha256:c01321a1027337256aa62b8e9a4d973ae1bed0a157519350a730a3f0e79c0a58\",\"schema_wire\":\"{\\\"created_by\\\":{\\\"min_length\\\":1,\\\"nullable\\\":false,\\\"type\\\":\\\"string\\\"},\\\"created_time\\\":{\\\"nullable\\\":false,\\\"type\\\":\\\"timestamp\\\"},\\\"id\\\":{\\\"min_length\\\":1,\\\"nullable\\\":false,\\\"type\\\":\\\"string\\\"},\\\"last_edited_by\\\":{\\\"min_length\\\":1,\\\"nullable\\\":false,\\\"type\\\":\\\"string\\\"},\\\"last_edited_time\\\":{\\\"nullable\\\":false,\\\"type\\\":\\\"timestamp\\\"},\\\"resource\\\":{\\\"min_length\\\":1,\\\"nullable\\\":false,\\\"type\\\":\\\"string\\\"},\\\"url\\\":{\\\"min_length\\\":1,\\\"nullable\\\":false,\\\"type\\\":\\\"string\\\"},\\\"version\\\":{\\\"min_length\\\":1,\\\"nullable\\\":false,\\\"type\\\":\\\"string\\\"}}\"},{\"resource\":\"accounts\",\"resource_kind\":\"notion_database\",\"schema_cid\":\"sha256:c01321a1027337256aa62b8e9a4d973ae1bed0a157519350a730a3f0e79c0a58\",\"schema_wire\":\"{\\\"created_by\\\":{\\\"min_length\\\":1,\\\"nullable\\\":false,\\\"type\\\":\\\"string\\\"},\\\"created_time\\\":{\\\"nullable\\\":false,\\\"type\\\":\\\"timestamp\\\"},\\\"id\\\":{\\\"min_length\\\":1,\\\"nullable\\\":false,\\\"type\\\":\\\"string\\\"},\\\"last_edited_by\\\":{\\\"min_length\\\":1,\\\"nullable\\\":false,\\\"type\\\":\\\"string\\\"},\\\"last_edited_time\\\":{\\\"nullable\\\":false,\\\"type\\\":\\\"timestamp\\\"},\\\"resource\\\":{\\\"min_length\\\":1,\\\"nullable\\\":false,\\\"type\\\":\\\"string\\\"},\\\"url\\\":{\\\"min_length\\\":1,\\\"nullable\\\":false,\\\"type\\\":\\\"string\\\"},\\\"version\\\":{\\\"min_length\\\":1,\\\"nullable\\\":false,\\\"type\\\":\\\"string\\\"}}\"}]}"
}

///|
test "Notion multiple snapshot relations preserve independent aliases and legacy single bytes" {
  let first = snapshot_test_empty(system=true)
  let second = snapshot_test_empty(system=true)
  let wire = notion_database_read_snapshots_relation_specification(
    [("tasks-é😀", first), ("accounts", second)],
    snapshot_test_limits(),
    2,
    1000,
  ).unwrap()
  assert_eq(wire, snapshot_relations_expected())
  assert_eq(
    notion_database_read_snapshots_relation_specification(
      [("tasks-é😀", first)],
      snapshot_test_limits(),
      1,
      1000,
    ),
    notion_database_read_snapshot_relation_specification(
      first,
      "tasks-é😀",
      snapshot_test_limits(),
    ),
  )
  assert_true(!physical_equal(first, second))
  assert_eq(
    notion_database_read_snapshot_wire(first),
    notion_database_read_snapshot_wire(second),
  )
}

///|
test "Notion snapshot relation inventory keeps empty exact unicode and duplicate alias semantics" {
  assert_eq(
    notion_database_read_snapshots_relation_specification(
      [],
      snapshot_test_limits(),
      0,
      0,
    ),
    Ok("{\"views\":[]}"),
  )
  let snapshot = snapshot_test_empty(system=true)
  assert_true(
    notion_database_read_snapshots_relation_specification(
      [("é", snapshot), ("é", snapshot)],
      snapshot_test_limits(),
      2,
      100,
    )
    is Ok(_),
  )
  assert_eq(
    notion_database_read_snapshots_relation_specification(
      [("tasks", snapshot), ("tasks", snapshot)],
      snapshot_test_limits(),
      2,
      23,
    ),
    Err(InvalidSnapshot),
  )
  assert_eq(
    notion_database_read_snapshots_relation_specification(
      [("", snapshot)],
      snapshot_test_limits(),
      1,
      10,
    ),
    Err(InvalidSnapshot),
  )
}

///|
test "Notion snapshot relation inventory charges all aliases comparisons and output boundaries" {
  let snapshot = snapshot_test_empty(system=true)
  let views = [("tasks", snapshot), ("other", snapshot)]
  let wire = notion_database_read_snapshots_relation_specification(
    views,
    snapshot_test_limits(),
    2,
    23,
  ).unwrap()
  assert_eq(
    notion_database_read_snapshots_relation_specification(
      views,
      snapshot_test_limits(),
      2,
      22,
    ),
    Err(BudgetExceeded),
  )
  assert_eq(
    notion_database_read_snapshots_relation_specification(
      views,
      snapshot_test_limits(),
      1,
      23,
    ),
    Err(BudgetExceeded),
  )
  let bytes = @utf8.encode(wire).length()
  assert_eq(
    notion_database_read_snapshots_relation_specification(
      views,
      { ..snapshot_test_limits(), max_bytes: bytes, },
      2,
      23,
    ),
    Ok(wire),
  )
  assert_eq(
    notion_database_read_snapshots_relation_specification(
      views,
      { ..snapshot_test_limits(), max_bytes: bytes - 1, },
      2,
      23,
    ),
    Err(BudgetExceeded),
  )
  for
    limits in [
      { ..snapshot_test_limits(), max_nodes: 2, },
      { ..snapshot_test_limits(), max_depth: 2, },
    ] {
    assert_eq(
      notion_database_read_snapshots_relation_specification(
        views, limits, 2, 23,
      ),
      Err(BudgetExceeded),
    )
  }
  assert_eq(
    notion_database_read_snapshots_relation_specification(
      views,
      snapshot_test_limits(),
      -1,
      23,
    ),
    Err(InvalidLimits),
  )
  assert_eq(
    notion_database_read_snapshots_relation_specification(
      views,
      snapshot_test_limits(),
      2,
      -1,
    ),
    Err(InvalidLimits),
  )
}

///|
test "Notion snapshot relation inventory refuses foreign or partial originals without upgrading schema" {
  let original = snapshot_test_empty(system=true)
  let copy = { ..original, }
  let partial = snapshot_test_empty()
  let refused : Array[(NotionDatabaseReadSnapshot, NotionReadSnapshotIssue)] = [
    (copy, ForeignOriginal),
    (partial, SchemaMismatch),
  ]
  for (snapshot, issue) in refused {
    assert_eq(
      notion_database_read_snapshots_relation_specification(
        [("tasks", original), ("other", snapshot)],
        snapshot_test_limits(),
        2,
        23,
      ),
      Err(issue),
    )
  }
  assert_eq(
    notion_database_read_snapshots_relation_specification(
      [("tasks-é😀", original), ("accounts", original)],
      snapshot_test_limits(),
      2,
      1000,
    ),
    Ok(snapshot_relations_expected()),
  )
}
