///|
// Independently authored input and installed Mapping. The fixture's declared
// input digests were calculated with Python hashlib, not the product output.
// This preparation/admission fixture grants no physical Provider permission.
let native_client_effect_fixture_document : String =
  #|{"id":"native-effect","results":{"published":{"from":{"result":"out","stage":"source"}}},"stages":[{"effects":{"save":{"create":{"from":{"result":"out"},"mapping":"mapping:crm.account.v1","target":"connector://crm/account"}}},"id":"source","inputs":{},"results":{"out":{"fields":["value"],"from":"selected"}},"steps":[{"as":"selected","values":{"rows":[{"value":"e\u0301\r\n"}],"schema":{"value":{"nullable":false,"type":"string"}}}}]}],"version":"actql/0.1"}

///|
let native_client_effect_fixture_environment_wire : String =
  #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:9faf09f5a3177d36dc7c9fab868f6fe4437e4597dd12bcdc051166ec2e6ad8fd","commands":[],"connector_id":"crm","connector_version":"fixture","contracts":[],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"crm","connector_id":"crm","connector_version":"fixture"}],"version":"actql-connectors/0.1"},"contract_registry":[],"evidence_bundle_cid":"sha256:67979d9f5507bd9dd0809091d96b7dc96a1dce6e30df75ad0fac523f9c3ad808","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[{"connector_manifest_cid":"sha256:b1b75d3b468de053f98c678ec9eedfb2f1fe7b6fcb76562b0f392121378ec7c1","conversions":[],"mapping_contract_cid":"sha256:1be9426a9b8809a531aae1c2cac2bfe7bef35b4fccff982c52da4a4de350190b","mapping_ref":"mapping:crm.account.v1","minimum_approval":"required","permission_rules":[{"effect_kind":"create","permissions":["scope:create"],"selector_class":"none","write_fields":["Name"]}],"primary_identity":"Id","required_fields":[],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"Name":{"field":"value","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","target_ref":"connector://crm/account","target_schema":{"additional_properties":false,"fields":{"Id":{"nullable":false,"type":"string"},"Name":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:bb7f22131b239944c4d7f01ddc3eaf675c34e38ca195527a90c6863668150e66","version":"salesforce-v1","writable_fields":["Name"]}],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}

///|
fn native_client_effect_fixture_environment() -> @checked.CheckEnvironment {
  @host.admit_client_check_environment(
    native_client_effect_fixture_environment_wire,
    "sha256:67979d9f5507bd9dd0809091d96b7dc96a1dce6e30df75ad0fac523f9c3ad808",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
}

///|
fn native_client_effect_fixture_preparation(
  intent : @host.ClientSubmittedIntent,
) -> NativeClientSubmittedPreparation {
  prepare_native_client_submitted_program(
    intent,
    native_client_effect_fixture_environment(),
    None,
    [],
    @host.client_standard_effect_computation_limits(),
  ).unwrap()
}

///|
fn native_client_effect_fixture_run(
  preparation : NativeClientSubmittedPreparation,
  reference : NativeClientSubmissionReference,
  run_id : String,
  scope? : String = "sha256:" + "a".repeat(64),
) -> (
  @host.ClientRequestIdentity,
  @host.ClientEffectAllowedRun,
  @publication.PublicationContract,
) raise {
  guard preparation.preparation is EffectComputation(prepared) else {
    fail("original Effect was not prepared")
  }
  let manifests = @host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    10000,
    1000,
    20,
  ).unwrap()
  let compilation = @host.issue_prepared_client_effect_compilation(
    prepared,
    manifests,
    @host.client_standard_values_sequence_limits(),
    32,
    64,
    100000,
    10000,
    100,
  ).unwrap()
  let allowed = @host.issue_client_effect_allowed_run(
    compilation,
    scope,
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @host.issue_client_effect_run_definition(
    allowed, "local-test", run_id, "2026-10-10T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let request = @host.prepare_client_effect_request_identity(
    prepared,
    scope,
    reference.request_id,
    @host.source_free_caller_input_intent_cid(),
  ).unwrap()
  (request, allowed, definition)
}

///|
fn native_client_effect_fixture_input(
  reference : NativeClientSubmissionReference,
  run_id : String,
  document? : String = native_client_effect_fixture_document,
) -> (
  @host.ClientSubmittedIntent,
  NativeClientSubmittedPreparation,
  @host.ClientRequestIdentity,
  @host.ClientEffectAllowedRun,
  @publication.PublicationContract,
) raise {
  let intent = @host.prepare_client_submitted_intent(
    "{\"kind\":\"program\",\"input\":" + document + ",\"parameters\":null}",
    65536,
    8192,
    64,
  ).unwrap()
  let preparation = native_client_effect_fixture_preparation(intent)
  let (request, allowed, definition) = native_client_effect_fixture_run(
    preparation, reference, run_id,
  )
  (intent, preparation, request, allowed, definition)
}
