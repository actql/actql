///|
fn original_string_fragment_request() -> @lower.FragmentRequest {
  let unsigned =
    #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"},"text_time_evaluation":{"max_input_codepoints":64,"max_input_utf8_bytes":256,"max_output_bytes":64,"max_pattern_bytes":1,"max_replacements":1,"version":"actql-text-time-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
  let cid = "sha256:" + @sha.hex(@utf8.encode(unsigned))
  let wire = unsigned.replace(old="\"host_policy_profile\":", new="\"evidence_bundle_cid\":\"" + cid + "\",\"host_policy_profile\":")
  let environment = @client_host.admit_client_check_environment(
    wire, cid, { text_time: true, veca: false },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false },
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"sealed-string","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"text":{"type":"string","nullable":false}},"rows":[{"text":"12.5"}]},"as":"input"},{"derive":{"n":{"try_number":{"value":{"field":"text"}}}},"as":"parsed"}],"results":{"r":{"from":"parsed","fields":["n"]}}}],"results":{"r":{"from":{"stage":"main","result":"r"}}}}
  let prepared = @client_host.prepare_effect_free_client_program(
    document, Json, environment, None,
    @client_host.client_standard_program_preparation_limits(),
  ).unwrap()
  let owner = @strategy.graph_task_owner(@client_host.prepared_client_graph(prepared), 0).unwrap()
  let sequence = prepared_sequence(owner)
  let pipeline = @lower.prepare_fragment_pipeline(sequence, 1, {
    max_roots: 100, max_pointer_bytes: 10000, max_work: 100000,
  }).unwrap()
  @lower.prepare_fragment_request(pipeline, 10L, 1000L).unwrap()
}

///|
test "String TRY_NUMBER fragment seals the original profile and independently hashed complete envelope" {
  let material = prepare_fragment_material(
    original_string_fragment_request(), material_demands(), registry_limits(),
  ).unwrap()
  assert_eq(material.evaluations.length(), 1)
  let envelope = @identity.object_field(material.evaluations[0].value, "envelope").unwrap()
  // Independently constructed from the specified argument, runtime-preflight,
  // Host policy and envelope preimages using Python hashlib; not product output.
  let expected =
    #|{"arguments_cid":"sha256:003cab4c0aef9a91f0da865ddb75695d5db41f88839d7c2764a4a560c9499942","demand_path":[],"envelope_cid":"sha256:cc4cff7cebe0a1859a0d6eec880fc981fafd66650793d1d0bcb72ce284ee0f66","expression_pointer":"/roots/0/source","host_policy_profile_cid":"sha256:cc81cb2eff39b8fae7bb7ad6f67414fdce9bff9fccd641e25b080cbe2b0ed46f","input":{"evidence_cid":"sha256:43aad4b014c3beaa52074d3082135ec72cf135224163a510ad0408c74955bc71","max_codepoints":64,"max_utf8_bytes":256,"source":"runtime_preflight"},"max_output_bytes":32,"operation":"try_number","semantic_step_id":"derive_1","verification":"unit_preflight","version":"actql-text-time-evaluation-envelope/0.1"}
  assert_eq(@identity.stringify_value(envelope, 10000, 1000, 100), expected)
  assert_true(@identity.object_field(material.evaluations[0].value, "node_pointer")
    is Some(@identity.String("/roots/0/node")))
  let candidate = prepare_fragment_candidate(
    test_fragment_contract(), material, registry_limits(),
  ).unwrap()
  assert_true(check_generated_fragment(candidate, material_demands(), registry_limits()) is Ok(_))
  let omitted = { ..candidate, material: { ..material, evaluations: [] }, }
  assert_true(check_generated_fragment(omitted, material_demands(), registry_limits()) is Err(Integrity))
}
