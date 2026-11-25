///|
fn relation_update_write_wire() -> String {
  "{\"writes\":[{\"resource\":\"records\",\"primary_identity\":\"id\",\"update\":{\"fields\":[\"choices\",\"amount\",\"label\"],\"permission\":\"fixture:update\",\"approval\":\"required\"}}]}"
}

///|
test "file CREATE mapping requires all storage fields and an admissible separate Text key" {
  let declaration = relation_mapping_declaration()
  let wire =
    #|{"writes":[{"resource":"records","primary_identity":"id","create":{"fields":["choices","amount","label"],"permission":"fixture:create","approval":"required"}}]}
  let sources = [
    { target: "choices", field: "choices", null_behavior: "reject", },
    { target: "amount", field: "amount", null_behavior: "write_null", },
    { target: "label", field: "label", null_behavior: "write_null", },
  ]
  let mapping = prepare_row_file_create_mapping(
    declaration, wire, "records", sources,
  ).unwrap()
  let spec = {
    ..relation_mapping_spec(RelationCreate),
    required_fields: ["amount", "choices", "label"],
  }
  let original = prepare_relation_row_write_mapping(
    declaration,
    "records",
    "id",
    spec,
    sources,
    { ..declaration_limits, max_fields: 1024, },
  ).unwrap()
  assert_eq(mapping.body, original.body)
  assert_eq(mapping.mapping_cid, original.mapping_cid)
  assert_eq(mapping.write_fields, ["amount", "choices", "label"])
  assert_eq(mapping.omittable, [])
  assert_true(
    mapping.body.contains(
      "\"required_fields\":[\"amount\",\"choices\",\"label\"]",
    ),
  )
  assert_true(mapping.body.contains("\"selector_class\":\"none\""))
  assert_true(
    prepare_row_update_mapping(declaration, wire, "records", sources)
    is Err(NotWritable("records")),
  )
  assert_true(
    prepare_row_file_create_mapping(declaration, wire, "records", [
      sources[0],
      sources[1],
    ])
    is Err(MissingRequiredField("label")),
  )
  let id = { target: "id", field: "id", null_behavior: "reject", }
  assert_true(
    prepare_row_file_create_mapping(
      declaration,
      wire,
      "records",
      [..sources, id],
    )
    is Err(FieldNotWritable("id")),
  )
  for
    invalid in [
      wire.replace(old="\"label\"", new="\"id\""),
      wire.replace(old=",\"label\"", new=""),
      wire.replace(old="\"required\"", new="\"none\""),
    ] {
    assert_true(
      prepare_row_file_create_mapping(declaration, invalid, "records", sources)
      is Err(InvalidSpecification),
    )
  }

  let short_key = relation_document_test_short_key_declaration()
  let short_wire = wire.replace(
    old="\"choices\",\"amount\",\"label\"",
    new="\"value\"",
  )
  assert_true(
    prepare_row_file_create_mapping(short_key, short_wire, "records", [
      { target: "value", field: "value", null_behavior: "write_null", },
    ])
    is Err(InvalidSpecification),
  )
}

///|
test "installed UPDATE mapping continuation reuses the original complete typed constructor" {
  let declaration = relation_mapping_declaration()
  let sources = relation_mapping_sources()
  let continued = prepare_row_update_mapping(
    declaration,
    relation_update_write_wire(),
    "records",
    sources,
  ).unwrap()
  let expected = prepare_relation_row_write_mapping(
    declaration,
    "records",
    "id",
    relation_mapping_spec(RelationUpdate),
    sources,
    { ..declaration_limits, max_fields: 1024, },
  ).unwrap()
  assert_eq(continued.body, expected.body)
  assert_eq(continued.mapping_ref, expected.mapping_ref)
  assert_eq(continued.mapping_cid, expected.mapping_cid)
  assert_eq(continued.write_fields, ["amount", "choices"])
  assert_true(continued.body.contains("\"effect_kind\":\"update\""))
  assert_true(continued.body.contains("\"selector_class\":\"id\""))
  assert_true(continued.body.contains("\"precision\":18"))
  assert_true(continued.body.contains("\"type\":\"array\""))
  assert_true(continued.body.contains("\"minimum_approval\":\"required\""))
}

///|
test "installed UPDATE continuation preserves typed null and omission rules" {
  let declaration = relation_mapping_declaration()
  let mapping = prepare_row_update_mapping(
    declaration,
    relation_update_write_wire(),
    "records",
    [
      { target: "amount", field: "newAmount", null_behavior: "write_null", },
      { target: "label", field: "newLabel", null_behavior: "omit", },
    ],
  ).unwrap()
  assert_eq(mapping.omittable, ["label"])
  for
    source in [
      { target: "choices", field: "newChoices", null_behavior: "write_null", },
      { target: "id", field: "newId", null_behavior: "reject", },
      { target: "label", field: "", null_behavior: "reject", },
    ] {
    assert_true(
      prepare_row_update_mapping(
        declaration,
        relation_update_write_wire(),
        "records",
        [source],
      )
      is Err(_),
    )
  }
  assert_true(
    prepare_row_update_mapping(
      declaration,
      relation_update_write_wire(),
      "records",
      [],
    )
    is Err(EmptyWrite),
  )
  assert_true(
    prepare_row_update_mapping(
      declaration,
      relation_update_write_wire(),
      "records",
      [
        { target: "label", field: "a", null_behavior: "reject", },
        { target: "label", field: "b", null_behavior: "reject", },
      ],
    )
    is Err(DuplicateField("label")),
  )
}

///|
test "installed UPDATE continuation refuses open duplicate foreign or malformed write facts" {
  let declaration = relation_mapping_declaration()
  let wire = relation_update_write_wire()
  for
    invalid in [
      "{}",
      "{\"writes\":[]}",
      wire.replace(old="{\"writes\":", new="{\"extra\":true,\"writes\":"),
      wire.replace(
        old="\"primary_identity\":\"id\"",
        new="\"primary_identity\":\"id\",\"fields\":[]",
      ),
      wire.replace(
        old="\"primary_identity\":\"id\"",
        new="\"primary_identity\":null",
      ),
      wire.replace(
        old="\"fields\":[\"choices\",\"amount\",\"label\"]",
        new="\"fields\":[\"choices\",\"choices\"]",
      ),
      wire.replace(
        old="\"fields\":[\"choices\",\"amount\",\"label\"]",
        new="\"fields\":[\"id\"]",
      ),
      wire.replace(
        old="\"permission\":\"fixture:update\"",
        new="\"permission\":\"\"",
      ),
      wire.replace(
        old="\"approval\":\"required\"",
        new="\"approval\":\"sometimes\"",
      ),
      wire.replace(
        old="\"approval\":\"required\"",
        new="\"approval\":\"required\",\"required\":[]",
      ),
      wire.replace(
        old="\"resource\":\"records\"",
        new="\"resource\":\"records\",\"resource\":\"records\"",
      ),
      wire.replace(
        old="\"primary_identity\":\"id\"",
        new="\"primary_identity\":\"missing\"",
      ),
    ] {
    assert_true(
      prepare_row_update_mapping(
        declaration,
        invalid,
        "records",
        relation_mapping_sources(),
      )
      is Err(_),
    )
  }
  assert_true(
    prepare_row_update_mapping(
      declaration,
      wire,
      "other",
      relation_mapping_sources(),
    )
    is Err(NotWritable("other")),
  )
}

///|
test "installed UPDATE validates every sibling specification before selecting a mapping" {
  let declaration = relation_mapping_declaration()
  let first = relation_update_write_wire()
  let duplicate = first.replace(
    old="]}",
    new=",{\"resource\":\"records\",\"primary_identity\":\"id\",\"update\":{\"fields\":[\"label\"],\"permission\":\"fixture:update\",\"approval\":\"required\"}}]}",
  )
  let foreign = first.replace(
    old="]}",
    new=",{\"resource\":\"foreign\",\"primary_identity\":\"id\",\"update\":{\"fields\":[\"label\"],\"permission\":\"fixture:update\",\"approval\":\"required\"}}]}",
  )
  assert_true(
    prepare_row_update_mapping(
      declaration,
      duplicate,
      "records",
      relation_mapping_sources(),
    )
    is Err(InvalidSpecification),
  )
  assert_true(
    prepare_row_update_mapping(
      declaration,
      foreign,
      "records",
      relation_mapping_sources(),
    )
    is Err(NotWritable("foreign")),
  )
}

///|
test "one guarded Relation issues distinct CREATE UPDATE and DELETE mappings" {
  let declaration = relation_mapping_declaration()
  let writes =
    #|{"writes":[{"resource":"records","primary_identity":"id","create":{"fields":["choices","amount","label"],"permission":"fixture:create","approval":"required"},"update":{"fields":["choices","amount","label"],"permission":"fixture:update","approval":"required"},"delete":{"permission":"fixture:delete","approval":"required"}}]}
  let create_sources = [
    { target: "choices", field: "choices", null_behavior: "reject", },
    { target: "amount", field: "amount", null_behavior: "write_null", },
    { target: "label", field: "label", null_behavior: "write_null", },
  ]
  let created = prepare_row_file_create_mapping(
    declaration, writes, "records", create_sources,
  ).unwrap()
  let updated = prepare_row_update_mapping(
    declaration,
    writes,
    "records",
    relation_mapping_sources(),
  ).unwrap()
  let deleted = prepare_row_delete_mapping_from_writes(
    declaration, writes, "records",
  ).unwrap()
  assert_eq(
    updated.body,
    prepare_row_update_mapping(
      declaration,
      relation_update_write_wire(),
      "records",
      relation_mapping_sources(),
    ).unwrap().body,
  )
  assert_eq(created.resource, updated.resource)
  assert_eq(updated.resource, deleted.resource)
  assert_true(created.mapping_cid != updated.mapping_cid)
  assert_true(created.mapping_cid != deleted.mapping_cid)
  assert_true(created.body.contains("\"fixture:create\""))
  assert_true(!created.body.contains("\"fixture:update\""))
  assert_true(!created.body.contains("\"fixture:delete\""))
  assert_true(updated.mapping_cid != deleted.mapping_cid)
  assert_true(deleted.body.contains("\"effect_kind\":\"delete\""))
  assert_true(deleted.body.contains("\"fixture:delete\""))
  assert_true(!deleted.body.contains("\"fixture:update\""))
  let bad = writes.replace(old="\"fixture:delete\"", new="\"\"")
  assert_true(
    prepare_row_update_mapping(
      declaration,
      bad,
      "records",
      relation_mapping_sources(),
    )
    is Err(InvalidSpecification),
  )
  let bad_create = writes.replace(old="\"fixture:create\"", new="\"\"")
  assert_true(
    prepare_row_delete_mapping_from_writes(declaration, bad_create, "records")
    is Err(InvalidSpecification),
  )
  assert_true(
    prepare_row_delete_mapping_from_writes(
      declaration,
      relation_update_write_wire(),
      "records",
    )
    is Err(NotWritable("records")),
  )
}

///|
test "existing CREATE mapping remains separate and unchanged by UPDATE continuation" {
  let declaration = github_declaration()
  let mapping = prepare_row_mapping(
    declaration,
    writes_json,
    "issue_comments",
    sources(),
  ).unwrap()
  assert_true(mapping.body.contains("\"effect_kind\":\"create\""))
  assert_true(mapping.body.contains("\"selector_class\":\"none\""))
  assert_true(
    prepare_row_update_mapping(
      declaration,
      writes_json,
      "issue_comments",
      sources(),
    )
    is Err(_),
  )
  assert_true(
    prepare_row_mapping(
      relation_mapping_declaration(),
      relation_update_write_wire(),
      "records",
      relation_mapping_sources(),
    )
    is Err(_),
  )
}

///|
fn checked_ordered_file_mapping(
  original : RowDeclaration,
  mapping : RowMapping,
) -> @environment.MappingContractShape raise {
  let env = relation_mapping_environment(original, mapping)
  let limits : @environment.Limits = {
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 32,
    max_members: 100,
  }
  let registry = @environment.check_contract_registry(env, limits).unwrap()
  let catalogue = @environment.check_catalog_contents(registry, limits).unwrap()
  let references = @environment.check_catalog_references(catalogue, {
    max_work: 100000,
    max_references: 100,
  }).unwrap()
  let policies = @environment.check_source_data_policies(references, {
    max_work: 100000,
    max_policies: 10,
  }).unwrap()
  let contracts = @environment.check_protocol_value_contracts(policies, {
    max_envelopes: 100,
    contracts: { max_nodes: 10000, max_depth: 32, max_text_bytes: 100000, },
  }).unwrap()
  let views = @environment.check_source_view_shapes(contracts, {
    max_views: 100,
    max_work: 100000,
  }).unwrap()
  let modes = @environment.check_source_read_modes(views, 100000).unwrap()
  let carriers = @environment.check_carrier_schemas(modes, {
    max_schemas: 100,
    max_work: 100000,
    bodies: { max_nodes: 10000, max_bytes: 100000, max_depth: 32, },
  }).unwrap()
  let mappings = @environment.check_mapping_contract_shapes(
    env,
    limits,
    100000,
    carriers=Some(carriers),
  ).unwrap()
  @environment.mapping_shape_at(mappings, 0).unwrap()
}

///|
test "declared File Mapping admits only its ordered typed key and selected operation" {
  let original = ordered_file_target_fixture()
  let tuple = "{\"kind\":\"tuple\",\"fields\":[\"site\",\"serial\"]}"
  let wire =
    #|{"writes":[{"resource":"records","primary_identity":@key,"@operation":{"fields":["label"],"permission":"fixture:write","approval":"required"}}]}
  let wire = wire.replace(old="@key", new=tuple)
  let sources = [
    { target: "label", field: "incoming", null_behavior: "write_null", },
  ]
  let update_wire = wire.replace(old="@operation", new="update")
  let update = prepare_row_update_mapping(
    original, update_wire, "records", sources,
  ).unwrap()
  let delete = prepare_row_delete_mapping_from_writes(
    original,
    wire
    .replace(old="@operation", new="delete")
    .replace(old="\"fields\":[\"label\"],", new=""),
    "records",
  ).unwrap()
  let upsert_wire = wire.replace(old="@operation", new="upsert")
  let upsert = prepare_row_file_upsert_mapping(
    original, upsert_wire, "records", sources,
  ).unwrap()

  assert_true(
    update.mapping_cid != delete.mapping_cid &&
    update.mapping_cid != upsert.mapping_cid &&
    delete.mapping_cid != upsert.mapping_cid,
  )
  for
    (mapping, operation, selector, written) in [
      (update, "update", "match_tuple", ["label"]),
      (delete, "delete", "match_tuple", []),
      (upsert, "upsert", "key_tuple", ["label"]),
    ] {
    assert_eq(mapping.write_fields, written)
    let shape = checked_ordered_file_mapping(original, mapping)
    assert_eq(@environment.mapping_shape_primary_identity(shape), None)
    assert_eq(@environment.mapping_shape_tuple_field_count(shape), 2)
    assert_eq(@environment.mapping_shape_tuple_field_at(shape, 0), Some("site"))
    assert_eq(
      @environment.mapping_shape_tuple_field_at(shape, 1),
      Some("serial"),
    )
    let permissions = @environment.select_mapping_permissions(
      shape, operation, selector, written, 1000,
    ).unwrap()
    assert_eq(@environment.mapping_permission_names(permissions), [
      "fixture:write",
    ])
    assert_true(
      @environment.select_mapping_permissions(
        shape, operation, "id", written, 1000,
      )
      is Err(_),
    )
    guard @json.parse(mapping.body) is Object(body) else {
      fail("closed Mapping body")
    }
    // SHA256 of the independent canonical tuple identity preimage with the
    // original typed records schema. Operation never changes the row scheme.
    assert_eq(
      body.get("resource_identity_cid"),
      Some(
        Json::string(
          "sha256:77e17d6ab3407abb3238e51082a0e55da816e8cf0b170ac7d178b3ba4e5b95d5",
        ),
      ),
    )
  }
  assert_true(upsert.body.contains("\"required_fields\":[\"label\"]"))
  assert_true(
    prepare_row_file_upsert_mapping(original, upsert_wire, "records", [
      { ..sources[0], null_behavior: "omit", },
    ])
    is Err(InvalidNullBehavior("label")),
  )
  for
    malformed in [
      update_wire.replace(old="\"site\",\"serial\"", new="\"serial\",\"site\""),
      update_wire.replace(old="\"site\",\"serial\"", new="\"site\",\"site\""),
      update_wire.replace(old="\"site\",\"serial\"", new="\"site\""),
      update_wire.replace(old="\"site\",\"serial\"", new="\"site\",\"label\""),
      update_wire.replace(
        old="\"fields\":[\"label\"]",
        new="\"fields\":[\"serial\"]",
      ),
    ] {
    assert_true(
      prepare_row_update_mapping(original, malformed, "records", sources)
      is Err(_),
    )
  }
  assert_true(
    prepare_row_file_create_mapping(
      original,
      wire.replace(old="@operation", new="create"),
      "records",
      sources,
    )
    is Err(InvalidSpecification),
  )
  assert_true(
    prepare_row_file_upsert_mapping(
      original,
      upsert_wire.replace(old=tuple, new="\"site\""),
      "records",
      sources,
    )
    is Err(InvalidSpecification),
  )
}

///|
test "one ordered File resource selects separate mappings for UPDATE DELETE and UPSERT" {
  let original = ordered_file_target_fixture()
  let wire =
    #|{"writes":[{"resource":"records","primary_identity":{"kind":"tuple","fields":["site","serial"]},"update":{"fields":["label"],"permission":"fixture:update","approval":"required"},"delete":{"permission":"fixture:delete","approval":"required"},"upsert":{"fields":["label"],"permission":"fixture:upsert","approval":"required"}}]}
  let sources = [
    { target: "label", field: "incoming", null_behavior: "write_null", },
  ]
  let update = prepare_row_update_mapping(original, wire, "records", sources).unwrap()
  let delete = prepare_row_delete_mapping_from_writes(original, wire, "records").unwrap()
  let upsert = prepare_row_file_upsert_mapping(
    original, wire, "records", sources,
  ).unwrap()
  assert_true(
    update.mapping_cid != delete.mapping_cid &&
    update.mapping_cid != upsert.mapping_cid &&
    delete.mapping_cid != upsert.mapping_cid,
  )
  for
    (mapping, kind, selector, writes) in [
      (update, "update", "match_tuple", ["label"]),
      (delete, "delete", "match_tuple", []),
      (upsert, "upsert", "key_tuple", ["label"]),
    ] {
    let shape = checked_ordered_file_mapping(original, mapping)
    let permission = @environment.select_mapping_permissions(
      shape, kind, selector, writes, 1000,
    ).unwrap()
    assert_eq(@environment.mapping_permission_names(permission), [
      "fixture:" + kind,
    ])
    assert_eq(@environment.mapping_shape_tuple_field_at(shape, 0), Some("site"))
    assert_eq(
      @environment.mapping_shape_tuple_field_at(shape, 1),
      Some("serial"),
    )
  }
  let invalid = wire.replace(
    old="\"upsert\":{\"fields\":[\"label\"]",
    new="\"upsert\":{\"fields\":[\"serial\"]",
  )
  assert_true(
    prepare_row_update_mapping(original, invalid, "records", sources)
    is Err(InvalidSpecification),
  )
}
