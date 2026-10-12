///|
let evidence = "sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904"

///|
let environment_wire : String =
  #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}

///|
fn environment() -> @checked.CheckEnvironment {
  @host.admit_client_check_environment(
    environment_wire,
    evidence,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
}

///|
fn bindings(wire : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: 1024,
      max_nodes: 64,
      max_depth: 8,
    }).unwrap(),
    {
      max_nodes: 64,
      max_depth: 8,
      max_string_bytes: 1024,
      max_total_string_bytes: 1024,
    },
  ).unwrap()
}

///|
let program : String =
  #|{"version":"actql/0.1","id":"python.local.structured","stages":[{"id":"seed","inputs":{},"steps":[{"values":{"schema":{"n":{"type":"number","nullable":false}},"rows":[{"n":1}]},"as":"data"}],"results":{"rows":{"from":"data","fields":["n"]}}},{"id":"compute","inputs":{"seed":{"result":{"stage":"seed","result":"rows"}}},"steps":[{"derive":{"value":"n + 1"},"as":"derived"},{"select":["value"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["value"]}}}],"results":{"answer":{"from":{"stage":"compute","result":"rows"}}}}

///|
test "structured and AQL inputs preserve the checked DAG and Result inventory" {
  let environment = environment()
  let context = bind_local_input_context(environment, [], "python.local.text").unwrap()
  let text = "WITH seed AS (SELECT 1 AS n) FROM seed |> EXTEND n + 1 AS value |> SELECT value |> RESULT answer"
  // The structured input has two Units; the query script has one Unit with
  // several steps. Physical segmentation belongs to the existing DAG Owner.
  for
    (input, result_unit, minimum_tasks) in [
      (Program(program), 1, 2),
      (Aql(text), 0, 1),
    ] {
    let prepared = prepare_local_input(
      input,
      environment,
      None,
      Some(context),
      @host.client_standard_program_preparation_limits(),
    ).unwrap()
    let graph = @host.prepared_client_graph(prepared)
    assert_true(@strategy.graph_task_count(graph) >= minimum_tasks)
    assert_eq(@host.prepared_client_result_count(prepared), 1)
    assert_eq(@host.prepared_client_result_name(prepared, 0), Some("answer"))
    let result_task = @strategy.graph_result_task(graph, 0).unwrap()
    assert_eq(
      @strategy.graph_task_unit_index(graph, result_task),
      Some(result_unit),
    )
  }
}

///|
test "an installed context cannot be carried into a changed environment" {
  let previous = environment()
  let context = bind_local_input_context(previous, [], "python.local.text").unwrap()
  // Independently hashed with Python hashlib over the sorted canonical input
  // object without evidence_bundle_cid, after setting max_artifact_rows=1001.
  let changed_evidence = "sha256:f0a3b3a9d3f35f21d9aa9c6b2da457153d66725222581c33574669ad7a4df18b"
  let changed = @host.admit_client_check_environment(
    environment_wire
    .replace(old="\"max_artifact_rows\":1000", new="\"max_artifact_rows\":1001")
    .replace(old=evidence, new=changed_evidence),
    changed_evidence,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  assert_true(
    @checked.checking_environment_cid(previous) !=
    @checked.checking_environment_cid(changed),
  )
  assert_true(
    prepare_local_input(
      Aql("SELECT 1 AS n"),
      changed,
      None,
      Some(context),
      @host.client_standard_program_preparation_limits(),
    )
    is Err(ForeignEnvironment),
  )
}

///|
test "AQL failures keep original UTF-8 provenance across Unicode and CRLF" {
  let environment = environment()
  let context = bind_local_input_context(environment, [], "python.local.text").unwrap()
  let issue = match
    prepare_local_input(
      Aql("/*😀*/\r\nSELECT missing"),
      environment,
      None,
      Some(context),
      @host.client_standard_program_preparation_limits(),
    ) {
    Err(Frontend(issue)) => issue
    _ => fail("Expected the original unresolved column")
  }
  let origin = @frontend.unknown_column_origin(issue).unwrap()
  let span = @origin.span(origin)
  assert_eq(@origin.kind(origin), @origin.Authored)
  assert_eq(span.start_byte, 17)
  assert_eq(span.end_byte, 24)
}

///|
test "AQL requires the installed query context and rejects retired syntax" {
  let environment = environment()
  let limits = @host.client_standard_program_preparation_limits()
  assert_true(
    prepare_local_input(Aql("SELECT 1 AS n"), environment, None, None, limits)
    is Err(Frontend(MissingQueryContext)),
  )
  let context = bind_local_input_context(environment, [], "python.local.text").unwrap()
  assert_true(
    prepare_local_input(
      Aql("PROGRAM 'legacy' {}"),
      environment,
      None,
      Some(context),
      limits,
    )
    is Err(Frontend(WrongQueryForm)),
  )
}

///|
test "bound input preparation preserves missing NULL and wrong-type distinctions" {
  let document =
    #|{"version":"actql/0.1","id":"python.local.bindings","params":{"x":{"type":"number","nullable":false}},"stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"n":{"type":"number","nullable":false}},"rows":[{"n":1}]},"as":"data"},{"derive":{"value":"n + $x"},"as":"derived"}],"results":{"rows":{"from":"derived","fields":["value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let environment = environment()
  let limits = @host.client_standard_program_preparation_limits()
  for supplied in [None, Some(bindings("{}"))] {
    assert_true(
      prepare_local_input(
        Program(document),
        environment,
        supplied,
        None,
        limits,
      )
      is Err(Preparation(NeedsInputs(_))),
    )
  }
  for wire in ["{\"x\":null}", "{\"x\":\"wrong\"}"] {
    assert_true(
      prepare_local_input(
        Program(document),
        environment,
        Some(bindings(wire)),
        None,
        limits,
      )
      is Err(Preparation(Check(_))),
    )
  }
  assert_true(
    prepare_local_input(
      Program(document),
      environment,
      Some(bindings("{\"x\":2}")),
      None,
      limits,
    )
    is Ok(_),
  )
}

///|
test "exhausted common Checker work is not a prepared Local input" {
  let limits = @host.client_standard_program_preparation_limits()
  let limited = {
    ..limits,
    checking: {
      ..limits.checking,
      compilation: { ..limits.checking.compilation, work: 1, },
    },
  }
  assert_true(
    prepare_local_input(Program(program), environment(), None, None, limited)
    is Err(Preparation(_)),
  )
}
