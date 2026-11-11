///|
// Independent canonical JSON/hash fixture. No Account, grant or provider IO.
let source_bridge_effect_environment_wire : String =
  #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:9faf09f5a3177d36dc7c9fab868f6fe4437e4597dd12bcdc051166ec2e6ad8fd","commands":[],"connector_id":"crm","connector_version":"fixture","contracts":[],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"crm","connector_id":"crm","connector_version":"fixture"}],"version":"actql-connectors/0.1"},"contract_registry":[],"evidence_bundle_cid":"sha256:de7cfc6d9aa91109ea99c14a77c22fbe49c94e49d6ff0d2fefd49a9904831288","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[{"connector_manifest_cid":"sha256:b1b75d3b468de053f98c678ec9eedfb2f1fe7b6fcb76562b0f392121378ec7c1","conversions":[],"mapping_contract_cid":"sha256:c99f6697a8b40c16a418a156177be2a6144be3ba5ebbc36020c819789d021cd4","mapping_ref":"mapping:crm.account.v1","minimum_approval":"required","permission_rules":[{"effect_kind":"update","permissions":["scope:update"],"selector_class":"id","write_fields":["Name"]},{"effect_kind":"update","permissions":["scope:update"],"selector_class":"ids","write_fields":["Name"]}],"primary_identity":"Id","required_fields":[],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"Name":{"field":"value","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","target_ref":"connector://crm/account","target_schema":{"additional_properties":false,"fields":{"Id":{"nullable":false,"type":"string"},"Name":{"nullable":true,"type":"number"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:1208f407bf69f466944f865797ce7407361d822605d1fbbb502177af4b63958f","version":"salesforce-v1","writable_fields":["Name"]}],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}

///|
fn source_bridge_effect_environment() -> @checked.CheckEnvironment {
  @host.admit_client_check_environment(
    source_bridge_effect_environment_wire,
    "sha256:de7cfc6d9aa91109ea99c14a77c22fbe49c94e49d6ff0d2fefd49a9904831288",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
}

///|
fn source_bridge_effect_publication(env : @checked.CheckEnvironment) -> String {
  "{\"environmentCid\":\"" +
  @checked.checking_environment_cid(env) +
  "\",\"aliases\":[],\"updateTargets\":[{\"name\":\"salesforce.Account\",\"targetRef\":\"connector://crm/account\",\"installationBindingCid\":\"sha256:" +
  "d".repeat(64) +
  "\",\"installationOwnerCid\":\"sha256:" +
  "e".repeat(64) +
  "\"}]}"
}

///|
test "source submitted bridge keeps same pure original and refuses equal foreign originals" {
  let env = environment()
  let intent = source_computation_intent("SELECT 1 AS n")
  let source = prepare_local_source_computation(
    intent,
    env,
    source_computation_publication(env),
  ).unwrap()
  let submitted = local_source_pure_submitted_preparation(source, intent, env).unwrap()
  guard local_source_computation_preparation(source) is Pure(prepared) else {
    fail("Pure")
  }
  assert_true(
    physical_equal(local_submitted_preparation_intent(submitted), intent),
  )
  assert_true(
    physical_equal(
      local_prepared_program(local_submitted_preparation_input(submitted)),
      prepared,
    ),
  )
  assert_true(
    local_prepared_original(local_submitted_preparation_input(submitted))
    is Aql("SELECT 1 AS n"),
  )
  assert_eq(
    local_prepared_document(local_submitted_preparation_input(submitted)),
    local_source_computation_material(source).0,
  )
  assert_true(
    local_source_pure_submitted_preparation(
      source,
      source_computation_intent("SELECT 1 AS n"),
      env,
    )
    is None,
  )
  assert_true(
    local_source_pure_submitted_preparation(source, intent, environment())
    is None,
  )
}

///|
test "source submitted bridge does not promote Effect computation into Pure preparation" {
  let env = source_bridge_effect_environment()
  let text = "SELECT 'original-id' AS id, 1 AS value |> RESULT out |> EFFECT UPDATE salesforce.Account ID id SET (Name = value)"
  let intent = source_computation_intent(text, format="aql")
  let outcome = prepare_local_source_computation(
    intent,
    env,
    source_bridge_effect_publication(env),
  )
  guard outcome is Ok(source) else {
    fail(
      source_computation_failure(outcome) +
      ": " +
      client_program_check_source(
        text,
        "aql",
        env,
        source_bridge_effect_publication(env),
        None,
        None,
        "ctx:source-bridge",
        "rev:" + "a".repeat(64),
        None,
        None,
        "corr:source-bridge",
        "bound_input",
        None,
      ),
    )
  }
  assert_true(local_source_computation_preparation(source) is Effect(_))
  assert_true(
    local_source_pure_submitted_preparation(source, intent, env) is None,
  )
  assert_eq(local_source_computation_source(source).0, text)
  assert_eq(
    local_source_computation_originals(source).0,
    @host.client_submitted_intent_wire(intent),
  )
}
