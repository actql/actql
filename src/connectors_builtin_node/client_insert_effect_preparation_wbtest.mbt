///|
// Independent original Mapping; real Source preparation caller, no Provider.
test "actual INSERT Source retains create and refuses unconnected original purpose" {
  let environment = client_program_check_environment(
    (
      #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:9faf09f5a3177d36dc7c9fab868f6fe4437e4597dd12bcdc051166ec2e6ad8fd","commands":[],"connector_id":"crm","connector_version":"fixture","contracts":[],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"crm","connector_id":"crm","connector_version":"fixture"}],"version":"actql-connectors/0.1"},"contract_registry":[],"evidence_bundle_cid":"sha256:6a38fdaffd7fbc7a2bd489a2614805f302a184a59a796a0c459e07662395d4b8","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_analytic_frame_memberships":1000,"max_analytic_input_wire_bytes":1000,"max_analytic_output_wire_bytes":1000,"max_analytic_partition_wire_bytes":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[{"connector_manifest_cid":"sha256:b1b75d3b468de053f98c678ec9eedfb2f1fe7b6fcb76562b0f392121378ec7c1","conversions":[],"mapping_contract_cid":"sha256:fb7d0ed30f8717314a15956a64d9c80e3d4b6f204bf4e573cdbec0d831620576","mapping_ref":"mapping:crm.account.v1","minimum_approval":"none","permission_rules":[{"effect_kind":"create","permissions":["scope:create"],"selector_class":"none","write_fields":["Name"]}],"primary_identity":"Id","required_fields":["Name"],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"Name":{"field":"name","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","target_ref":"connector://crm/account","target_schema":{"additional_properties":false,"fields":{"Id":{"nullable":false,"type":"string"},"Name":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:bb7f22131b239944c4d7f01ddc3eaf675c34e38ca195527a90c6863668150e66","version":"fixture","writable_fields":["Name"]}],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
    ),
    "sha256:6a38fdaffd7fbc7a2bd489a2614805f302a184a59a796a0c459e07662395d4b8",
    false,
    false,
    true,
    false,
    false,
    false,
    false,
  ).unwrap()
  let publication = "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[],\"updateTargets\":[{\"name\":\"salesforce.Account\",\"targetRef\":\"connector://crm/account\",\"installationBindingCid\":\"sha256:" +
    "d".repeat(64) +
    "\",\"installationOwnerCid\":\"sha256:" +
    "e".repeat(64) +
    "\"}]}"
  let text = "SELECT 'original name' AS Name |> EFFECT INSERT salesforce.Account (Name)"
  let lowered = match
    client_program_lower_source(text, "sql", environment, publication, None) {
    Ok(value) => value
    Err(_) => fail("actual INSERT Source lowering")
  }
  assert_true(lowered.insert_effect)
  assert_true(lowered.keyed_effect_kind is None)
  let header = @stage_syntax.effect_header_at(
    @stage_syntax.collect_effect_headers(lowered.program.unwrap(), 1, 10000).unwrap(),
    0,
  ).unwrap()
  assert_eq(@stage_syntax.effect_header_kind(header), "create")
  let values = @stage_syntax.effect_header_create_values(header).unwrap()
  let fields = @decode.open_object(values).unwrap()
  assert_eq(@decode.object_length(values), Some(1))
  let original = @decode.lookup(fields, "Name").unwrap()
  assert_eq(
    @decode.text(
      @decode.lookup(@decode.open_object(original).unwrap(), "field").unwrap(),
    ),
    Ok("Name"),
  )
  assert_true(
    client_program_prepare_source_computation_with_parameters(
      text,
      "sql",
      environment,
      publication,
      None,
      None,
      true,
      [],
    )
    is SourcePure(Rejected(SourcePreparation(RecordTargetOriginalsUnavailable))),
  )
}
