///|
fn tuple_mapping_test_original(
  identity : String,
  selector? : String = "match_tuple",
  writable? : String = "label",
  version? : String = "actql.mapping_contract/0.2",
  policy_source? : String = "connector://example/record#records",
) -> (WireEnvironment, CarrierSchemas) raise {
  let connector =
    #|{"connector":"example","connector_id":"example","connector_version":"external-7"}
  let schema =
    #|{"additional_properties":false,"fields":{"label":{"nullable":true,"type":"string"},"serial":{"nullable":false,"type":"int64"},"site":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"}
  let manifest = "{\"connectors\":[" +
    connector +
    "],\"version\":\"actql-connectors/0.1\"}"
  let connector_cid = "sha256:" + @sha.hex(@utf8.encode(connector))
  let schema_cid = "sha256:" + @sha.hex(@utf8.encode(schema))
  let mapping = sealed_fixture(
    @json.parse(
      "{\"connector_manifest_cid\":\"" +
      connector_cid +
      "\",\"conversions\":[],\"mapping_ref\":\"mapping:example.record.v1\",\"minimum_approval\":\"required\",\"permission_rules\":[{\"effect_kind\":\"update\",\"selector_class\":\"" +
      selector +
      "\",\"write_fields\":[\"" +
      writable +
      "\"],\"permissions\":[\"scope:update\"]}],\"primary_identity\":" +
      identity +
      ",\"required_fields\":[],\"required_permissions\":[],\"resource_identity_cid\":\"sha256:" +
      "b".repeat(64) +
      "\",\"row_mapping\":{},\"schema\":\"" +
      version +
      "\",\"target_ref\":\"connector://example/record\",\"target_schema\":" +
      schema +
      ",\"target_schema_identity\":\"" +
      schema_cid +
      "\",\"version\":\"external-7\",\"writable_fields\":[\"" +
      writable +
      "\"]}",
    ),
    "mapping_contract_cid",
  )
  let bodies = value_bodies("{\"type\":\"number\",\"nullable\":false}")
  bodies["carrier_schema"] = @json.parse(schema)
  let facts =
    #|{"relation_keys":{"candidate_keys":[["site","serial"]]}}
  bodies["carrier_facts"] = @json.parse(facts)
  let contents = reference_fixture(
    complete_view=true,
    path=["view", "view_id"],
    replacement=Some(Json::string("records")),
    policy_body=Some(
      @json.parse(
        "{\"version\":\"actql-source-data-policy/0.1\",\"source_ref\":\"" +
        policy_source +
        "\",\"classification\":\"internal\"}",
      ),
    ),
    bodies~,
    mappings=[mapping],
    manifest=Some(manifest),
  )
  let references = check_catalog_references(contents, reference_caps()).unwrap()
  let policies = check_source_data_policies(references, policy_limits()).unwrap()
  let values = check_protocol_value_contracts(policies, protocol_value_limits()).unwrap()
  let shapes = check_source_view_shapes(values, {
    max_views: 10,
    max_work: 100000,
  }).unwrap()
  let modes = check_source_read_modes(shapes, 100000).unwrap()
  let environment = contract_registry_environment(catalog_registry(contents))
  (environment, check_carrier_schemas(modes, carrier_limits()).unwrap())
}

///|
test "tuple Mapping admits the same published ordered key and only its explicit permission" {
  let tuple =
    #|{"kind":"tuple","fields":["site","serial"]}
  let (environment, carriers) = tuple_mapping_test_original(tuple)
  let limits = mapping_shape_limits()
  let shapes = check_mapping_contract_shapes(
    environment,
    limits,
    100000,
    carriers=Some(carriers),
  ).unwrap()
  let shape = mapping_shape_at(shapes, 0).unwrap()
  assert_eq(mapping_shape_primary_identity(shape), None)
  assert_eq(mapping_shape_tuple_field_count(shape), 2)
  assert_eq(mapping_shape_tuple_field_at(shape, 0), Some("site"))
  assert_eq(mapping_shape_tuple_field_at(shape, 1), Some("serial"))
  assert_eq(mapping_shape_tuple_field_at(shape, 2), None)
  let selected = select_mapping_permissions(
    shape,
    "update",
    "match_tuple",
    ["label"],
    100,
  ).unwrap()
  assert_eq(mapping_permission_names(selected), ["scope:update"])
  for selector in ["id", "match", "where", "key_tuple"] {
    assert_true(
      select_mapping_permissions(shape, "update", selector, ["label"], 100)
      is Err(InvalidRequest),
    )
  }
  assert_true(
    select_mapping_permissions(shape, "update", "match_tuple", ["serial"], 100)
    is Err(InvalidRequest),
  )
  let work = mapping_shape_work(shapes)
  assert_true(
    check_mapping_contract_shapes(
      environment,
      limits,
      work - 1,
      carriers=Some(carriers),
    )
    is Err(WorkLimit),
  )
  let (_, foreign) = tuple_mapping_test_original(tuple)
  assert_true(
    check_mapping_contract_shapes(
      environment,
      limits,
      100000,
      carriers=Some(foreign),
    )
    is Err(InvalidMapping(0)),
  )
  assert_true(
    check_mapping_contract_shapes(environment, limits, 100000)
    is Err(InvalidMapping(0)),
  )
}

///|
test "tuple Mapping refuses reversed and duplicate columns, scalar rules, and the wrong Source" {
  let tuple =
    #|{"kind":"tuple","fields":["site","serial"]}
  let variants = [
    tuple_mapping_test_original(
      (
        #|{"kind":"tuple","fields":["serial","site"]}
      ),
    ),
    tuple_mapping_test_original(
      (
        #|{"kind":"tuple","fields":["site","site"]}
      ),
    ),
    tuple_mapping_test_original(tuple, selector="id"),
    tuple_mapping_test_original(tuple, writable="site"),
    tuple_mapping_test_original(tuple, version="actql.mapping_contract/0.1"),
    tuple_mapping_test_original(
      tuple,
      policy_source="connector://example/other#records",
    ),
  ]
  for (environment, carriers) in variants {
    assert_true(
      check_mapping_contract_shapes(
        environment,
        mapping_shape_limits(),
        100000,
        carriers=Some(carriers),
      )
      is Err(InvalidMapping(0)),
    )
  }
}
