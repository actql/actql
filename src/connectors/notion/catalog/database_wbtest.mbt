///|
fn database_test_limits() -> NotionDatabaseLimits {
  {
    max_bytes: 8192,
    max_nodes: 512,
    max_depth: 16,
    max_data_sources: 8,
    max_properties: 8,
    max_identity_bytes: 64,
    max_name_bytes: 64,
  }
}

///|
fn database_test_original() -> NotionDatabaseCatalog {
  project_notion_database(
    @utf8.encode(
      (
        #|{"object":"database","id":"db","data_sources":[{"id":"s1","name":"同名"},{"id":"s2","name":"同名"}],"extra":{"bounded":true}}
      ),
    ),
    database_test_limits(),
  ).unwrap()
}

///|
fn database_test_schema() -> String {
  (
    #|{"object":"data_source","id":"s2","parent":{"type":"database_id","database_id":"db"},"properties":{"Name":{"id":"title","name":"Name","type":"title","title":{}},"é":{"id":"r%3Ax","name":"é","type":"relation","relation":{"data_source_id":"related","type":"single_property","single_property":{}}},"":{"id":"future","name":"","type":"new_vendor_kind","new_vendor_kind":{"not_a_logical_type":true}}}}
  )
}

///|
test "Notion database discovery preserves multiple sources names and exact bytes without implicit selection" {
  let database = database_test_original()
  assert_eq(database.id, "db")
  assert_eq(notion_database_source_count(database), 2)
  assert_eq(notion_database_source_at(database, 0), Some(("s1", "同名")))
  assert_eq(notion_database_source_at(database, 1), Some(("s2", "同名")))
  assert_eq(notion_database_source_at(database, -1), None)
  assert_eq(notion_database_source_at(database, 2), None)
  assert_eq(
    project_notion_data_source(database, -1, b"{}", database_test_limits()).unwrap_err(),
    InvalidSelection,
  )
  assert_eq(
    project_notion_data_source(database, 2, b"{}", database_test_limits()).unwrap_err(),
    InvalidSelection,
  )
  let wire = b"{\"object\":\"database\",\"id\":\"empty\",\"data_sources\":[]}"
  let empty = project_notion_database(wire, {
    ..database_test_limits(),
    max_data_sources: 0,
  }).unwrap()
  assert_eq(notion_database_source_count(empty), 0)
  assert_eq(empty.response_sha256, @sha.hex(wire))
  assert_eq(@decode.object_length(notion_database_original(empty)), Some(3))
}

///|
test "Notion selected schema retains original database occurrence not equal ids or hashes" {
  let database = database_test_original()
  let schema = project_notion_data_source(
    database,
    1,
    @utf8.encode(database_test_schema()),
    database_test_limits(),
  ).unwrap()
  assert_eq(schema.id, "s2")
  assert_eq(notion_data_source_selected_index(schema), 1)
  assert_true(physical_equal(notion_data_source_database(schema), database))
  assert_true(notion_data_source_matches_database(schema, database))
  assert_true(
    !notion_data_source_matches_database(schema, database_test_original()),
  )
  assert_eq(
    schema.response_sha256,
    @sha.hex(@utf8.encode(database_test_schema())),
  )
  assert_eq(@decode.object_length(notion_data_source_original(schema)), Some(4))
  assert_eq(
    project_notion_data_source(
      database,
      0,
      @utf8.encode(database_test_schema()),
      database_test_limits(),
    ).unwrap_err(),
    ForeignDatabase,
  )
}

///|
test "Notion property inventory preserves exact names ids Unicode and future ordinary DATA" {
  let schema = project_notion_data_source(
    database_test_original(),
    1,
    @utf8.encode(database_test_schema()),
    database_test_limits(),
  ).unwrap()
  assert_eq(notion_data_source_property_count(schema), 3)
  let title = notion_data_source_property_at(schema, 0).unwrap()
  assert_eq((title.name, title.id, title.kind), ("Name", "title", "title"))
  let relation = notion_data_source_property_at(schema, 1).unwrap()
  assert_eq(
    (relation.name, relation.id, relation.kind),
    ("é", "r%3Ax", "relation"),
  )
  let definition = notion_property_definition(relation)
  assert_eq(@decode.object_length(definition), Some(4))
  let future = notion_data_source_property_at(schema, 2).unwrap()
  assert_eq((future.name, future.kind), ("", "new_vendor_kind"))
  assert_true(notion_data_source_property_at(schema, -1) is None)
  assert_true(notion_data_source_property_at(schema, 3) is None)
}

///|
test "Notion foreign containing database and malformed parent never rebind the selected source" {
  let database = database_test_original()
  let external =
    #|{"object":"data_source","id":"s1","parent":{"type":"data_source_id","database_id":"db","data_source_id":"sync-parent"},"properties":{}}
  let schema = project_notion_data_source(
    database,
    0,
    @utf8.encode(external),
    database_test_limits(),
  ).unwrap()
  assert_eq(notion_data_source_property_count(schema), 0)
  for
    parent in [
      (
        #|{"type":"database_id","database_id":"foreign"}
      ),
      (
        #|{"type":"page_id","database_id":"db","page_id":"page"}
      ),
      (
        #|{"type":"data_source_id","database_id":"db"}
      ),
      (
        #|{"type":"data_source_id","database_id":"db","data_source_id":""}
      ),
      (
        #|{"type":"database_id","database_id":null}
      ),
    ] {
    let wire = "{\"object\":\"data_source\",\"id\":\"s1\",\"parent\":" +
      parent +
      ",\"properties\":{}}"
    assert_true(
      project_notion_data_source(
        database,
        0,
        @utf8.encode(wire),
        database_test_limits(),
      )
      is Err(_),
    )
  }
}

///|
test "Notion metadata rejects duplicate identities and inconsistent definitions before any projection" {
  for
    wire in [
      (
        #|{"object":"database","id":"db","data_sources":[{"id":"s","name":"first"},{"id":"s","name":"second"}]}
      ),
      (
        #|{"object":"database","id":"db","data_sources":[{"id":"","name":"empty"}]}
      ),
      (
        #|{"object":"database","id":"db","data_sources":[{"id":"s","name":null}]}
      ),
    ] {
    assert_true(
      project_notion_database(@utf8.encode(wire), database_test_limits())
      is Err(_),
    )
  }
  for
    properties in [
      (
        #|{"a":{"id":"same","name":"a","type":"title","title":{}},"b":{"id":"same","name":"b","type":"checkbox","checkbox":{}}}
      ),
      (
        #|{"a":{"id":"a","name":"renamed","type":"title","title":{}}}
      ),
      (
        #|{"a":{"id":"a","name":"a","type":"title","rich_text":{}}}
      ),
      (
        #|{"a":{"id":"a","name":"a","type":"title","title":null}}
      ),
      (
        #|{"a":{"id":"a","name":"a","type":"title","title":[]}}
      ),
      (
        #|{"a":{"id":"a","name":"a","type":"title","title":{}} ,"a":{"id":"b","name":"a","type":"title","title":{}}}
      ),
    ] {
    let wire = "{\"object\":\"data_source\",\"id\":\"s1\",\"parent\":{\"type\":\"database_id\",\"database_id\":\"db\"},\"properties\":" +
      properties +
      "}"
    assert_true(
      project_notion_data_source(
        database_test_original(),
        0,
        @utf8.encode(wire),
        database_test_limits(),
      )
      is Err(_),
    )
  }
}

///|
test "Notion metadata bounds include every original byte node depth identity and name" {
  let wire = b"{\"object\":\"database\",\"id\":\"db\",\"data_sources\":[{\"id\":\"s\",\"name\":\"abc\"}]}"
  assert_true(
    project_notion_database(wire, {
      ..database_test_limits(),
      max_bytes: wire.length(),
    })
    is Ok(_),
  )
  assert_eq(
    project_notion_database(wire, {
      ..database_test_limits(),
      max_bytes: wire.length() - 1,
    }).unwrap_err(),
    BudgetExceeded,
  )
  for
    bound in [
      { ..database_test_limits(), max_nodes: 1, },
      { ..database_test_limits(), max_depth: 1, },
      { ..database_test_limits(), max_data_sources: 0, },
      { ..database_test_limits(), max_identity_bytes: 1, },
      { ..database_test_limits(), max_name_bytes: 2, },
    ] {
    assert_eq(project_notion_database(wire, bound).unwrap_err(), BudgetExceeded)
  }
  assert_eq(
    project_notion_data_source(
      database_test_original(),
      1,
      @utf8.encode(database_test_schema()),
      { ..database_test_limits(), max_properties: 2, },
    ).unwrap_err(),
    BudgetExceeded,
  )
  for
    bound in [
      { ..database_test_limits(), max_nodes: 0, },
      { ..database_test_limits(), max_properties: -1, },
      { ..database_test_limits(), max_name_bytes: -1, },
    ] {
    assert_eq(project_notion_database(wire, bound).unwrap_err(), InvalidLimits)
  }
}

///|
test "Notion error and malformed original metadata cannot masquerade as empty success" {
  for
    wire in [
      b"{}", b"null", b"[]", b"\xff\x80", b"{\"object\":\"error\",\"status\":403}",
      b"{\"object\":\"database\",\"id\":\"db\",\"data_sources\":[]}{ }", b"{\"object\":\"database\",\"id\":\"db\",\"data_sources\":[],\"id\":\"db\"}",
      b"{\"object\":\"database\",\"id\":\"db\",\"data_sources\":null}",
    ] {
    assert_true(project_notion_database(wire, database_test_limits()) is Err(_))
  }
}

///|
test "Notion property names retain distinct Unicode and whitespace spellings" {
  let wire =
    #|{"object":"data_source","id":"s1","parent":{"type":"database_id","database_id":"db"},"properties":{"é":{"id":"a","name":"é","type":"title","title":{}},"é":{"id":"b","name":"é","type":"rich_text","rich_text":{}},"x\r\n":{"id":"c","name":"x\r\n","type":"checkbox","checkbox":{}}}}
  let schema = project_notion_data_source(
    database_test_original(),
    0,
    @utf8.encode(wire),
    database_test_limits(),
  ).unwrap()
  assert_eq(notion_data_source_property_at(schema, 0).unwrap().name, "é")
  assert_eq(notion_data_source_property_at(schema, 1).unwrap().name, "é")
  assert_eq(notion_data_source_property_at(schema, 2).unwrap().name, "x\r\n")
}
