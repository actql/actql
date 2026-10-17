///|
test "Notion saved full schema projects exact schema bytes into existing relation specification" {
  let snapshot = snapshot_test_empty(system=true)
  let resource = "tasks-é😀"
  let specification = notion_database_read_snapshot_relation_specification(
    snapshot,
    resource,
    snapshot_test_limits(),
  ).unwrap()
  let parsed = @source.parse_json(specification, {
    max_input_bytes: 32768,
    max_nodes: 2048,
    max_depth: 32,
  }).unwrap()
  let cursor = @decode.admit(parsed, {
    max_nodes: 2048,
    max_depth: 32,
    max_string_bytes: 32768,
    max_total_string_bytes: 32768,
  }).unwrap()
  assert_eq(@decode.object_length(cursor), Some(1))
  let root = @decode.open_object(cursor).unwrap()
  let views = @decode.lookup(root, "views").unwrap()
  assert_eq(@decode.array_length(views), Some(1))
  let view = @decode.element_at(views, 0).unwrap()
  assert_eq(@decode.object_length(view), Some(4))
  let view = @decode.open_object(view).unwrap()
  assert_eq(
    @decode.text(@decode.lookup(view, "resource").unwrap()),
    Ok(resource),
  )
  assert_eq(
    @decode.text(@decode.lookup(view, "resource_kind").unwrap()),
    Ok("notion_database"),
  )
  assert_eq(
    @decode.text(@decode.lookup(view, "schema_wire").unwrap()),
    Ok(snapshot.schema_wire),
  )
  assert_eq(
    @decode.text(@decode.lookup(view, "schema_cid").unwrap()),
    Ok(snapshot.schema_cid),
  )
  assert_true(@decode.lookup(view, "facts_wire") is None)
  assert_true(@decode.lookup(view, "acquisition_wire") is None)
  assert_eq(notion_database_read_snapshot_wire(snapshot), Ok(snapshot.wire))
}

///|
test "Notion relation specification refuses property only or copied saved originals" {
  let property = snapshot_test_empty()
  assert_eq(
    notion_database_read_snapshot_relation_specification(
      property,
      "tasks",
      snapshot_test_limits(),
    ),
    Err(SchemaMismatch),
  )
  let snapshot = snapshot_test_empty(system=true)
  let copy = { ..snapshot, }
  assert_eq(
    notion_database_read_snapshot_relation_specification(
      copy,
      "tasks",
      snapshot_test_limits(),
    ),
    Err(ForeignOriginal),
  )
  assert_eq(
    notion_database_read_snapshot_relation_specification(
      snapshot,
      "",
      snapshot_test_limits(),
    ),
    Err(InvalidSnapshot),
  )
}

///|
test "Notion relation specification keeps exact output byte node and depth exhaustion" {
  let snapshot = snapshot_test_empty(system=true)
  let wire = notion_database_read_snapshot_relation_specification(
    snapshot,
    "tasks",
    snapshot_test_limits(),
  ).unwrap()
  let bytes = @utf8.encode(wire).length()
  assert_eq(
    notion_database_read_snapshot_relation_specification(snapshot, "tasks", {
      ..snapshot_test_limits(),
      max_bytes: bytes,
    }),
    Ok(wire),
  )
  assert_eq(
    notion_database_read_snapshot_relation_specification(snapshot, "tasks", {
      ..snapshot_test_limits(),
      max_bytes: bytes - 1,
    }),
    Err(BudgetExceeded),
  )
  assert_eq(
    notion_database_read_snapshot_relation_specification(snapshot, "tasks", {
      ..snapshot_test_limits(),
      max_nodes: 1,
    }),
    Err(BudgetExceeded),
  )
  assert_eq(
    notion_database_read_snapshot_relation_specification(snapshot, "tasks", {
      ..snapshot_test_limits(),
      max_depth: 1,
    }),
    Err(BudgetExceeded),
  )
  assert_eq(
    notion_database_read_snapshot_relation_specification(snapshot, "tasks", {
      ..snapshot_test_limits(),
      max_bytes: 0,
    }),
    Err(InvalidLimits),
  )
}
