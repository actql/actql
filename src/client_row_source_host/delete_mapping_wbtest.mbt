///|
fn delete_mapping_limits() -> RowDeclarationLimits {
  {
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 32,
    max_views: 4,
    max_fields: 16,
  }
}

///|
fn delete_mapping_declaration(id_nullable? : Bool = false) -> RowDeclaration {
  generate_row_declaration(
    "original-delete",
    "fixture",
    "fixture/0.1",
    [
      {
        resource: "records",
        resource_kind: "record",
        fields: [
          { name: "id", value_type: "string", nullable: id_nullable, },
          { name: "value", value_type: "string", nullable: true, },
        ],
      },
    ],
    delete_mapping_limits(),
  ).unwrap()
}

///|
fn original_delete_mapping(declaration : RowDeclaration) -> RowMapping {
  prepare_row_delete_mapping(
    declaration,
    "records",
    "id",
    "fixture:delete",
    "required",
    delete_mapping_limits(),
  ).unwrap()
}

///|
test "DELETE Mapping retains original manifest full schema and no proposed-value fields" {
  let original = delete_mapping_declaration()
  let mapping = original_delete_mapping(original)
  assert_eq(
    mapping.body,
    (
      #|{"connector_manifest_cid":"sha256:5fa04bd432bc9b4a4b5b777502699b8acb1c94e049c449b9a15a6cb08293f47d","conversions":[],"mapping_contract_cid":"sha256:9c14d11bfbbf6c423411f3bb7f156709954fe13437cb6cd4fe1e07baef8a8980","mapping_ref":"mapping:original-delete/records/delete-5e1ac3629b05d411.v1","minimum_approval":"required","permission_rules":[{"effect_kind":"delete","permissions":["fixture:delete"],"selector_class":"id","write_fields":[]}],"primary_identity":"id","required_fields":[],"required_permissions":[],"resource_identity_cid":"sha256:8d405a8763bfe82c234811a4af5e47f59588f9c5a5cc1cea596f6bfe4fcfc416","row_mapping":{},"schema":"actql.mapping_contract/0.1","target_ref":"connector://original-delete/records","target_schema":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:adfed565bc1dc4bff1f6a90f20e7548a777c5df0cc16acdf55255016949acbf9","version":"fixture/0.1","writable_fields":[]}
    ),
  )
  assert_eq(mapping.resource, "records")
  assert_eq(mapping.write_fields, [])
  assert_eq(mapping.omittable, [])
  let body = @json.parse(mapping.body)
  assert_eq(
    spec_text(body, "connector_manifest_cid"),
    Some(original.manifest_entry_cid),
  )
  assert_eq(spec_text(body, "primary_identity"), Some("id"))
  assert_eq(spec_text(body, "minimum_approval"), Some("required"))
  guard body is Object(entries) else { fail("OriginalMappingObjectRequired") }
  assert_eq(entries.get("row_mapping"), Some(({} : Json)))
  assert_eq(entries.get("writable_fields"), Some(([] : Json)))
  assert_eq(entries.get("required_fields"), Some(([] : Json)))
  assert_eq(
    entries.get("permission_rules"),
    Some(
      (
        [
          {
            "effect_kind": "delete",
            "selector_class": "id",
            "write_fields": [],
            "permissions": ["fixture:delete"],
          },
        ] : Json),
    ),
  )
  assert_eq(
    entries.get("target_schema"),
    Some(
      (
        {
          "type": "object",
          "nullable": false,
          "additional_properties": false,
          "fields": {
            "id": { "type": "string", "nullable": false },
            "value": { "type": "string", "nullable": true },
          },
        } : Json),
    ),
  )
  let again = original_delete_mapping(original)
  assert_eq(again.body, mapping.body)
  let changed = prepare_row_delete_mapping(
    original,
    "records",
    "id",
    "fixture:delete",
    "none",
    delete_mapping_limits(),
  ).unwrap()
  assert_true(changed.mapping_cid != mapping.mapping_cid)
}

///|
test "DELETE Mapping rejects absent or nullable identity foreign Resource and invalid choice" {
  assert_true(
    prepare_row_delete_mapping(
      delete_mapping_declaration(id_nullable=true),
      "records",
      "id",
      "fixture:delete",
      "required",
      delete_mapping_limits(),
    )
    is Err(InvalidSpecification),
  )
  for name in ["missing", "value"] {
    assert_true(
      prepare_row_delete_mapping(
        delete_mapping_declaration(),
        "records",
        name,
        "fixture:delete",
        "required",
        delete_mapping_limits(),
      )
      is Err(InvalidSpecification),
    )
  }
  assert_true(
    prepare_row_delete_mapping(
      delete_mapping_declaration(),
      "other",
      "id",
      "fixture:delete",
      "required",
      delete_mapping_limits(),
    )
    is Err(NotWritable("other")),
  )
  for
    (permission, approval) in [("", "required"), ("fixture:delete", "default")] {
    assert_true(
      prepare_row_delete_mapping(
        delete_mapping_declaration(),
        "records",
        "id",
        permission,
        approval,
        delete_mapping_limits(),
      )
      is Err(InvalidSpecification),
    )
  }
}

///|
test "DELETE Mapping caller ceilings apply before parsing original envelope and output" {
  let original = delete_mapping_declaration()
  for
    limits in [
      { ..delete_mapping_limits(), max_bytes: 1, },
      { ..delete_mapping_limits(), max_nodes: 1, },
      { ..delete_mapping_limits(), max_depth: 1, },
      { ..delete_mapping_limits(), max_fields: 1, },
    ] {
    assert_true(
      prepare_row_delete_mapping(
        original, "records", "id", "fixture:delete", "required", limits,
      )
      is Err(_),
    )
  }
  assert_true(
    prepare_row_delete_mapping(
      original,
      "records",
      "id",
      "fixture:delete",
      "required",
      { ..delete_mapping_limits(), max_bytes: 0, },
    )
    is Err(InvalidSpecification),
  )
  assert_eq(
    original_delete_mapping(original).body,
    original_delete_mapping(original).body,
  )
}

///|
test "DELETE Mapping refuses mutated original schema and view envelopes without resealing" {
  let changed = delete_mapping_declaration()
  let index = changed.contracts
    .search_by(wire => wire.contains("\"kind\":\"carrier_schema\""))
    .unwrap()
  changed.contracts[index] = changed.contracts[index].replace(
    old="\"nullable\":true",
    new="\"nullable\":false",
  )
  assert_true(
    prepare_row_delete_mapping(
      changed,
      "records",
      "id",
      "fixture:delete",
      "required",
      delete_mapping_limits(),
    )
    is Err(InvalidSpecification),
  )
  let foreign_view = delete_mapping_declaration()
  foreign_view.view_bodies[0] = foreign_view.view_bodies[0].replace(
    old="\"resource_kind\":\"record\"",
    new="\"resource_kind\":\"foreign\"",
  )
  assert_true(
    prepare_row_delete_mapping(
      foreign_view,
      "records",
      "id",
      "fixture:delete",
      "required",
      delete_mapping_limits(),
    )
    is Err(InvalidSpecification),
  )
}

///|
test "DELETE Mapping is admitted by the existing shape and permission Owner only for delete id" {
  let original = delete_mapping_declaration()
  let mapping = original_delete_mapping(original)
  // Environment section order uses the full member CID, independently of
  // each declaration envelope's self-CID order.
  let contracts = original.contracts.map(wire => {
    let body = @json.parse(wire)
    (canonical_cid(body, delete_mapping_limits()), body)
  })
  contracts.sort_by((a, b) => {
    if key_before(a.0, b.0) {
      -1
    } else if key_before(b.0, a.0) {
      1
    } else {
      0
    }
  })
  let base = object([
    ("version", "actql-check-environment/0.1".to_json()),
    (
      "connector_manifest",
      object([
        ("version", "actql-connectors/0.1".to_json()),
        ("connectors", Json::array([@json.parse(original.manifest_entry)])),
      ]),
    ),
    ("connector_catalogs", Json::array([@json.parse(original.catalog)])),
    ("schema_snapshots", Json::array([])),
    ("connector_capabilities", Json::array([])),
    (
      "source_views",
      Json::array(original.view_bodies.map(wire => @json.parse(wire))),
    ),
    ("contract_registry", Json::array(contracts.map(entry => entry.1))),
    ("mapping_contracts", Json::array([@json.parse(mapping.body)])),
    ("command_contracts", Json::array([])),
    ("model_task_contracts", Json::array([])),
    ("host_policy_profile", object([])),
  ])
  guard base is Object(fields) else { fail("OriginalEnvironmentObject") }
  let evidence_cid = canonical_cid(base, delete_mapping_limits())
  let entries = []
  for name, value in fields {
    entries.push((name, value))
  }
  entries.push(("evidence_bundle_cid", evidence_cid.to_json()))
  let environment_body = object(entries)
  let limits : @environment.Limits = {
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 32,
    max_members: 100,
  }
  let wire = canonical_text(environment_body, delete_mapping_limits())
  let environment = @environment.read(@utf8.encode(wire), evidence_cid, limits).unwrap()
  let shapes = @environment.check_mapping_contract_shapes(
    environment, limits, 10000,
  ).unwrap()
  let shape = @environment.mapping_shape_at(shapes, 0).unwrap()
  let selected = @environment.select_mapping_permissions(
    shape,
    "delete",
    "id",
    [],
    100,
  ).unwrap()
  assert_eq(@environment.mapping_permission_names(selected), ["fixture:delete"])
  for
    (kind, selector, fields) in [
      ("update", "id", []),
      ("create", "none", []),
      ("delete", "id", ["value"]),
    ] {
    assert_true(
      @environment.select_mapping_permissions(
        shape, kind, selector, fields, 100,
      )
      is Err(_),
    )
  }
}

///|
test "DELETE Mapping preserves a required Array field and refuses invented conditional presence" {
  let required = "{\"choices\":{\"items\":{\"nullable\":false,\"type\":\"string\"},\"nullable\":false,\"type\":\"array\"},\"id\":{\"nullable\":false,\"type\":\"string\"}}"
  let conditional = "{\"choices\":{\"contract\":{\"items\":{\"nullable\":false,\"type\":\"string\"},\"nullable\":false,\"type\":\"array\"},\"presence\":\"conditional\"},\"id\":{\"nullable\":false,\"type\":\"string\"}}"
  let generate = (wire : String) => {
    let body = @json.parse(wire)
    let declared = generate_relation_row_declaration(
      "original-delete",
      "fixture",
      "fixture/0.1",
      [
        {
          resource: "records",
          resource_kind: "record",
          schema_wire: canonical_text(body, delete_mapping_limits()),
          schema_cid: canonical_cid(body, delete_mapping_limits()),
          request_schema_wire: None,
          facts_wire: None,
          acquisition_wire: None,
        },
      ],
      delete_mapping_limits(),
    ).unwrap()
    prepare_row_delete_mapping(
      declared,
      "records",
      "id",
      "fixture:delete",
      "required",
      delete_mapping_limits(),
    )
  }
  let mapping = generate(required).unwrap()
  assert_true(
    mapping.body.contains(
      "\"choices\":{\"items\":{\"nullable\":false,\"type\":\"string\"},\"nullable\":false,\"type\":\"array\"}",
    ),
  )
  assert_true(generate(conditional) is Err(InvalidSpecification))
}
