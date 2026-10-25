///|
// The two real declared Source views share the original independent schema and
// [b, a] key facts. No Vectors carrier or publication order is invented here.
fn composite_vector_source_test_declaration(
  checked : Bool,
) -> Result[@row_host.RowDeclaration, @row_host.RowHostIssue] {
  let schema_wire = if checked {
    "{\"a\":{\"max_utf8_bytes\":1,\"nullable\":false,\"type\":\"string\"},\"b\":{\"nullable\":false,\"type\":\"number\"},\"embedding\":{\"dimensions\":2,\"element_type\":\"f32\",\"nullable\":false,\"type\":\"vector\"}}"
  } else {
    "{\"a\":{\"max_utf8_bytes\":1,\"nullable\":false,\"type\":\"string\"},\"b\":{\"nullable\":false,\"type\":\"number\"},\"embedding\":{\"dimensions\":2,\"nullable\":false,\"type\":\"vector\"}}"
  }
  let schema_cid = if checked {
    // Independent SHA-256 of the exact checked map, including fixed f32.
    "sha256:5a8be37ab2b6e29c46b4fffb85022ff8642f6152897b75a7eec858392ded4f3d"
  } else {
    // Retain the original incomplete declaration as a typed refusal control.
    "sha256:a08bd3260a45f5089c6ab67175b8d99836cbe36a6a1c0716341e9eb506281cca"
  }
  @row_host.generate_relation_row_declaration(
    "composite_fixture",
    "composite_fixture",
    "composite_fixture/0.1",
    ["queries", "candidates"].map(resource => {
      resource,
      resource_kind: "table",
      schema_wire,
      schema_cid,
      facts_wire: Some(
        "{\"relation_keys\":{\"candidate_keys\":[[\"b\",\"a\"]]}}",
      ),
      request_schema_wire: None,
      acquisition_wire: None,
    }),
    {
      max_bytes: 200000,
      max_nodes: 20000,
      max_depth: 32,
      max_views: 2,
      max_fields: 3,
    },
  )
}

///|
fn composite_vector_source_preparation_context() -> (
  @program_check.CheckEnvironment,
  @local_input.LocalInputContext,
) raise {
  let declaration = composite_vector_source_test_declaration(true).unwrap()
  let (schemas, capabilities) = @row_host.row_declaration_evidence_members(
    declaration,
  )
  // Reuse the existing Source integration control's Host policy unchanged.
  let policy = "{\"capacity\":{\"max_aggregate_array_items\":10000,\"max_artifact_bytes\":10000,\"max_artifact_rows\":10000,\"max_effect_items\":10000,\"max_graph_input_edges\":10000,\"max_graph_input_nodes\":10000,\"max_graph_output_rows\":10000,\"max_graph_paths\":10000,\"max_infer_items\":10000,\"max_model_input_tokens_per_item\":10000,\"max_model_request_bytes_per_item\":10000,\"max_model_total_duration_ms\":10000,\"max_nested_value_bytes\":10000,\"max_nested_value_depth\":10000,\"max_relation_output_rows\":10000,\"max_temporal_matches_per_key\":10000,\"max_temporal_output_rows\":10000,\"version\":\"actql-capacity-host-policy/0.1\"}}"
  let (wire, original_cid) = declaration_environment(
    [declaration.catalog],
    declaration.contracts,
    declaration.view_bodies,
    [],
    host_policy=policy,
  )
  let body = wire
    .replace(old=",\"evidence_bundle_cid\":\"" + original_cid + "\"", new="")
    .replace(
      old="\"connector_capabilities\":[]",
      new="\"connector_capabilities\":" + by_body(capabilities),
    )
    .replace(
      old="\"schema_snapshots\":[]",
      new="\"schema_snapshots\":" + by_body(schemas),
    )
  let environment_cid = text_cid(body)
  let complete = body.replace(
    old="\"host_policy_profile\":",
    new="\"evidence_bundle_cid\":\"" +
      environment_cid +
      "\",\"host_policy_profile\":",
  )
  // Preserve the first typed Catalog refusal instead of hiding it in the
  // shared fixture's unwrap. The same strict reader and limits still apply.
  match
    @environment.read(
      @utf8.encode(complete),
      environment_cid,
      declaration_limits_for_admission(),
    ) {
    Ok(_) => ()
    Err(issue) =>
      fail("composite Source Catalog read: " + @debug.to_string(issue))
  }
  let catalog = query_catalog_from_wire(complete, expected=environment_cid)
  let environment = @program_check.checking_environment(
    @environment.member_environment(
      @environment.source_request_member(
        @environment.source_request_at(catalog, 0).unwrap(),
      ),
    ),
    { text_time: false, veca: true, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
  let aliases = ["queries", "candidates"].map(resource => {
    let source_ref = "connector://composite_fixture/" + resource + "#records"
    let view = @row_host.row_declaration_view(declaration, source_ref).unwrap()
    "{\"name\":\"" +
    resource +
    "\",\"sourceRef\":\"" +
    view.source_ref +
    "\",\"sourceViewContractCid\":\"" +
    view.view_cid +
    "\",\"schemaContractCid\":\"" +
    view.carrier_schema_cid +
    "\"}"
  })
  let publication = "{\"environmentCid\":\"" +
    environment_cid +
    "\",\"aliases\":[" +
    aliases.join(",") +
    "],\"tableWrites\":[]}"
  let context = @local_input.bind_local_published_input_context(
    environment,
    publication,
    None,
  ).unwrap()
  (environment, context)
}

///|
test "composite Vector Source original JSON SQL and AQL reach strict preparation" {
  assert_true(
    composite_vector_source_test_declaration(false) is Err(InvalidContracts),
  )
  let (environment, context) = composite_vector_source_preparation_context()
  let cases = composite_vector_source_preparation_normal_inputs()
  assert_eq(cases.length(), 5)
  for submitted in cases {
    let original = @local_input.prepare_local_submitted_input(
      submitted,
      environment,
      Some(context),
      @publication_host.client_standard_program_preparation_limits(),
    ).unwrap()
    let prepared = @local_input.local_prepared_program(
      @local_input.local_submitted_preparation_input(original),
    )
    assert_eq(@publication_host.prepared_client_acquisition_count(prepared), 2)
    assert_eq(
      @publication_host.prepared_client_result_name(prepared, 0),
      Some("answer"),
    )
    assert_eq(@publication_host.prepared_client_result_name(prepared, 1), None)
    let schema = @publication_host.issue_prepared_client_result_schema(
      prepared,
      0,
      { max_fields: 1, max_bytes: 10000, max_nodes: 1000, max_depth: 32, },
    ).unwrap()
    assert_eq(
      @execution.relation_schema_wire(schema),
      composite_vector_source_preparation_expected_schema(),
    )
  }
}

///|
test "composite Vector Source reordered role keys refuse before Run admission" {
  let (environment, context) = composite_vector_source_preparation_context()
  let cases = composite_vector_source_preparation_refusal_inputs()
  assert_eq(cases.length(), 2)
  for submitted in cases {
    assert_true(
      @local_input.prepare_local_submitted_input(
        submitted,
        environment,
        Some(context),
        @publication_host.client_standard_program_preparation_limits(),
      )
      is Err(Frontend(QueryLowering(InvalidQuery))),
    )
  }
}
