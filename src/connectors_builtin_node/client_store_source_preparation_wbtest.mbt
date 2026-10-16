///|
// Same independent original as the compiler/Effect test. This is a pure public
// preparation caller, not installed Reference issuance or an Effect Run.
fn store_source_preparation_environment() -> @program_check.CheckEnvironment {
  client_program_check_environment(
    (
      #|{"command_contracts":[{"atomicity":"single_target","command_id":"command:fixture.upload.v1","connector_id":"storage","contract_cid":"sha256:cc127c70d073273d011fbb36068fb8b45e77cab31fa5d0737553bccb9978b0f2","idempotency":{"support":"unsupported"},"input_contract":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"path":{"nullable":false,"type":"string"}}},"input_schema":{"cid":"sha256:0146ce90a7071e37336a39b05f68d2f1505847a80a6f37731140fbb60ae54312","id":"fixture.upload.command_input","version":"fixture-1"},"minimum_approval":"required","outcome":"synchronous","output_schema":{"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","version":"fixture-1"},"permissions":["scope:write"],"preview":{"strength":"exact"},"reversibility":"unknown","schema":"actql.command_contract/0.1","target":{"cardinality":"single","resource_kind":"file_collection"},"version":"fixture-1"}],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:a937153e39e2f69f5d6893275d3b6a7457498cc22627a1152627d473897f8757","commands":[{"atomicity":"single_target","command_id":"command:fixture.upload.v1","connector_id":"storage","contract_cid":"sha256:cc127c70d073273d011fbb36068fb8b45e77cab31fa5d0737553bccb9978b0f2","idempotency":{"support":"unsupported"},"input_contract":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"path":{"nullable":false,"type":"string"}}},"input_schema":{"cid":"sha256:0146ce90a7071e37336a39b05f68d2f1505847a80a6f37731140fbb60ae54312","id":"fixture.upload.command_input","version":"fixture-1"},"minimum_approval":"required","outcome":"synchronous","output_schema":{"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","version":"fixture-1"},"permissions":["scope:write"],"preview":{"strength":"exact"},"reversibility":"unknown","schema":"actql.command_contract/0.1","target":{"cardinality":"single","resource_kind":"file_collection"},"version":"fixture-1"}],"connector_id":"storage","connector_version":"fixture-1","contracts":[{"body":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"path":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:0146ce90a7071e37336a39b05f68d2f1505847a80a6f37731140fbb60ae54312","id":"fixture.upload.command_input","kind":"command_input","schema":"actql.contract/0.1","version":"fixture-1"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","kind":"command_output","schema":"actql.contract/0.1","version":"fixture-1"}],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"fixture","connector_id":"storage","connector_version":"fixture-1"}],"version":"actql-connectors/0.1"},"contract_registry":[{"body":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"path":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:0146ce90a7071e37336a39b05f68d2f1505847a80a6f37731140fbb60ae54312","id":"fixture.upload.command_input","kind":"command_input","schema":"actql.contract/0.1","version":"fixture-1"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","kind":"command_output","schema":"actql.contract/0.1","version":"fixture-1"}],"evidence_bundle_cid":"sha256:f90cdb6f1b80d81f2ca9707aa5378f63be5aae1dc73b9a6c7e0028dd5f837c3f","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_analytic_frame_memberships":1000,"max_analytic_input_wire_bytes":1000,"max_analytic_output_wire_bytes":1000,"max_analytic_partition_wire_bytes":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[{"connector_manifest_cid":"sha256:6960590acec3fcbd045e40dbb94ec08f77c3a2d271943b019a8ada57283a3208","conversions":[],"mapping_contract_cid":"sha256:7d2514050811313eeb33ef05a6a694c0dfb5bbfd6cf1347a072853b6320b459a","mapping_ref":"mapping:fixture.archive.v1","minimum_approval":"none","permission_rules":[{"effect_kind":"create","permissions":["scope:write"],"selector_class":"none","write_fields":["content","path"]}],"primary_identity":null,"required_fields":["content","path"],"required_permissions":[],"resource_identity_cid":"sha256:e3d4f3b2c3b392c4c889b78ea6b4794bc6a715d39a740275ab3c936d20ec6759","row_mapping":{"content":{"field":"content","null_behavior":"reject"},"path":{"field":"path","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","store_command":{"catalog_cid":"sha256:a937153e39e2f69f5d6893275d3b6a7457498cc22627a1152627d473897f8757","command_contract_cid":"sha256:cc127c70d073273d011fbb36068fb8b45e77cab31fa5d0737553bccb9978b0f2","command_ref":"command:fixture.upload.v1"},"target_ref":"connector://storage/archive","target_schema":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"path":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:793f546b62fd8f3db0862d0369fc5451de8cee5fce0bd2408d7749efc6c3c336","version":"fixture-1","writable_fields":["content","path"]}],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
    ),
    "sha256:f90cdb6f1b80d81f2ca9707aa5378f63be5aae1dc73b9a6c7e0028dd5f837c3f",
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
fn store_source_preparation_text() -> String {
  "SELECT 1 AS id |> SERIALIZE FORMAT JSONL PRESERVE ORDER OPTIONS (name = 'one.jsonl', max_rows = 1, max_bytes = 128) |> EFFECT STORE storage.archive SET (path = name, content = content)"
}

///|
test "published STORE public source lowerer retains its original publication" {
  let environment = store_source_preparation_environment()
  let publication = store_public_bridge_publication(environment)
  let lowered = match
    client_program_lower_source(
      store_source_preparation_text(),
      "sql",
      environment,
      publication,
      None,
    ) {
    Ok(value) => value
    Err(_) =>
      fail("public source lowerer must receive the original STORE publication")
  }
  let targets = lowered.store_targets.unwrap()
  assert_true(
    physical_equal(
      @query_program.store_target_publication_environment(targets),
      @program_check.checking_environment_wire(environment),
    ),
  )
  let target = @query_program.resolve_store_target_binding(
    targets,
    [{ value: "storage", quoted: false, }, { value: "archive", quoted: false, }],
    1000,
  ).unwrap()
  let (_, _, binding, owner) = @query_program.resolved_store_target_identity(
    target,
  )
  assert_eq(binding, "sha256:" + "d".repeat(64))
  assert_eq(owner, "sha256:" + "e".repeat(64))
  let headers = @stage_syntax.collect_effect_headers(
    lowered.program.unwrap(),
    1,
    10000,
  ).unwrap()
  assert_eq(
    @stage_syntax.effect_header_published_store_target(
      @stage_syntax.effect_header_at(headers, 0).unwrap(),
    ),
    Some(("connector://storage/archive", "mapping:fixture.archive.v1")),
  )
}

///|
test "published STORE public source still requires the explicit Effect preparation route" {
  let environment = store_source_preparation_environment()
  let publication = store_public_bridge_publication(environment)
  for format in ["sql", "aql-text"] {
    let outcome = client_program_prepare_source_computation_with_parameters(
      store_source_preparation_text(),
      format,
      environment,
      publication,
      None,
      None,
      false,
      [],
    )
    assert_true(
      outcome is SourcePure(Rejected(Preparation(EffectNotSupported(_)))),
    )
  }
}

///|
test "published STORE check source uses the original target and common input types" {
  let environment = store_source_preparation_environment()
  let publication = store_public_bridge_publication(environment)
  for format in ["sql", "aql-text"] {
    let report = client_program_check_source(
      store_source_preparation_text(),
      format,
      environment,
      publication,
      None,
      None,
      "ctx:store",
      "rev:store",
      None,
      None,
      "corr:store",
      "bound_input",
      None,
    )
    assert_true(report.contains("\"verdict\":\"verified\""), msg=report)
    let invalid = store_source_preparation_text().replace(
      old="content = content",
      new="content = 7",
    )
    let rejected = client_program_check_source(
      invalid,
      format,
      environment,
      publication,
      None,
      None,
      "ctx:store",
      "rev:store",
      None,
      None,
      "corr:store",
      "bound_input",
      None,
    )
    assert_true(rejected.contains("\"verdict\":\"invalid\""), msg=rejected)
    assert_true(rejected.contains("\"code\":\"query_invalid\""), msg=rejected)
    assert_true(!rejected.contains("implementation_limit"), msg=rejected)
  }
}
