///|
fn preparation_environment() -> @checked.CheckEnvironment {
  @host.admit_client_check_environment(
    (
      #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
    ),
    "sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
}

///|
fn preparation_values_document() -> String {
  (
    #|{"version":"actql/0.1","id":"client-values","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1},{"id":2}]},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"source","result":"rows"}}}}
  )
}

///|
test "Native Local ingress keeps the ordinary Program owner and named Result" {
  let environment = preparation_environment()
  guard prepare_native_client_program(
      preparation_values_document(),
      Json,
      environment,
      None,
      None,
      [],
      @host.client_standard_effect_computation_limits(),
    )
    is Ok(Computation(prepared)) else {
    fail("ordinary Local preparation failed")
  }
  assert_eq(@host.prepared_client_result_count(prepared), 1)
  assert_eq(@host.prepared_client_result_name(prepared, 0), Some("answer"))
  let row = @host.issue_prepared_client_result_row_contract(
    prepared, 0, 0, 10000, 1000, 20,
  ).unwrap()
  assert_eq(
    @host.client_result_row_contract_wire(row),
    "{\"additional_properties\":false,\"fields\":{\"id\":{\"nullable\":false,\"type\":\"number\"}},\"nullable\":false,\"type\":\"object\"}",
  )
}

///|
test "Native Local SQL uses the existing frontend and common checker" {
  let environment = preparation_environment()
  let context = @frontend.bind_query_context(
    [],
    @checked.checking_environment_cid(environment),
  ).unwrap()
  guard prepare_native_client_program(
      "SELECT 1 AS id",
      Sql,
      environment,
      None,
      Some(context),
      [],
      @host.client_standard_effect_computation_limits(),
    )
    is Ok(Computation(prepared)) else {
    fail("ordinary SQL preparation failed")
  }
  assert_eq(@host.prepared_client_result_count(prepared), 1)
  assert_true(
    prepare_native_client_program(
      "SELECT missing AS id",
      Sql,
      environment,
      None,
      Some(context),
      [],
      @host.client_standard_effect_computation_limits(),
    )
    is Err(Frontend(_)),
  )
}

///|
test "Native Local ingress cannot fall back from text to a JSON Program" {
  assert_true(
    prepare_native_client_program(
      preparation_values_document(),
      Text,
      preparation_environment(),
      None,
      None,
      [],
      @host.client_standard_effect_computation_limits(),
    )
    is Err(Frontend(_)),
  )
}

///|
test "Native Local Effect inventory selects its existing owner before checking" {
  let document = preparation_values_document().replace(
    old="\"results\":{\"rows\":{\"from\":\"selected\",\"fields\":[\"id\"]}}",
    new="\"results\":{\"rows\":{\"from\":\"selected\",\"fields\":[\"id\"]}},\"effects\":{\"save\":{\"create\":{\"target\":\"connector://missing/rows\",\"mapping\":\"mapping:missing.rows\",\"from\":{\"result\":\"rows\"}}}}",
  )
  assert_true(
    prepare_native_client_program(
      document,
      Json,
      preparation_environment(),
      None,
      None,
      [],
      @host.client_standard_effect_computation_limits(),
    )
    is Err(EffectComputation(_)),
  )
}

///|
test "Native Local preserves caller strings and supplied-value distinctions" {
  let document = preparation_values_document()
    .replace(old="\"type\":\"number\"", new="\"type\":\"string\"")
    .replace(old="{\"id\":1}", new="{\"id\":\"e\\u0301\\r\\n\"}")
    .replace(old="{\"id\":2}", new="{\"id\":\"é\\n\"}")
  guard prepare_native_client_program(
      document,
      Json,
      preparation_environment(),
      None,
      None,
      [],
      @host.client_standard_effect_computation_limits(),
    )
    is Ok(Computation(prepared)) else {
    fail("string values were not prepared")
  }
  let semantic = @host.emit_prepared_client_semantic_program(
    prepared, 10000, 1000, 20,
  ).unwrap()
  let value = @source.parse_json_bytes_preserving(@utf8.encode(semantic), {
    max_input_bytes: 10000,
    max_nodes: 1000,
    max_depth: 20,
  }).unwrap()
  let root = @decode.admit(value, {
    max_nodes: 1000,
    max_depth: 20,
    max_string_bytes: 10000,
    max_total_string_bytes: 10000,
  }).unwrap()
  let stages = @decode.elements(
    @decode.required(@decode.open_object(root).unwrap(), "stages").unwrap(),
  ).unwrap()
  let steps = @decode.elements(
    @decode.required(@decode.open_object(stages[0]).unwrap(), "steps").unwrap(),
  ).unwrap()
  let values = @decode.open_object(
    @decode.required(@decode.open_object(steps[0]).unwrap(), "values").unwrap(),
  ).unwrap()
  let rows = @decode.elements(@decode.required(values, "rows").unwrap()).unwrap()
  assert_eq(
    @decode.text(
      @decode.required(@decode.open_object(rows[0]).unwrap(), "id").unwrap(),
    ).unwrap(),
    "e\u{0301}\r\n",
  )
  assert_eq(
    @decode.text(
      @decode.required(@decode.open_object(rows[1]).unwrap(), "id").unwrap(),
    ).unwrap(),
    "é\n",
  )
}
