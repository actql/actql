///|
fn installed_update_bridge_declaration() -> @client_row_source_host.RowDeclaration {
  @client_row_source_host.generate_relation_row_declaration(
    "typed-write",
    "fixture",
    "fixture/0.1",
    [
      {
        resource: "records",
        resource_kind: "record",
        schema_wire: "{\"amount\":{\"nullable\":true,\"precision\":18,\"scale\":3,\"type\":\"decimal\"},\"choices\":{\"items\":{\"nullable\":false,\"type\":\"string\"},\"nullable\":false,\"type\":\"array\"},\"id\":{\"nullable\":false,\"type\":\"string\"},\"label\":{\"nullable\":true,\"type\":\"string\"}}",
        schema_cid: "sha256:2618d0643c294611e48b9b7a5b21a88acf4de645cf0682b064d62f040a71bb8e",
        request_schema_wire: None,
        facts_wire: None,
        acquisition_wire: None,
      },
    ],
    {
      max_bytes: 65536,
      max_nodes: 8192,
      max_depth: 64,
      max_views: 8,
      max_fields: 32,
    },
  ).unwrap()
}

///|
test "installed UPDATE bridge returns the existing mapping metadata projection" {
  let declaration = installed_update_bridge_declaration()
  let writes = "{\"writes\":[{\"resource\":\"records\",\"primary_identity\":\"id\",\"update\":{\"fields\":[\"amount\",\"choices\"],\"permission\":\"fixture:update\",\"approval\":\"required\"}}]}"
  let sources = "[{\"target\":\"amount\",\"field\":\"amount\",\"null_behavior\":\"write_null\"},{\"target\":\"choices\",\"field\":\"choices\",\"null_behavior\":\"reject\"}]"
  let wire = client_program_row_source_prepare_update_mapping(
    declaration, writes, "records", sources,
  )
  guard @json.parse(wire) is Object(output) &&
    output.get("body") is Some(String(body)) else {
    abort("mapping metadata")
  }
  assert_true(output.get("mapping_ref") is Some(String(_)))
  assert_true(output.get("mapping_cid") is Some(String(_)))
  assert_true(output.get("write_fields") is Some(Array(_)))
  assert_true(output.get("omittable") is Some(Array(_)))
  assert_true(body.contains("\"effect_kind\":\"update\""))
  assert_true(body.contains("\"precision\":18"))
  for
    bad in [
      "{}", "[{\"target\":\"amount\",\"target\":\"choices\",\"field\":\"amount\",\"null_behavior\":\"reject\"}]",
      "[{\"target\":\"amount\",\"field\":\"amount\",\"null_behavior\":\"reject\",\"extra\":true}]",
    ] {
    assert_eq(
      client_program_row_source_prepare_update_mapping(
        declaration, writes, "records", bad,
      ),
      "{\"issue\":\"InvalidSpecification\"}",
    )
  }
}

///|
test "installed file CREATE bridge binds typed fields and approval" {
  let declaration = installed_update_bridge_declaration()
  let writes =
    #|{"writes":[{"resource":"records","primary_identity":"id","create":{"fields":["amount","choices","label"],"permission":"fixture:create","approval":"required"}}]}
  let sources =
    #|[{"target":"amount","field":"a","null_behavior":"write_null"},{"target":"choices","field":"c","null_behavior":"reject"},{"target":"label","field":"l","null_behavior":"reject"}]
  let output = client_program_row_source_prepare_file_create_mapping(
    declaration, writes, "records", sources,
  )
  guard @json.parse(output) is Object(metadata) &&
    metadata.get("body") is Some(String(body)) else {
    fail("missing file CREATE Mapping")
  }
  assert_true(body.contains("\"effect_kind\":\"create\""))
  assert_true(body.contains("\"minimum_approval\":\"required\""))
  assert_true(
    body.contains("\"required_fields\":[\"amount\",\"choices\",\"label\"]"),
  )
  assert_eq(
    client_program_row_source_prepare_file_create_mapping(
      declaration,
      writes,
      "records",
      sources.replace(
        old="\"target\":\"label\"",
        new="\"target\":\"id\",\"target\":\"label\"",
      ),
    ),
    "{\"issue\":\"InvalidSpecification\"}",
  )
}
