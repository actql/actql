///|
fn command_target_catalog(
  kind : String,
  input_fields? : String = "{}",
) -> @environment.CatalogContents {
  let command_before = "{\"command_id\":\"command:crm.invoke.v1\",\"connector_id\":\"example\","
  let command_after = "\"input_contract\":{\"additional_properties\":false,\"fields\":" +
    input_fields +
    "},\"schema\":\"actql.command_contract/0.1\",\"target\":{\"cardinality\":\"single\",\"resource_kind\":\"" +
    kind +
    "\"},\"version\":\"external-1\"}"
  let command_cid = "sha256:" +
    @sha.hex(@utf8.encode(command_before + command_after))
  let command = command_before +
    "\"contract_cid\":\"" +
    command_cid +
    "\"," +
    command_after
  let catalog_core = "\"commands\":[" +
    command +
    "],\"connector_id\":\"example\",\"connector_version\":\"external-7\",\"contracts\":[],\"schema\":\"actql.connector_catalog/0.1\",\"source_views\":[]}"
  let catalog_cid = "sha256:" + @sha.hex(@utf8.encode("{" + catalog_core))
  let catalog = "{\"catalog_cid\":\"" + catalog_cid + "\"," + catalog_core
  let prefix = "{\"command_contracts\":[" +
    command +
    "],\"connector_capabilities\":[],\"connector_catalogs\":[" +
    catalog +
    "],\"contract_registry\":[],"
  let suffix = "\"host_policy_profile\":{},\"mapping_contracts\":[],\"model_task_contracts\":[],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  let environment_cid = "sha256:" + @sha.hex(@utf8.encode(prefix + suffix))
  let environment = @environment.read(
    @utf8.encode(
      prefix + "\"evidence_bundle_cid\":\"" + environment_cid + "\"," + suffix,
    ),
    environment_cid,
    { max_bytes: 20000, max_nodes: 1000, max_depth: 100, max_members: 100, },
  ).unwrap()
  let registry = @environment.check_contract_registry(environment, {
    max_bytes: 20000,
    max_nodes: 1000,
    max_depth: 100,
    max_members: 100,
  }).unwrap()
  @environment.check_catalog_contents(registry, {
    max_bytes: 20000,
    max_nodes: 1000,
    max_depth: 100,
    max_members: 100,
  }).unwrap()
}

///|
test "Command target kind binds checked Result to exact Catalog command" {
  let effects = "{\"command\":{\"command\":{\"target\":{\"field\":\"ref\"},\"contract\":\"command:crm.invoke.v1\",\"from\":{\"result\":\"r\"},\"input\":{}}}}"
  let (checked, headers) = effect_binding_inputs(
    effects,
    reference_nullable=Some(false),
  )
  let bindings = bind_effect_results(headers, checked, 4).unwrap()
  let catalogs = command_target_catalog("crm/account")
  let selected = bind_effect_command_targets(bindings, catalogs, 6).unwrap()
  assert_eq(effect_command_target_count(selected), 2)
  assert_eq(effect_command_targets_work(selected), 6)
  assert_true(
    physical_equal(effect_command_targets_effects(selected), bindings),
  )
  assert_true(
    physical_equal(effect_command_targets_catalogs(selected), catalogs),
  )
  let first = effect_command_target_at(selected, 0).unwrap()
  assert_true(
    physical_equal(
      effect_command_target_effect(first),
      effect_result_binding_at(bindings, 0).unwrap(),
    ),
  )
  assert_eq(
    @environment.command_target_resource_kind(
      effect_command_target_contract(first),
    ),
    "crm/account",
  )
  assert_true(effect_command_target_at(selected, -1) is None)
  assert_true(effect_command_target_at(selected, 2) is None)
  assert_eq(
    effect_command_target_issue_kind(
      bind_effect_command_targets(bindings, catalogs, 5).unwrap_err(),
    ),
    WorkLimit,
  )
}

///|
test "Command target kind mismatch and absent contract remain typed failures" {
  let effects = "{\"command\":{\"command\":{\"target\":{\"field\":\"ref\"},\"contract\":\"command:crm.invoke.v1\",\"from\":{\"result\":\"r\"},\"input\":{}}}}"
  let (checked, headers) = effect_binding_inputs(
    effects,
    reference_nullable=Some(false),
  )
  let bindings = bind_effect_results(headers, checked, 4).unwrap()
  let issue = bind_effect_command_targets(
    bindings,
    command_target_catalog("crm/contact"),
    6,
  ).unwrap_err()
  assert_eq(effect_command_target_issue_kind(issue), TargetKindMismatch)
  assert_eq(effect_command_target_issue_stage(issue), 0)
  assert_eq(effect_command_target_issue_effect(issue), "command")
  let other = effects.replace(
    old="command:crm.invoke.v1",
    new="command:crm.other.v1",
  )
  let (checked, headers) = effect_binding_inputs(
    other,
    reference_nullable=Some(false),
  )
  let bindings = bind_effect_results(headers, checked, 4).unwrap()
  assert_eq(
    effect_command_target_issue_kind(
      bind_effect_command_targets(
        bindings,
        command_target_catalog("crm/account"),
        6,
      ).unwrap_err(),
    ),
    Contract(@environment.MissingCommand("command:crm.other.v1")),
  )
}
