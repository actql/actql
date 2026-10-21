///|
// Preserve the existing Node preparation failure domain while using the same
// portable publication owner as the public check projection.
fn client_table_write_publication(
  environment : @program_check.CheckEnvironment,
  publication : String,
) -> Array[@query_program.TableWriteBinding] raise ClientSourceStop {
  match @source_publication.published_table_writes(environment, publication) {
    Ok(value) => value
    Err(Limit) => raise ClientSourceStop(Limit)
    Err(_) => raise ClientSourceStop(Publication)
  }
}

///|
// Independent installed environment and fixed binding, before physical I/O.
test "Table publication validates installed Mapping before lowering" {
  let wire = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[{\"catalog_cid\":\"sha256:5e08bd4afedbd52e332bff556d21ae024806b40acfdff7d683c63fbfd9c12576\",\"commands\":[],\"connector_id\":\"table\",\"connector_version\":\"fixture\",\"contracts\":[],\"schema\":\"actql.connector_catalog/0.1\",\"source_views\":[]}],\"connector_manifest\":{\"connectors\":[{\"connector\":\"table\",\"connector_id\":\"table\",\"connector_version\":\"fixture\"}],\"version\":\"actql-connectors/0.1\"},\"contract_registry\":[],\"evidence_bundle_cid\":\"sha256:ee8bc2292e30621d67ad36adb1a25987d113448e5b6dd333cbaf5511328e20dc\",\"host_policy_profile\":{\"capacity\":{\"max_aggregate_array_items\":1000,\"max_artifact_bytes\":1000,\"max_artifact_rows\":1000,\"max_effect_items\":1000,\"max_graph_input_edges\":1000,\"max_graph_input_nodes\":1000,\"max_graph_output_rows\":1000,\"max_graph_paths\":1000,\"max_infer_items\":1000,\"max_model_input_tokens_per_item\":1000,\"max_model_request_bytes_per_item\":1000,\"max_model_total_duration_ms\":1000,\"max_nested_value_bytes\":1000,\"max_nested_value_depth\":1000,\"max_relation_output_rows\":1000,\"max_temporal_matches_per_key\":1000,\"max_temporal_output_rows\":1000,\"version\":\"actql-capacity-host-policy/0.1\"}},\"mapping_contracts\":[{\"connector_manifest_cid\":\"sha256:a1a3727735c1e6af17286d33e4eccf591d11821edb1fbed9bb963284027b9874\",\"conversions\":[],\"mapping_contract_cid\":\"sha256:112eeda664d4f10b1a5c827b49ff301c42366fc831b381919036d2cf81591f1b\",\"mapping_ref\":\"mapping:table.catalog.v1\",\"minimum_approval\":\"required\",\"permission_rules\":[{\"effect_kind\":\"store\",\"permissions\":[\"scope:store\"],\"selector_class\":\"none\",\"write_fields\":[\"Name\"]}],\"primary_identity\":\"Id\",\"required_fields\":[],\"required_permissions\":[],\"resource_identity_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"row_mapping\":{\"Name\":{\"field\":\"id\",\"null_behavior\":\"reject\"}},\"schema\":\"actql.mapping_contract/0.1\",\"target_ref\":\"connector://table/catalog\",\"target_schema\":{\"additional_properties\":false,\"fields\":{\"Id\":{\"nullable\":false,\"type\":\"number\"},\"Name\":{\"nullable\":true,\"type\":\"number\"}},\"nullable\":false,\"type\":\"object\"},\"target_schema_identity\":\"sha256:c000fb12383456a0e123e74501d164b96bb886251dbb44f301661070321be8e0\",\"version\":\"reference-v1\",\"writable_fields\":[\"Name\"]}],\"model_task_contracts\":[],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  let environment = client_program_check_environment(
    wire, "sha256:ee8bc2292e30621d67ad36adb1a25987d113448e5b6dd333cbaf5511328e20dc",
    false, false, true, false, false, false, false,
  ).unwrap()
  let mappings = @check_environment.check_mapping_contract_shapes(
    @program_check.checking_environment_wire(environment),
    { max_bytes: 1048576, max_nodes: 16384, max_depth: 32, max_members: 32768, },
    1000000,
  ).unwrap()
  assert_eq(@check_environment.mapping_shape_count(mappings), 1)
  let publication = "{\"environmentCid\":\"sha256:ee8bc2292e30621d67ad36adb1a25987d113448e5b6dd333cbaf5511328e20dc\",\"aliases\":[],\"tableWrites\":[{\"name\":\"analytics.report\",\"targetRef\":\"connector://table/catalog\",\"mappingRef\":\"mapping:table.catalog.v1\",\"mappingCid\":\"sha256:112eeda664d4f10b1a5c827b49ff301c42366fc831b381919036d2cf81591f1b\",\"capabilityCid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"installationBindingCid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"action\":\"create\",\"expectedTable\":null}]}"
  let context_valid = try {
    client_source_context(environment, publication, None) |> ignore
    true
  } catch {
    _ => false
  }
  assert_true(context_valid, msg="Read context remains independently valid")
  let root = source_publication_cursor(publication)
  let entry = @decode.elements(source_publication_field(root, "tableWrites")).unwrap()[0]
  let name = @query_syntax.parse_relation_path(
    source_publication_text(entry, "name"),
    {
      max_source_bytes: 1024,
      max_tokens: 256,
      max_literal_bytes: 1024,
      max_work: 16384,
    },
  ).unwrap()
  let mapping = @check_environment.mapping_shape_for(
    mappings,
    source_publication_text(entry, "mappingRef"),
  ).unwrap()
  assert_eq(
    @check_environment.mapping_shape_cid(mapping),
    source_publication_text(entry, "mappingCid"),
  )
  assert_eq(
    @check_environment.mapping_shape_target(mapping),
    source_publication_text(entry, "targetRef"),
  )
  assert_true(
    @decode.view(
      @decode.lookup(@decode.open_object(entry).unwrap(), "expectedTable").unwrap(),
    )
    is @decode.NullValue,
  )
  assert_true(
    @query_program.resolve_table_write_binding(
      [
        {
          name,
          target_ref: source_publication_text(entry, "targetRef"),
          mapping_ref: source_publication_text(entry, "mappingRef"),
          mapping_cid: source_publication_text(entry, "mappingCid"),
          capability_cid: source_publication_text(entry, "capabilityCid"),
          installation_binding_cid: source_publication_text(
            entry, "installationBindingCid",
          ),
          action: @query_program.Create,
        },
      ],
      name,
      true,
      1000000,
    )
    is Ok(_),
    msg="Fixed publication metadata passes the common resolver",
  )
  let bindings = Some(client_table_write_publication(environment, publication)) catch {
    _ => None
  }
  assert_true(bindings is Some(_), msg="Installed Table publication is valid")
  let bindings = bindings.unwrap()
  assert_eq(bindings.length(), 1)
  assert_eq(bindings[0].mapping_ref, "mapping:table.catalog.v1")
  assert_true(bindings[0].action is @query_program.Create)
  let missing = publication.replace(
    old="\"expectedTable\":null",
    new="\"unexpected\":null",
  )
  assert_true(!client_program_source_publication_valid(environment, missing))
  let invalid = publication.replace(
    old="\"expectedTable\":null",
    new="\"expectedTable\":{}",
  )
  assert_true(!client_program_source_publication_valid(environment, invalid))
  let report = client_program_check_source(
    "CREATE TABLE analytics.report AS SELECT 1 AS id",
    "sql",
    environment,
    publication,
    None,
    None,
    "ctx:fixture",
    "source:fixture",
    None,
    None,
    "corr:fixture",
    "bound_input",
    None,
  )
  assert_true(report.contains("\"verdict\":\"verified\""), msg=report)
  let prepared = match
    client_program_prepare_source_computation_with_parameters(
      "CREATE TABLE analytics.report AS SELECT 1 AS id",
      "sql",
      environment,
      publication,
      None,
      None,
      true,
      [],
    ) {
    SourceEffect(EffectPrepared(value)) => value
    _ => fail("Table source must retain the admitted Effect owner")
  }
  assert_eq(client_program_effect_result_count(prepared), 0)
  let compiled = client_program_compile_local_effects(prepared).unwrap()
  assert_true(
    client_program_effect_compilation_plan_wire(compiled).contains(
      "\"effect_result\"",
    ),
  )
}
