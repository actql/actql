///|
// Fixed independent environment. This exercises preparation, not Provider I/O.
test "public full and logical UPDATE preparation retain one concrete selection" {
  let wire =
    #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:9faf09f5a3177d36dc7c9fab868f6fe4437e4597dd12bcdc051166ec2e6ad8fd","commands":[],"connector_id":"crm","connector_version":"fixture","contracts":[],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"crm","connector_id":"crm","connector_version":"fixture"}],"version":"actql-connectors/0.1"},"contract_registry":[],"evidence_bundle_cid":"sha256:ef3c11ecddf6d35749bb98df9820c0459b72190354495ffb87e877a5e5ae7d97","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[{"connector_manifest_cid":"sha256:b1b75d3b468de053f98c678ec9eedfb2f1fe7b6fcb76562b0f392121378ec7c1","conversions":[],"mapping_contract_cid":"sha256:8806f951f0eba711a67aa15619f5f892d505983e5d8c47479cf5798d60f75fcd","mapping_ref":"mapping:crm.account.v1","minimum_approval":"none","permission_rules":[{"effect_kind":"update","permissions":["scope:update"],"selector_class":"id","write_fields":["Name"]}],"primary_identity":"Id","required_fields":[],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"Name":{"field":"name","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","target_ref":"connector://crm/account","target_schema":{"additional_properties":false,"fields":{"Id":{"nullable":false,"type":"string"},"Name":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:bb7f22131b239944c4d7f01ddc3eaf675c34e38ca195527a90c6863668150e66","version":"fixture","writable_fields":["Name"]}],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
  let environment = client_program_check_environment(
    wire, "sha256:ef3c11ecddf6d35749bb98df9820c0459b72190354495ffb87e877a5e5ae7d97",
    false, false, true, false, false, false, false,
  ).unwrap()
  let publication =
    #|{"aliases":[],"environmentCid":"sha256:ef3c11ecddf6d35749bb98df9820c0459b72190354495ffb87e877a5e5ae7d97","updateTargets":[{"installationBindingCid":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","installationOwnerCid":"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","name":"salesforce.Account","targetRef":"connector://crm/account"}]}
  assert_true(client_program_source_publication_valid(environment, publication))
  let prefix = "SELECT 'id' AS id, 'name' AS name |> RESULT updates |> EFFECT UPDATE "
  let suffix = " FROM RESULT updates ID id SET (Name = name)"
  let full = client_program_lower_source(
    prefix +
    "TARGET 'connector://crm/account' MAPPING `mapping:crm.account.v1`" +
    suffix,
    "sql",
    environment,
    publication,
    None,
  ).unwrap()
  assert_true(full.update_targets is Some(_))
  let json = client_program_prepare_published_effect_computation_with_parameters(
    full.document,
    "json",
    environment,
    publication,
    None,
    [],
  )
  let json = client_program_effect_preparation_ready(json).unwrap()
  let selection = @publication_host.prepared_client_effect_target_selections(
    json,
  ).unwrap()
  let legacy = client_program_prepare_effect_computation_with_parameters(
    full.document,
    "json",
    environment,
    None,
    [],
  )
  assert_true(
    @publication_host.prepared_client_effect_target_selections(
      client_program_effect_preparation_ready(legacy).unwrap(),
    )
    is None,
  )
  for
    invalid in [
      publication.replace(
        old="ef3c11ecddf6d35749bb98df9820c0459b72190354495ffb87e877a5e5ae7d97",
        new="a".repeat(64),
      ),
      publication.replace(old="installationOwnerCid", new="unknownOwnerCid"),
      "{}",
    ] {
    assert_true(
      client_program_prepare_published_effect_computation_with_parameters(
        full.document,
        "json",
        environment,
        invalid,
        None,
        [],
      )
      is EffectRejected(Input(SourcePreparation(Publication))),
    )
  }
  for
    target in [
      "salesforce.Account", "salesforce.Account MAPPING `mapping:crm.account.v1`",
    ] {
    let short = client_program_lower_source(
      prefix + target + suffix,
      "sql",
      environment,
      publication,
      None,
    ).unwrap()
    assert_eq(short.document, full.document)
    assert_true(short.update_targets is Some(_))
    let prepared = match
      client_program_prepare_source_computation_with_parameters(
        prefix + target + suffix,
        "sql",
        environment,
        publication,
        None,
        None,
        true,
        [],
      ) {
      SourceEffect(EffectPrepared(value)) => value
      _ => abort("expected ordinary prepared Effect owner")
    }
    assert_true(
      @publication_host.prepared_client_effect_target_selections(prepared)
      is Some(_),
    )
    assert_eq(
      @publication_host.prepared_client_effect_target_selections(prepared).unwrap(),
      selection,
    )
  }
}
