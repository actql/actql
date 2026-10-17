///|
fn relation_mapping_declaration() -> RowDeclaration raise {
  let fields = (
    {
      "id": { "type": "string", "nullable": false },
      "choices": {
        "type": "array",
        "nullable": false,
        "items": { "type": "string", "nullable": false },
      },
      "amount": {
        "type": "decimal",
        "nullable": true,
        "precision": 18,
        "scale": 3,
      },
      "label": { "type": "string", "nullable": true },
    } : Json)
  let wire = canonical_text(fields, delete_mapping_limits())
  generate_relation_row_declaration(
    "typed-write",
    "fixture",
    "fixture/0.1",
    [
      {
        resource: "records",
        resource_kind: "record",
        schema_wire: wire,
        schema_cid: canonical_cid(fields, delete_mapping_limits()),
        request_schema_wire: None,
        facts_wire: None,
        acquisition_wire: None,
      },
    ],
    delete_mapping_limits(),
  ).unwrap()
}

///|
fn relation_mapping_spec(kind : RowRelationWriteKind) -> RowRelationWriteSpec {
  {
    kind,
    writable_fields: ["choices", "amount", "label"],
    required_fields: if kind == RelationCreate {
      ["choices"]
    } else {
      []
    },
    permission: if kind == RelationCreate {
      "fixture:create"
    } else {
      "fixture:update"
    },
    approval: "required",
  }
}

///|
fn relation_mapping_sources() -> Array[RowMappingSource] {
  [
    { target: "choices", field: "originalChoices", null_behavior: "reject", },
    { target: "amount", field: "originalAmount", null_behavior: "write_null", },
  ]
}

///|
fn relation_mapping_environment(
  original : RowDeclaration,
  mapping : RowMapping,
) -> @environment.WireEnvironment raise {
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
  guard base is Object(fields) else { abort("test environment object") }
  let cid = canonical_cid(base, delete_mapping_limits())
  let entries = []
  for name, value in fields {
    entries.push((name, value))
  }
  entries.push(("evidence_bundle_cid", cid.to_json()))
  let wire = canonical_text(object(entries), delete_mapping_limits())
  @environment.read(@utf8.encode(wire), cid, {
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 32,
    max_members: 100,
  }).unwrap()
}

///|
test "Relation write Mapping preserves full Array Decimal and original target fields" {
  let original = relation_mapping_declaration()
  for kind in [RelationCreate, RelationUpdate] {
    let mapping = prepare_relation_row_write_mapping(
      original,
      "records",
      "id",
      relation_mapping_spec(kind),
      relation_mapping_sources(),
      delete_mapping_limits(),
    ).unwrap()
    guard @json.parse(mapping.body) is Object(body) else {
      fail("MappingObjectRequired")
    }
    assert_eq(
      body.get("target_schema"),
      Some(
        (
          {
            "type": "object",
            "nullable": false,
            "additional_properties": false,
            "fields": {
              "id": { "type": "string", "nullable": false },
              "choices": {
                "type": "array",
                "nullable": false,
                "items": { "type": "string", "nullable": false },
              },
              "amount": {
                "type": "decimal",
                "nullable": true,
                "precision": 18,
                "scale": 3,
              },
              "label": { "type": "string", "nullable": true },
            },
          } : Json),
      ),
    )
    assert_eq(body.get("primary_identity"), Some("id".to_json()))
    assert_eq(
      body.get("connector_manifest_cid"),
      Some(original.manifest_entry_cid.to_json()),
    )
    assert_eq(mapping.write_fields, ["amount", "choices"])
    assert_eq(
      body.get("row_mapping"),
      Some(
        (
          {
            "choices": { "field": "originalChoices", "null_behavior": "reject" },
            "amount": {
              "field": "originalAmount",
              "null_behavior": "write_null",
            },
          } : Json),
      ),
    )
    let again = prepare_relation_row_write_mapping(
      original,
      "records",
      "id",
      relation_mapping_spec(kind),
      [relation_mapping_sources()[1], relation_mapping_sources()[0]],
      delete_mapping_limits(),
    ).unwrap()
    assert_eq(mapping.body, again.body)
  }
}

///|
test "actual Mapping shape permission and row-source Owners distinguish create update and delete" {
  let original = relation_mapping_declaration()
  for
    (kind, operation, selector, permission) in [
      (RelationCreate, "create", "none", "fixture:create"),
      (RelationUpdate, "update", "id", "fixture:update"),
    ] {
    let mapping = prepare_relation_row_write_mapping(
      original,
      "records",
      "id",
      relation_mapping_spec(kind),
      relation_mapping_sources(),
      delete_mapping_limits(),
    ).unwrap()
    let env = relation_mapping_environment(original, mapping)
    let shapes = @environment.check_mapping_contract_shapes(
      env,
      { max_bytes: 100000, max_nodes: 10000, max_depth: 32, max_members: 100, },
      10000,
    ).unwrap()
    let shape = @environment.mapping_shape_at(shapes, 0).unwrap()
    let selected = @environment.select_mapping_permissions(
      shape,
      operation,
      selector,
      ["choices", "amount"],
      1000,
    ).unwrap()
    assert_eq(@environment.mapping_permission_names(selected), [permission])
    let fields = @environment.check_mapping_row_fields(shape, 1000).unwrap()
    assert_eq(@environment.mapping_row_fields_count(fields), 2)
    assert_true(
      @environment.select_mapping_permissions(
        shape,
        "delete",
        "id",
        ["choices", "amount"],
        1000,
      )
      is Err(_),
    )
    assert_true(
      @environment.select_mapping_permissions(
        shape,
        operation,
        selector,
        ["choices"],
        1000,
      )
      is Err(_),
    )
  }
}

///|
test "Relation Mapping checks original nullable required and omission facts" {
  let original = relation_mapping_declaration()
  let create = relation_mapping_spec(RelationCreate)
  assert_true(
    prepare_relation_row_write_mapping(
      original,
      "records",
      "id",
      create,
      [{ target: "amount", field: "amount", null_behavior: "write_null", }],
      delete_mapping_limits(),
    )
    is Err(MissingRequiredField("choices")),
  )
  for behavior in ["write_null", "omit", "default"] {
    assert_true(
      prepare_relation_row_write_mapping(
        original,
        "records",
        "id",
        create,
        [{ target: "choices", field: "choices", null_behavior: behavior, }],
        delete_mapping_limits(),
      )
      is Err(InvalidNullBehavior("choices")),
    )
  }
  let omitted = prepare_relation_row_write_mapping(
    original,
    "records",
    "id",
    create,
    [
      { target: "choices", field: "choices", null_behavior: "reject", },
      { target: "label", field: "label", null_behavior: "omit", },
    ],
    delete_mapping_limits(),
  ).unwrap()
  assert_eq(omitted.omittable, ["label"])
  assert_true(
    prepare_relation_row_write_mapping(
      original,
      "records",
      "id",
      { ..relation_mapping_spec(RelationUpdate), required_fields: ["choices"], },
      relation_mapping_sources(),
      delete_mapping_limits(),
    )
    is Err(InvalidSpecification),
  )
}

///|
test "Relation Mapping rejects foreign fields duplicate sources and identity writes" {
  let original = relation_mapping_declaration()
  let spec = relation_mapping_spec(RelationCreate)
  assert_true(
    prepare_relation_row_write_mapping(
      original,
      "other",
      "id",
      spec,
      relation_mapping_sources(),
      delete_mapping_limits(),
    )
    is Err(NotWritable("other")),
  )
  for field in ["id", "unknown"] {
    assert_true(
      prepare_relation_row_write_mapping(
        original,
        "records",
        "id",
        spec,
        [{ target: field, field: "value", null_behavior: "reject", }],
        delete_mapping_limits(),
      )
      is Err(FieldNotWritable(_)),
    )
  }
  assert_true(
    prepare_relation_row_write_mapping(
      original,
      "records",
      "id",
      { ..spec, writable_fields: ["id", "choices"], },
      relation_mapping_sources(),
      delete_mapping_limits(),
    )
    is Err(InvalidSpecification),
  )
  assert_true(
    prepare_relation_row_write_mapping(
      original,
      "records",
      "id",
      spec,
      [relation_mapping_sources()[0], relation_mapping_sources()[0]],
      delete_mapping_limits(),
    )
    is Err(DuplicateField("choices")),
  )
  assert_true(
    prepare_relation_row_write_mapping(
      original,
      "records",
      "id",
      spec,
      [{ target: "choices", field: "", null_behavior: "reject", }],
      delete_mapping_limits(),
    )
    is Err(InvalidNullBehavior("choices")),
  )
}

///|
test "Relation Mapping refuses mutated original View and carrier without resealing" {
  for change_view in [true, false] {
    let original = relation_mapping_declaration()
    if change_view {
      original.view_bodies[0] = original.view_bodies[0].replace(
        old="record",
        new="foreign",
      )
    } else {
      let index = original.contracts
        .search_by(wire => wire.contains("\"kind\":\"carrier_schema\""))
        .unwrap()
      original.contracts[index] = original.contracts[index].replace(
        old="\"scale\":3",
        new="\"scale\":2",
      )
    }
    assert_true(
      prepare_relation_row_write_mapping(
        original,
        "records",
        "id",
        relation_mapping_spec(RelationCreate),
        relation_mapping_sources(),
        delete_mapping_limits(),
      )
      is Err(InvalidSpecification),
    )
  }
}

///|
test "Relation Mapping caller ceilings refuse no partial Mapping and keep original reusable" {
  let original = relation_mapping_declaration()
  for
    limits in [
      { ..delete_mapping_limits(), max_bytes: 1, },
      { ..delete_mapping_limits(), max_nodes: 1, },
      { ..delete_mapping_limits(), max_depth: 1, },
      { ..delete_mapping_limits(), max_fields: 1, },
    ] {
    assert_true(
      prepare_relation_row_write_mapping(
        original,
        "records",
        "id",
        relation_mapping_spec(RelationCreate),
        relation_mapping_sources(),
        limits,
      )
      is Err(_),
    )
  }
  assert_true(
    prepare_relation_row_write_mapping(
      original,
      "records",
      "id",
      relation_mapping_spec(RelationCreate),
      [],
      delete_mapping_limits(),
    )
    is Err(EmptyWrite),
  )
  assert_true(
    prepare_relation_row_write_mapping(
      original,
      "records",
      "id",
      relation_mapping_spec(RelationCreate),
      relation_mapping_sources(),
      delete_mapping_limits(),
    )
    is Ok(_),
  )
}
