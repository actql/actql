///|
// Independent original from keyed_effect_fixture_test. These are actual Source
// callers; they do not manufacture installation originals or exercise I/O.
fn keyed_source_environment() -> @program_check.CheckEnvironment {
  client_program_check_environment(
    (
      #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:9faf09f5a3177d36dc7c9fab868f6fe4437e4597dd12bcdc051166ec2e6ad8fd","commands":[],"connector_id":"crm","connector_version":"fixture","contracts":[],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"crm","connector_id":"crm","connector_version":"fixture"}],"version":"actql-connectors/0.1"},"contract_registry":[],"evidence_bundle_cid":"sha256:1076bb2e2c919e744d55e6dfdb1c6a093e86f68043983e52799ff058118af969","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_analytic_frame_memberships":1000,"max_analytic_input_wire_bytes":1000,"max_analytic_output_wire_bytes":1000,"max_analytic_partition_wire_bytes":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[{"connector_manifest_cid":"sha256:b1b75d3b468de053f98c678ec9eedfb2f1fe7b6fcb76562b0f392121378ec7c1","conversions":[],"mapping_contract_cid":"sha256:4d938cc5bfcca0020bde03eada3316f7a432d3964c27a929e562f284bf1d3229","mapping_ref":"mapping:crm.account.v1","minimum_approval":"none","permission_rules":[{"effect_kind":"update","permissions":["scope:update"],"selector_class":"id","write_fields":["Name"]},{"effect_kind":"upsert","permissions":["scope:upsert"],"selector_class":"key","write_fields":["Name"]},{"effect_kind":"delete","permissions":["scope:delete"],"selector_class":"id","write_fields":[]}],"primary_identity":"Id","required_fields":[],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"Name":{"field":"name","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","target_ref":"connector://crm/account","target_schema":{"additional_properties":false,"fields":{"Id":{"nullable":false,"type":"string"},"Name":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:bb7f22131b239944c4d7f01ddc3eaf675c34e38ca195527a90c6863668150e66","version":"fixture","writable_fields":["Name"]}],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
    ),
    "sha256:1076bb2e2c919e744d55e6dfdb1c6a093e86f68043983e52799ff058118af969",
    false,
    false,
    true,
    false,
    false,
    false,
    false,
  ).unwrap()
}

///|
test "actual keyed Source preparation refuses unsupported original purpose without discarding the Effect" {
  let environment = keyed_source_environment()
  let publication = "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[],\"updateTargets\":[{\"name\":\"salesforce.Account\",\"targetRef\":\"connector://crm/account\",\"installationBindingCid\":\"sha256:" +
    "d".repeat(64) +
    "\",\"installationOwnerCid\":\"sha256:" +
    "e".repeat(64) +
    "\"}]}"
  assert_true(client_program_source_publication_valid(environment, publication))
  for
    (word, kind) in [
      ("UPSERT", @query_syntax.KeyedEffectKind::Upsert),
      ("DELETE", Delete),
    ] {
    let suffix = if word == "UPSERT" { " SET (Name = name)" } else { "" }
    let text = "SELECT 'id' AS id, 'original name' AS name |> EFFECT " +
      word +
      " salesforce.Account ID id" +
      suffix
    let lowered = match
      client_program_lower_source(text, "sql", environment, publication, None) {
      Ok(value) => value
      Err(_) => fail("actual record Source lowering")
    }
    assert_eq(lowered.keyed_effect_kind, Some(kind))
    assert_eq(
      @stage_syntax.effect_header_count(
        @stage_syntax.collect_effect_headers(lowered.program.unwrap(), 1, 10000).unwrap(),
      ),
      1,
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
      is SourcePure(
        Rejected(SourcePreparation(RecordTargetOriginalsUnavailable))
      ),
    )
  }
  let pure = client_program_lower_source(
    "SELECT 'unchanged' AS name",
    "sql",
    environment,
    publication,
    None,
  ).unwrap()
  assert_true(pure.keyed_effect_kind is None)
}
