///|
fn project_catalogue_declaration_fixture() -> Json {
  {
    "views": [
      {
        "resource": "records",
        "resource_kind": "record",
        "schema": { "id": { "type": "string", "nullable": false } },
        "facts": { "relation_keys": { "candidate_keys": [["id"]] } },
      },
    ],
  }
}

///|
test "portable public catalogue projection preserves the original canonical schema and existing Relation admission" {
  let expected = "{\"views\":[{\"facts_wire\":\"{\\\"relation_keys\\\":{\\\"candidate_keys\\\":[[\\\"id\\\"]]}}\",\"resource\":\"records\",\"resource_kind\":\"record\",\"schema_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"schema_wire\":\"{\\\"id\\\":{\\\"nullable\\\":false,\\\"type\\\":\\\"string\\\"}}\"}]}"
  let wire = project_relation_declaration_input(
    project_catalogue_declaration_fixture(),
    4096,
    1024,
    16,
  ).unwrap()
  assert_eq(wire, expected)
  let declaration = restore_relation_row_declaration(
    "original",
    "fixture",
    "fixture/0.1",
    wire,
    None,
  ).unwrap()
  assert_eq(declaration.views.length(), 1)
  assert_eq(declaration.views[0].resource, "records")
  assert_eq(declaration.views[0].fields, ["id"])
}

///|
test "portable public catalogue projection retains strict private field and unknown input refusal" {
  for extra in ["schema_wire", "schema_cid", "facts_wire", "unknown"] {
    let entry = project_catalogue_declaration_fixture()
    guard entry is Object(root) &&
      root.get("views") is Some(Array(views)) &&
      views[0] is Object(fields) else {
      fail("fixture")
    }
    fields[extra] = Json::string("foreign")
    let wire = project_relation_declaration_input(entry, 4096, 1024, 16).unwrap()
    assert_true(
      restore_relation_row_declaration(
        "original",
        "fixture",
        "fixture/0.1",
        wire,
        None,
      )
      is Err(_),
    )
    if extra.has_suffix("_wire") || extra == "schema_cid" {
      assert_true(wire.contains("public_input_field:" + extra))
    } else {
      assert_true(wire.contains("unknown"))
    }
  }
  for
    invalid in [
      Json::null(),
      ({ "views": 1 } : Json),
      ({ "views": [1] } : Json),
    ] {
    assert_true(
      project_relation_declaration_input(invalid, 4096, 1024, 16)
      is Err(InvalidSpecification),
    )
  }
}

///|
test "portable public catalogue projection keeps exact and one short encoding bounds without granting capacity" {
  let expected = "{\"views\":[{\"facts_wire\":\"{\\\"relation_keys\\\":{\\\"candidate_keys\\\":[[\\\"id\\\"]]}}\",\"resource\":\"records\",\"resource_kind\":\"record\",\"schema_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"schema_wire\":\"{\\\"id\\\":{\\\"nullable\\\":false,\\\"type\\\":\\\"string\\\"}}\"}]}"
  let input = project_catalogue_declaration_fixture()
  assert_eq(
    project_relation_declaration_input(input, expected.length(), 1024, 16).unwrap(),
    expected,
  )
  assert_true(
    project_relation_declaration_input(input, expected.length() - 1, 1024, 16)
    is Err(InvalidSpecification),
  )
  assert_true(
    project_relation_declaration_input(input, 4096, 0, 16)
    is Err(InvalidSpecification),
  )
  assert_true(
    project_relation_declaration_input(input, 4096, 1024, 0)
    is Err(InvalidSpecification),
  )
}
