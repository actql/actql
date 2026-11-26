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
  let sources =
    #|{"operation":"update","sources":[{"target":"amount","field":"amount","null_behavior":"write_null"},{"target":"choices","field":"choices","null_behavior":"reject"}]}
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
      "{}",
      "[]",
      (
        #|{"operation":"update","sources":[{"target":"amount","target":"choices","field":"amount","null_behavior":"reject"}]}
      ),
      (
        #|{"operation":"update","sources":[{"target":"amount","field":"amount","null_behavior":"reject","extra":true}]}
      ),
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
test "installed guarded Mapping selects the original ordered UPDATE or File UPSERT" {
  let declaration = @client_row_source_host.restore_relation_row_declaration(
    "ordered",
    "fixture",
    "fixture/0.1",
    @client_row_source_host.project_relation_declaration_input(
      {
        "views": [
          {
            "resource": "records",
            "resource_kind": "record",
            "schema": {
              "site": { "type": "string", "nullable": false },
              "serial": { "type": "int64", "nullable": false },
              "label": { "type": "string", "nullable": true },
            },
            "facts": {
              "relation_keys": { "candidate_keys": [["site", "serial"]] },
            },
          },
        ],
      },
      65536,
      8192,
      32,
    ).unwrap(),
    None,
  ).unwrap()
  let writes =
    #|{"writes":[{"resource":"records","primary_identity":{"kind":"tuple","fields":["site","serial"]},"update":{"fields":["label"],"permission":"fixture:update","approval":"required"},"upsert":{"fields":["label"],"permission":"fixture:upsert","approval":"required"}}]}
  let input =
    #|{"operation":"@operation","sources":[{"target":"label","field":"incoming","null_behavior":"write_null"}]}
  let mappings = []
  for
    (operation, kind, selector) in [
      ("update", "update", "match_tuple"),
      ("file-upsert", "upsert", "key_tuple"),
    ] {
    let wire = client_program_row_source_prepare_update_mapping(
      declaration,
      writes,
      "records",
      input.replace(old="@operation", new=operation),
    )
    guard @json.parse(wire) is Object(output) &&
      output.get("body") is Some(String(body)) &&
      output.get("mapping_cid") is Some(String(cid)) else {
      abort("missing ordered Mapping")
    }
    mappings.push(cid)
    assert_true(body.contains("actql.mapping_contract/0.2"))
    assert_true(body.contains("\"fields\":[\"site\",\"serial\"]"))
    assert_true(body.contains("\"effect_kind\":\"" + kind + "\""))
    assert_true(body.contains("\"selector_class\":\"" + selector + "\""))
    assert_true(body.contains("\"fixture:" + kind + "\""))
    let required = if kind == "upsert" { "[\"label\"]" } else { "[]" }
    assert_true(body.contains("\"required_fields\":" + required))
  }
  assert_true(mappings[0] != mappings[1])
  assert_eq(
    client_program_row_source_prepare_update_mapping(
      declaration,
      writes,
      "records",
      input.replace(old="@operation", new="upsert"),
    ),
    "{\"issue\":\"InvalidSpecification\"}",
  )
  assert_eq(
    client_program_row_source_prepare_update_mapping(
      declaration,
      writes.replace(old="\"site\",\"serial\"", new="\"serial\",\"site\""),
      "records",
      input.replace(old="@operation", new="file-upsert"),
    ),
    "{\"issue\":\"InvalidSpecification\"}",
  )
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
