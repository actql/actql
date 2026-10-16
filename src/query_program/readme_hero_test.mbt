///|
// Static caller inputs only: these declarations never issue Source authority.
fn readme_hero_environment() -> @check.CheckEnvironment {
  let wire = @environment.read(
    @utf8.encode(
      (
        #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:189e570b7553c768f55852ec2f1a36e1386c4c4118ca62efc8578d028e40c648","commands":[],"connector_id":"salesforce","connector_version":"fixture","contracts":[],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"salesforce","connector_id":"salesforce","connector_version":"fixture"},{"connector":"snowflake","connector_id":"snowflake","connector_version":"fixture"}],"version":"actql-connectors/0.1"},"contract_registry":[],"evidence_bundle_cid":"sha256:1a448dee07aa59b5199ecf17709e891d7f061c2ff0ae9109a750d17d9ead89c6","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_analytic_frame_memberships":1000,"max_analytic_input_wire_bytes":1000,"max_analytic_output_wire_bytes":1000,"max_analytic_partition_wire_bytes":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[{"connector_manifest_cid":"sha256:e28fe9527c3be5c38b3b2d6c412f3169b398bf5c7044361b6f03bebd3daf59ec","conversions":[],"mapping_contract_cid":"sha256:084cd9221773adccf7378e9dae278c8e5d8b8db50ba1f70cd4fae64ddbdfcff7","mapping_ref":"mapping:salesforce.churn.v1","minimum_approval":"required","permission_rules":[{"effect_kind":"update","permissions":["scope:update"],"selector_class":"id","write_fields":["Churn_Risk__c","Risk_Reason__c"]}],"primary_identity":"Id","required_fields":[],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"Churn_Risk__c":{"field":"Churn_Risk__c","null_behavior":"reject"},"Risk_Reason__c":{"field":"Risk_Reason__c","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","target_ref":"connector://salesforce/Account","target_schema":{"additional_properties":false,"fields":{"Churn_Risk__c":{"nullable":false,"type":"string"},"Id":{"nullable":false,"type":"string"},"Risk_Reason__c":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:62b1bb5af1125a1bd7c8ef823b817937173ea48b09378e78a55d0beb340e7fe8","version":"fixture","writable_fields":["Churn_Risk__c","Risk_Reason__c"]}],"model_task_contracts":[{"authored_model_selector":"fixture-risk-model","connector_id":"models/fixture","contract_cid":"sha256:d913e3e79cef9f65f1c7250e4ca6cf9016ea87b23822e532fb4d907bfcd30782","data_handling":{"accepted_classifications":["public","internal"],"allowed_regions":["fixture-region"],"contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention":"none","training_use":"forbidden"},"generation_config":{"max_output_tokens":32,"seed_requested":-7,"temperature":0,"top_p":1},"input_contract":{"additional_properties":false,"fields":{"active_users":{"nullable":false,"type":"int64"},"notes":{"nullable":false,"type":"string"},"trend":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"input_schema_cid":"sha256:735d8d91c33e902ce54d02b0f48fac4af82c3e3fd7c3fdc076676ce015d1110b","max_items":2,"output_contract":{"additional_properties":false,"fields":{"level":{"nullable":false,"type":"string"},"reason":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"output_schema_cid":"sha256:831710c95d0c43885a6e08694b3b977e105768f1be9ae8d80e9752e3ac05e7e6","prompt_template_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retrieval_policy":"none","schema":"actql.model_task/0.1","streaming":false,"task_id":"model-task:churn-risk.v1","task_kind":"structured_generate","tool_policy":"none","version":"fixture"}],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
      ),
    ),
    "sha256:1a448dee07aa59b5199ecf17709e891d7f061c2ff0ae9109a750d17d9ead89c6",
    { max_bytes: 100000, max_nodes: 10000, max_depth: 100, max_members: 100, },
  ).unwrap()
  let tasks = @environment.check_model_tasks(wire, {
    bodies: {
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
      max_members: 100,
    },
    contracts: { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, },
    max_work: 100000,
  }).unwrap()
  @check.checking_environment(
    wire,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    model_tasks=Some(tasks),
  )
}

///|
fn readme_hero_text() -> String {
  (
    #|SELECT a.id AS id, a.description AS notes,
    #|       u.active_users, u.trend
    #|FROM salesforce.accounts AS a
    #|JOIN snowflake.usage_30d AS u ON a.id = u.account_id
    #||> INFER `model-task:churn-risk.v1`
    #|     INPUT (notes, active_users, trend) AS risk
    #||> WHERE risk.outcome = 'ok' AND risk.value.level = 'high'
    #||> RESULT updates
    #||> EFFECT UPDATE salesforce.Account
    #|     ID id SET (
    #|       Churn_Risk__c = risk.value.level,
    #|       Risk_Reason__c = risk.value.reason
    #|     );
  )
}

///|
fn readme_hero_inputs() -> Array[Input] {
  let declarations = [
    ("salesforce.accounts", (
      #|{"carrier":"relation","primary_key":["id"],"schema":{"description":{"nullable":false,"type":"string"},"id":{"nullable":false,"type":"string"}}}
    )),
    ("snowflake.usage_30d", (
      #|{"carrier":"relation","primary_key":["account_id"],"schema":{"account_id":{"nullable":false,"type":"string"},"active_users":{"nullable":false,"type":"int64"},"trend":{"nullable":false,"type":"string"}}}
    )),
  ]
  declarations.map(entry => {
    let declaration = @wire.admit(@source.parse_json(entry.1,construction_limits().source.source).unwrap(),construction_limits().source.tree).unwrap()
    {relation:entry.0.split(".").map(value => {value,quoted:false}),name:entry.0.replace(old=".",new="_"),source:Captured(declaration),visible_fields:match entry.0 {"salesforce.accounts" => ["id","description"] _ => ["account_id","active_users","trend"]},graph_bindings:[]}
  })
}

///|
fn readme_hero_context(environment : @check.CheckEnvironment) -> Context {
  {
    ..infer_member_context(environment),
    program_id: "fixture.readme_hero",
    captured_stage: None,
    inputs: readme_hero_inputs(),
  }
}

///|
fn readme_hero_publication(
  environment : @check.CheckEnvironment,
) -> UpdateTargetPublication {
  let mappings = @environment.check_mapping_contract_shapes(
    @check.checking_environment_wire(environment),
    { max_bytes: 100000, max_nodes: 10000, max_depth: 100, max_members: 100, },
    100000,
  ).unwrap()
  bind_update_target_publication(
    mappings,
    [
      {
        name: [
          { value: "salesforce", quoted: false, },
          { value: "Account", quoted: false, },
        ],
        target_ref: "connector://salesforce/Account",
        installation_binding_cid: "sha256:" + "d".repeat(64),
        installation_owner_cid: "sha256:" + "e".repeat(64),
      },
    ],
    100000,
  ).unwrap()
}

///|
test "exact README hero defaults retain the Common key and original UPDATE scope" {
  let environment=readme_hero_environment()
  let context=readme_hero_context(environment)
  let publication=readme_hero_publication(environment)
  let source=readme_hero_text()
  let explicit=source.replace(old:"INPUT (notes, active_users, trend)",new:"ITEM KEY (id) INPUT (notes = notes, active_users = active_users, trend = trend) KEEP (id, notes, active_users, trend)")
  let prepare=fn(text) {compile(@query.parse_query(text,syntax_limits()).unwrap(),context,construction_limits(),update_targets=Some(publication))}
  let actual=match prepare(source) {Ok(value)=>value Err(issue)=>fail("exact README hero: "+infer_defaults_issue_tag(issue))}
  let expanded=match prepare(explicit) {Ok(value)=>value Err(issue)=>fail("independent expanded control: "+infer_defaults_issue_tag(issue))}
  assert_eq(semantic(actual),semantic(expanded))
  assert_eq(@program.exports(actual).map(value=>value.0),["updates"])
  let headers=@program.collect_effect_headers(actual,10,100000).unwrap()
  assert_eq(@program.effect_header_count(headers),1)
  assert_eq(@program.effect_header_kind(@program.effect_header_at(headers,0).unwrap()),"update")
}

///|
test "README hero omission never borrows a key from unprojected JOIN or observed values" {
  let environment=readme_hero_environment()
  let source=readme_hero_text().replace(old:"a.id AS id",new:"a.description AS id")
  let result=compile(@query.parse_query(source,syntax_limits()).unwrap(),readme_hero_context(environment),construction_limits(),update_targets=Some(readme_hero_publication(environment)))
  assert_true(result is Err(_))
}
