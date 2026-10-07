///|
fn saved_relation_view() -> RowRelationViewSpec {
  {
    resource: "rows",
    resource_kind: "table",
    schema_wire: (
      #|{"id":{"nullable":false,"type":"number"},"p":{"contract":{"max_utf8_bytes":32,"nullable":true,"type":"string"},"presence":"conditional"}}
    ),
    // Independently authored field-map bytes hashed with Node SHA-256.
    schema_cid: "sha256:326b7ad79f0904551619945e3eef1915cd61ac943ee05bb8e74f2ef61eea9ee5",
  }
}

///|
test "saved Relation declaration emits original presence and text extent contracts" {
  let view = saved_relation_view()
  let declaration = generate_relation_row_declaration(
    "table-local",
    "table",
    "table/0.1",
    [view],
    declaration_limits,
  ).unwrap()
  assert_eq(declaration.views[0].fields, ["id", "p"])
  assert_eq(
    declaration.views[0].source_ref,
    "connector://table-local/rows#records",
  )
  let body = "{\"fields\":" +
    view.schema_wire +
    ",\"version\":\"actql-relation-schema/0.1\"}"
  assert_true(declaration.contracts.any(wire => wire.contains(body)))
  assert_false(
    declaration.contracts.any(wire => wire.contains("\"type\":\"schema\"")),
  )
  let wire = (
    {
      "views": [
        {
          "resource": view.resource,
          "resource_kind": view.resource_kind,
          "schema_wire": view.schema_wire,
          "schema_cid": view.schema_cid,
        },
      ],
    } : Json).stringify()
  let restored = restore_relation_row_declaration(
    "table-local",
    "table",
    "table/0.1",
    wire,
    Some(declaration.catalog_cid),
  ).unwrap()
  assert_eq(restored.catalog, declaration.catalog)
  assert_eq(restored.contracts, declaration.contracts)
}

///|
test "saved Relation declarations refuse CID drift and never default schema metadata" {
  let view = saved_relation_view()
  for
    changed in [
      { ..view, schema_wire: view.schema_wire + " ", },
      { ..view, schema_wire: "{}", },
      { ..view, schema_cid: "sha256:" + "0".repeat(64), },
    ] {
    assert_true(
      generate_relation_row_declaration(
        "table-local",
        "table",
        "table/0.1",
        [changed],
        declaration_limits,
      )
      is Err(InvalidContracts),
    )
  }
  assert_true(
    restore_relation_row_declaration(
      "table-local",
      "table",
      "table/0.1",
      "{\"views\":[{\"resource\":\"rows\",\"resource_kind\":\"table\",\"schema_cid\":\"sha256:" +
      "0".repeat(64) +
      "\"}]}",
      None,
    )
    is Err(InvalidSpecification),
  )
  assert_true(
    generate_relation_row_declaration(
      "table-local",
      "table",
      "table/0.1",
      [view, view],
      { ..declaration_limits, max_nodes: 10, },
    )
    is Err(_),
  )
}
