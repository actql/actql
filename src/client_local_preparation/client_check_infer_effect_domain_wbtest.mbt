///|
// The combined Model/UPDATE fixture retains the two existing independent
// contracts. Its environment CID is Python SHA-256 of canonical JSON excluding
// evidence_bundle_cid; no product result supplies an expected identity.
fn infer_effect_domain_environment() -> @checked.CheckEnvironment {
  let wire =
    #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:9faf09f5a3177d36dc7c9fab868f6fe4437e4597dd12bcdc051166ec2e6ad8fd","commands":[],"connector_id":"crm","connector_version":"fixture","contracts":[],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"crm","connector_id":"crm","connector_version":"fixture"}],"version":"actql-connectors/0.1"},"contract_registry":[],"evidence_bundle_cid":"sha256:11939a2bcb67e13a36d2b9a570a2fe9b341f6e73bb3de3d9f6695afc15821a10","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[{"connector_manifest_cid":"sha256:b1b75d3b468de053f98c678ec9eedfb2f1fe7b6fcb76562b0f392121378ec7c1","conversions":[],"mapping_contract_cid":"sha256:c99f6697a8b40c16a418a156177be2a6144be3ba5ebbc36020c819789d021cd4","mapping_ref":"mapping:crm.account.v1","minimum_approval":"required","permission_rules":[{"effect_kind":"update","permissions":["scope:update"],"selector_class":"id","write_fields":["Name"]},{"effect_kind":"update","permissions":["scope:update"],"selector_class":"ids","write_fields":["Name"]}],"primary_identity":"Id","required_fields":[],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"Name":{"field":"value","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","target_ref":"connector://crm/account","target_schema":{"additional_properties":false,"fields":{"Id":{"nullable":false,"type":"string"},"Name":{"nullable":true,"type":"number"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:1208f407bf69f466944f865797ce7407361d822605d1fbbb502177af4b63958f","version":"salesforce-v1","writable_fields":["Name"]}],"model_task_contracts":[{"authored_model_selector":"fixture-risk-model","connector_id":"models/fixture","contract_cid":"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560","data_handling":{"accepted_classifications":["public","internal"],"allowed_regions":["fixture-region"],"contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention":"none","training_use":"forbidden"},"generation_config":{"max_output_tokens":32,"seed_requested":-7,"temperature":0,"top_p":1},"input_contract":{"additional_properties":false,"fields":{"text":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"input_schema_cid":"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7","max_items":2,"output_contract":{"additional_properties":false,"fields":{"reason":{"nullable":true,"type":"string"},"risk":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"output_schema_cid":"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3","prompt_template_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retrieval_policy":"none","schema":"actql.model_task/0.1","streaming":false,"task_id":"model-task:risk-score.v1","task_kind":"structured_generate","tool_policy":"none","version":"1"}],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
  @host.admit_client_check_environment(
    wire,
    "sha256:11939a2bcb67e13a36d2b9a570a2fe9b341f6e73bb3de3d9f6695afc15821a10",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
}

///|
test "static INFER UPDATE preserves its original known outcome domain refusal" {
  let environment = infer_effect_domain_environment()
  let publication = source_bridge_effect_publication(environment)
  let document = "SELECT DISTINCT 'a' AS id |> EXTEND 'urgent' AS text " +
    "|> INFER `model-task:risk-score.v1` ITEM KEY (id) INPUT (text = text) " +
    "KEEP (id) AS assessment |> WHERE assessment.outcome = 1 AND assessment.value.risk = 'high' " +
    "|> RESULT out |> EFFECT UPDATE salesforce.Account ID id SET (Name = 1)"
  let report = client_program_check_source(
    document,
    "aql",
    environment,
    publication,
    None,
    None,
    "ctx:infer-effect-domain",
    "rev:" + "a".repeat(64),
    None,
    None,
    "corr:infer-effect-domain",
    "bound_input",
    None,
  )
  assert_true(report.contains("\"verdict\":\"invalid\""), msg=report)
  assert_true(report.contains("expression_domain_mismatch"), msg=report)
  assert_true(report.contains("key_comparable_operands"), msg=report)
  assert_true(report.contains("\"requirements\":[]"), msg=report)
  assert_true(!report.contains("implementation_limit"), msg=report)
}
