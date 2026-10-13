///|
fn vector_fixture_saved_view() -> RowRelationViewSpec {
  {
    resource: "vectors",
    resource_kind: "table",
    schema_wire: (
      #|{"id":{"nullable":false,"type":"number"},"left_vector":{"dimensions":2,"element_type":"f32","nullable":false,"type":"vector"},"right_vector":{"dimensions":2,"element_type":"f32","nullable":true,"type":"vector"}}
    ),
    // SHA-256 of the independently authored canonical field-map bytes.
    schema_cid: "sha256:6d31ea776fe51f6447312c10f7f575b97d3c5a3fe88c27d4c1fe105a1d564849",
    request_schema_wire: None,
    facts_wire: None,
    acquisition_wire: None,
  }
}

///|
fn vector_fixture_row_schema() -> @schema.Schema {
  @schema.from_fields(
    [
      (@schema.Unqualified("id"), @contract.primitive(@contract.NumberType, nullable=false)),
      (@schema.Unqualified("left_vector"), @contract.vector_contract(2.0, nullable=false).unwrap()),
      (@schema.Unqualified("right_vector"), @contract.vector_contract(2.0, nullable=true).unwrap()),
    ],
    max_fields=3,
    max_name_bytes=64,
  ).unwrap()
}

///|
test "Vector fixture full declaration preserves dimension nullability and independent schema CID" {
  let view = vector_fixture_saved_view()
  let original = match generate_relation_row_declaration(
    "vector_fixture", "vector_fixture", "vector_fixture/0.1", [view], declaration_limits,
  ) {
    Ok(declaration) => declaration
    Err(issue) => {
      if issue is InvalidContracts {
        abort("RowHostIssue.InvalidContracts: original Vector declaration")
      }
      abort("unexpected RowHostIssue: original Vector declaration")
    }
  }
  assert_eq(original.views[0].fields, ["id", "left_vector", "right_vector"])
  let body = "{\"fields\":" + view.schema_wire + ",\"version\":\"actql-relation-schema/0.1\"}"
  assert_true(original.contracts.any(wire => wire.contains(body)))
  let saved = ({ "views": [{
    "resource": view.resource,
    "resource_kind": view.resource_kind,
    "schema_wire": view.schema_wire,
    "schema_cid": view.schema_cid,
  }] } : Json).stringify()
  let restored = restore_relation_row_declaration(
    "vector_fixture", "vector_fixture", "vector_fixture/0.1", saved, Some(original.catalog_cid),
  ).unwrap()
  assert_eq(restored.catalog, original.catalog)
  assert_eq(restored.contracts, original.contracts)
  assert_true(generate_relation_row_declaration(
    "vector_fixture", "vector_fixture", "vector_fixture/0.1",
    [{ ..view, schema_cid: "sha256:" + "0".repeat(64) }], declaration_limits,
  ) is Err(InvalidContracts))
  // The saved Source wire is checked, not the authored Values shorthand.
  let authored = {
    ..view,
    schema_wire: (
      #|{"id":{"nullable":false,"type":"number"},"left_vector":{"dimensions":2,"nullable":false,"type":"vector"},"right_vector":{"dimensions":2,"nullable":true,"type":"vector"}}
    ),
    schema_cid: "sha256:ef9fb503e0f3face25dec7348dfec4a772045dcb14d13fea2331b2d1cbbb1c83",
  }
  assert_true(generate_relation_row_declaration(
    "vector_fixture", "vector_fixture", "vector_fixture/0.1", [authored], declaration_limits,
  ) is Err(InvalidContracts))
}

///|
test "RowSource admits the three original Vector rows as typed Vector and SQL NULL cells" {
  let schema = vector_fixture_row_schema()
  let fields = ["id", "left_vector", "right_vector"]
  let limits : @admitted.Limits = { max_nodes: 256, max_depth: 16, max_text_bytes: 4096 }
  for (wire, id, left, right) in [
    ("{\"id\":1,\"left_vector\":[3,4],\"right_vector\":[0,0]}", 1.0, [3.0,4.0], Some([0.0,0.0])),
    ("{\"id\":2,\"left_vector\":[1,0],\"right_vector\":[0,1]}", 2.0, [1.0,0.0], Some([0.0,1.0])),
    ("{\"id\":3,\"left_vector\":[1,1],\"right_vector\":null}", 3.0, [1.0,1.0], None),
  ] {
    let cells = admit_row_source_object(schema, fields, row_presence_cursor(wire), limits).unwrap()
    assert_true(cells[0].unwrap().value is @admitted.Number(actual) && actual == id)
    guard cells[1].unwrap().value is @admitted.Vector(actual_left) else { abort("typed left Vector") }
    assert_eq(@admitted.elements(actual_left), left)
    match right {
      Some(expected) => {
        guard cells[2].unwrap().value is @admitted.Vector(actual_right) else { abort("typed right Vector") }
        assert_eq(@admitted.elements(actual_right), expected)
      }
      None => assert_true(cells[2].unwrap().value is @admitted.Null)
    }
  }
}

///|
test "RowSource rejects wrong Vector dimensions required NULL and missing nullable cells" {
  let schema = vector_fixture_row_schema()
  let fields = ["id", "left_vector", "right_vector"]
  let limits : @admitted.Limits = { max_nodes: 256, max_depth: 16, max_text_bytes: 4096 }
  for (wire, field) in [
    ("{\"id\":1,\"left_vector\":[3],\"right_vector\":[0,0]}", "left_vector"),
    ("{\"id\":1,\"left_vector\":[3,4,5],\"right_vector\":[0,0]}", "left_vector"),
    ("{\"id\":1,\"left_vector\":null,\"right_vector\":[0,0]}", "left_vector"),
    ("{\"id\":1,\"left_vector\":[3,4],\"right_vector\":[0]}", "right_vector"),
    ("{\"id\":1,\"left_vector\":[3,4],\"right_vector\":7}", "right_vector"),
  ] {
    assert_true(admit_row_source_object(schema, fields, row_presence_cursor(wire), limits) is Err(Value(actual)) && actual == field)
  }
  // Nullable means a NULL cell is allowed; it does not authorize omission.
  assert_true(admit_row_source_object(schema, fields,
    row_presence_cursor("{\"id\":1,\"left_vector\":[3,4]}"), limits,
  ) is Err(MissingField("right_vector")))
}
