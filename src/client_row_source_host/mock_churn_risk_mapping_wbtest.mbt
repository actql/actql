///|
fn mock_update_limits() -> RowDeclarationLimits {
  {
    max_bytes: 65536,
    max_nodes: 8192,
    max_depth: 64,
    max_views: 4,
    max_fields: 16,
  }
}

///|
fn mock_update_schema() -> String {
  (
    #|{"Churn_Risk__c":{"nullable":false,"type":"string"},"Risk_Reason__c":{"nullable":true,"type":"string"},"description":{"nullable":false,"type":"string"},"id":{"nullable":false,"type":"string"},"name":{"nullable":false,"type":"string"}}
  )
}

///|
fn mock_update_declaration(
  connector? : String = "salesforce",
  registration? : String = "mock_salesforce",
  resource? : String = "Account",
  kind? : String = "record",
  schema? : String = mock_update_schema(),
  facts? : String = "{\"relation_keys\":{\"candidate_keys\":[[\"id\"]]}}",
) -> RowDeclaration {
  let schema_cid = if schema == mock_update_schema() {
    // Independent canonical field-map preimage, not a Mapping output.
    "sha256:2bb86ad0dae4e6ab1cde7bb339f74cd3959dc572f6ad54f6da5487765709307d"
  } else {
    canonical_cid(@json.parse(schema), mock_update_limits()) catch {
      _ => abort("mutation input digest")
    }
  }
  generate_relation_row_declaration(
    connector,
    registration,
    registration + "/0.1",
    [
      {
        resource,
        resource_kind: kind,
        schema_wire: schema,
        schema_cid,
        request_schema_wire: None,
        facts_wire: Some(facts),
        acquisition_wire: None,
      },
    ],
    mock_update_limits(),
  ).unwrap()
}

///|
test "mock UPDATE Mapping is generated from the same original Account declaration" {
  let original = mock_update_declaration()
  let mapping = prepare_churn_risk_mock_update_mapping(
    original,
    mock_update_limits(),
  ).unwrap()
  guard @json.parse(mapping.body) is Object(body) else {
    fail("mapping object")
  }
  assert_eq(
    body.get("target_ref"),
    Some("connector://salesforce/Account".to_json()),
  )
  assert_eq(
    body.get("connector_manifest_cid"),
    Some(original.manifest_entry_cid.to_json()),
  )
  assert_eq(body.get("primary_identity"), Some("id".to_json()))
  assert_eq(body.get("minimum_approval"), Some("required".to_json()))
  assert_eq(
    body.get("writable_fields"),
    Some(["Churn_Risk__c", "Risk_Reason__c"].to_json()),
  )
  assert_eq(body.get("required_fields"), Some(([] : Array[String]).to_json()))
  assert_eq(
    body.get("permission_rules"),
    Some(
      @json.parse(
        "[{\"effect_kind\":\"update\",\"permissions\":[\"salesforce:record:update\"],\"selector_class\":\"id\",\"write_fields\":[\"Churn_Risk__c\",\"Risk_Reason__c\"]}]",
      ),
    ),
  )
  assert_eq(
    body.get("row_mapping"),
    Some(
      @json.parse(
        "{\"Churn_Risk__c\":{\"field\":\"Churn_Risk__c\",\"null_behavior\":\"reject\"},\"Risk_Reason__c\":{\"field\":\"Risk_Reason__c\",\"null_behavior\":\"reject\"}}",
      ),
    ),
  )
  // Ordinary Mapping admission sees the exact schema and UPDATE/id family.
  let env = relation_mapping_environment(original, mapping)
  let shapes = @environment.check_mapping_contract_shapes(
    env,
    { max_bytes: 100000, max_nodes: 10000, max_depth: 32, max_members: 100, },
    100000,
  ).unwrap()
  assert_eq(@environment.mapping_shape_count(shapes), 1)
  assert_eq(
    @environment.mapping_shape_reference(
      @environment.mapping_shape_at(shapes, 0).unwrap(),
    ),
    mapping.mapping_ref,
  )
}

///|
test "mock UPDATE refuses foreign resource generation schema and original key facts" {
  for
    original in [
      mock_update_declaration(connector="other"),
      mock_update_declaration(registration="other"),
      mock_update_declaration(resource="Other"),
      mock_update_declaration(kind="table"),
      mock_update_declaration(facts="{}"),
      mock_update_declaration(
        facts="{\"relation_keys\":{\"candidate_keys\":[[\"name\"]]}}",
      ),
      mock_update_declaration(
        schema=mock_update_schema().replace(
          old="\"description\":{\"nullable\":false",
          new="\"description\":{\"nullable\":true",
        ),
      ),
    ] {
    assert_true(
      prepare_churn_risk_mock_update_mapping(original, mock_update_limits())
      is Err(_),
    )
  }
}

///|
test "mock UPDATE retains bounded original metadata and output refusals" {
  let original = mock_update_declaration()
  for
    limits in [
      { ..mock_update_limits(), max_bytes: 1, },
      { ..mock_update_limits(), max_nodes: 1, },
      { ..mock_update_limits(), max_fields: 1, },
      { ..mock_update_limits(), max_views: 0, },
    ] {
    assert_true(
      prepare_churn_risk_mock_update_mapping(original, limits) is Err(_),
    )
  }
}
