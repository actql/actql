///|
fn effect_mapping_shape_fixture_with_body(
  rules : String,
  required_fields : String,
  row_source : String,
  target_type? : String = "number",
  target_nullable? : Bool = true,
  row_mapping? : String = "",
) -> @environment.MappingContractShapes {
  let before = "{\"connector_manifest_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"conversions\":[],"
  let target_schema = "{\"additional_properties\":false,\"fields\":{\"Id\":{\"nullable\":false,\"type\":\"string\"},\"Name\":{\"nullable\":" +
    target_nullable.to_string() +
    ",\"type\":\"" +
    target_type +
    "\"}},\"nullable\":false,\"type\":\"object\"}"
  let target_schema_cid = "sha256:" + @sha.hex(@utf8.encode(target_schema))
  let row = if row_mapping.is_empty() {
    "{\"Name\":{\"field\":\"" + row_source + "\",\"null_behavior\":\"reject\"}}"
  } else {
    row_mapping
  }
  let after = "\"mapping_ref\":\"mapping:crm.account.v1\",\"minimum_approval\":\"none\",\"permission_rules\":" +
    rules +
    "," +
    "\"primary_identity\":\"Id\",\"required_fields\":" +
    required_fields +
    ",\"required_permissions\":[],\"resource_identity_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"," +
    "\"row_mapping\":" +
    row +
    ",\"schema\":\"actql.mapping_contract/0.1\",\"target_ref\":\"connector://crm/account\"," +
    "\"target_schema\":" +
    target_schema +
    ",\"target_schema_identity\":\"" +
    target_schema_cid +
    "\",\"version\":\"salesforce-v1\",\"writable_fields\":[\"Name\"]}"
  let cid = "sha256:" + @sha.hex(@utf8.encode(before + after))
  let body = before + "\"mapping_contract_cid\":\"" + cid + "\"," + after
  let prefix = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],"
  let suffix = "\"host_policy_profile\":{},\"mapping_contracts\":[" +
    body +
    "],\"model_task_contracts\":[],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  let environment_cid = "sha256:" + @sha.hex(@utf8.encode(prefix + suffix))
  let environment = @environment.read(
    @utf8.encode(
      prefix + "\"evidence_bundle_cid\":\"" + environment_cid + "\"," + suffix,
    ),
    environment_cid,
    { max_bytes: 20000, max_nodes: 2000, max_depth: 100, max_members: 100, },
  ).unwrap()
  @environment.check_mapping_contract_shapes(
    environment,
    { max_bytes: 20000, max_nodes: 2000, max_depth: 100, max_members: 100, },
    100,
  ).unwrap()
}

///|
fn effect_mapping_shape_fixture_with_rules(
  rules : String,
) -> @environment.MappingContractShapes {
  effect_mapping_shape_fixture_with_body(rules, "[]", "amount")
}

///|
fn effect_mapping_shape_fixture() -> @environment.MappingContractShapes {
  effect_mapping_shape_fixture_with_rules(
    "[{\"effect_kind\":\"create\",\"permissions\":[\"scope:create\"],\"selector_class\":\"none\",\"write_fields\":[\"Name\"]}]",
  )
}

///|
test "checked Effect header binds exact Mapping reference and target" {
  let effects = "{\"create\":{\"create\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"from\":{\"result\":\"r\"}}}}"
  let (checked, headers) = effect_binding_inputs(effects)
  let bindings = bind_effect_results(headers, checked, 4).unwrap()
  let mappings = effect_mapping_shape_fixture()
  let selected = bind_effect_mapping_shapes(bindings, mappings, 2).unwrap()
  assert_eq(effect_mapping_shape_count(selected), 2)
  assert_eq(effect_mapping_shapes_work(selected), 2)
  assert_true(physical_equal(effect_mapping_shapes_effects(selected), bindings))
  assert_true(
    physical_equal(effect_mapping_shapes_environment(selected), mappings),
  )
  let first = effect_mapping_shape_at(selected, 0).unwrap()
  assert_true(
    physical_equal(
      effect_mapping_shape_effect(first),
      effect_result_binding_at(bindings, 0).unwrap(),
    ),
  )
  assert_eq(
    @environment.mapping_shape_reference(effect_mapping_shape_contract(first)),
    "mapping:crm.account.v1",
  )
  assert_true(effect_mapping_shape_at(selected, 2) is None)
  assert_eq(
    effect_mapping_shape_issue_kind(
      bind_effect_mapping_shapes(bindings, mappings, 1).unwrap_err(),
    ),
    WorkLimit,
  )
}

///|
test "foreign Mapping reference and target fail before Preview" {
  let mappings = effect_mapping_shape_fixture()
  let cases : Array[(String, String, EffectMappingShapeIssueKind)] = [
    ("mapping:crm.other.v1", "connector://crm/account", MissingMapping),
    ("mapping:crm.account.v1", "connector://crm/contact", TargetMismatch),
  ]
  for (mapping, target, expected) in cases {
    let effects = "{\"create\":{\"create\":{\"target\":\"" +
      target +
      "\",\"mapping\":\"" +
      mapping +
      "\",\"from\":{\"result\":\"r\"}}}}"
    let (checked, headers) = effect_binding_inputs(effects)
    let bindings = bind_effect_results(headers, checked, 4).unwrap()
    let issue = bind_effect_mapping_shapes(bindings, mappings, 2).unwrap_err()
    assert_eq(effect_mapping_shape_issue_kind(issue), expected)
    assert_eq(effect_mapping_shape_issue_stage(issue), 0)
    assert_eq(effect_mapping_shape_issue_effect(issue), "create")
  }
}

///|
test "Command Effect does not require a Mapping body" {
  let effects = "{\"command\":{\"command\":{\"target\":{\"field\":\"ref\"},\"contract\":\"command:crm.invoke.v1\",\"from\":{\"result\":\"r\"},\"input\":{}}}}"
  let (checked, headers) = effect_binding_inputs(
    effects,
    reference_nullable=Some(false),
  )
  let bindings = bind_effect_results(headers, checked, 4).unwrap()
  let selected = bind_effect_mapping_shapes(
    bindings,
    effect_mapping_shape_fixture(),
    2,
  ).unwrap()
  assert_eq(effect_mapping_shape_count(selected), 0)
  assert_eq(effect_mapping_shapes_work(selected), 2)
}
