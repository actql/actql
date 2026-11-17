///|
fn inventory_views(count : Int) -> Array[RowViewSpec] {
  let views = []
  for index in 0..<count {
    views.push({
      resource: "records_" + index.to_string(),
      resource_kind: "record",
      fields: [{ name: "id", value_type: "number", nullable: false, }],
    })
  }
  views
}

///|
test "installed authored restore uses the original inventory and preserves explicit limits" {
  let views = inventory_views(65)
  let bodies : Array[Json] = []
  for view in views {
    bodies.push({
      "resource": view.resource.to_json(),
      "resource_kind": view.resource_kind.to_json(),
      "fields": [{ "name": "id", "type": "number", "nullable": false }],
    })
  }
  let wire = ({ "views": bodies } : Json).stringify()
  let original = restore_row_declaration(
    "inventory",
    "fixture",
    "fixture/0.1",
    wire,
    None,
  ).unwrap()
  assert_eq(original.views.length(), 65)
  let last = row_declaration_view(
    original, "connector://inventory/records_64#records",
  ).unwrap()
  assert_eq(last.resource, "records_64")
  assert_eq(last.fields, ["id"])
  assert_true(
    generate_row_declaration(
      "inventory",
      "fixture",
      "fixture/0.1",
      [views[0], views[1]],
      { ..declaration_limits, max_views: 1, },
    )
    is Err(InvalidView),
  )
  assert_true(
    restore_row_declaration(
      "inventory",
      "fixture",
      "fixture/0.1",
      wire,
      Some("sha256:" + "0".repeat(64)),
    )
    is Err(ForeignDeclaration),
  )
}

///|
test "installed Relation restore uses every original view without changing explicit constructors" {
  let field_map = "{\"id\":{\"nullable\":false,\"type\":\"number\"}}"
  // Independently hash the literal canonical field-map bytes, not product
  // declaration or schema output.
  let schema_cid = "sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513"
  let bodies : Array[Json] = []
  let views : Array[RowRelationViewSpec] = []
  for index in 0..<65 {
    let resource = "records_" + index.to_string()
    bodies.push({
      "resource": resource.to_json(),
      "resource_kind": "record",
      "schema_wire": field_map.to_json(),
      "schema_cid": schema_cid.to_json(),
    })
    views.push({
      resource,
      resource_kind: "record",
      schema_wire: field_map,
      schema_cid,
      request_schema_wire: None,
      facts_wire: None,
      acquisition_wire: None,
    })
  }
  let original = restore_relation_row_declaration(
    "inventory",
    "fixture",
    "fixture/0.1",
    ({ "views": bodies } : Json).stringify(),
    None,
  ).unwrap()
  assert_eq(original.views.length(), 65)
  assert_eq(
    row_declaration_view(original, "connector://inventory/records_64#records").unwrap().fields,
    ["id"],
  )
  assert_true(
    generate_relation_row_declaration(
      "inventory",
      "fixture",
      "fixture/0.1",
      [views[0], views[1]],
      { ..declaration_limits, max_views: 1, },
    )
    is Err(InvalidSpecification),
  )
}
