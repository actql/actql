///|
fn carrier_graph_source_owner() -> @lower.BoundPrepared {
  let checked = @pipeline.check(
    input_cursor(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}," +
      "\"src\":{\"type\":\"number\",\"nullable\":false}," +
      "\"dst\":{\"type\":\"number\",\"nullable\":false}," +
      "\"node_name\":{\"type\":\"string\",\"nullable\":false}," +
      "\"weight\":{\"type\":\"number\",\"nullable\":false}}," +
      "\"rows\":[{\"id\":1,\"src\":1,\"dst\":2," +
      "\"node_name\":\"first\",\"weight\":10},{\"id\":2," +
      "\"src\":2,\"dst\":1,\"node_name\":\"second\"," +
      "\"weight\":20}]},\"as\":\"source\"}]",
    ),
    [],
    None,
    None,
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn carrier_graph_open_endpoint_source_owner() -> @lower.BoundPrepared {
  let checked = @pipeline.check(
    input_cursor(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\"," +
      "\"nullable\":false},\"src\":{\"type\":\"number\"," +
      "\"nullable\":false},\"dst\":{\"type\":\"number\"," +
      "\"nullable\":false},\"node_name\":{\"type\":\"string\"," +
      "\"nullable\":false},\"weight\":{\"type\":\"number\"," +
      "\"nullable\":false}},\"rows\":[{\"id\":1,\"src\":1," +
      "\"dst\":2,\"node_name\":\"first\",\"weight\":10}]}," +
      "\"as\":\"source\"}]",
    ),
    [],
    None,
    None,
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn local_carrier_graph_program() -> String {
  let schema = "{\"id\":{\"type\":\"number\",\"nullable\":false}," +
    "\"src\":{\"type\":\"number\",\"nullable\":false}," +
    "\"dst\":{\"type\":\"number\",\"nullable\":false}," +
    "\"node_name\":{\"type\":\"string\",\"nullable\":false}," +
    "\"weight\":{\"type\":\"number\",\"nullable\":false}}"
  let rows = "[{\"id\":1,\"src\":1,\"dst\":2," +
    "\"node_name\":\"first\",\"weight\":10},{\"id\":2," +
    "\"src\":2,\"dst\":1,\"node_name\":\"second\"," +
    "\"weight\":20}]"
  "{\"version\":\"actql/0.1\",\"id\":\"p\",\"params\":" +
  "{\"minimum\":{\"type\":\"number\",\"nullable\":false}}," +
  "\"stages\":[{\"id\":\"a\",\"inputs\":{\"remote\":{" +
  "\"connector\":\"crm/main\",\"resource\":\"r\"}},\"steps\":[{" +
  "\"filter\":\"id > $minimum\",\"as\":\"filtered\"},{" +
  "\"select\":[\"id\"],\"as\":\"captured\"}],\"results\":{" +
  "\"r\":{\"from\":\"captured\",\"fields\":[\"id\"]}}},{" +
  "\"id\":\"values\",\"inputs\":{},\"steps\":[{\"values\":{" +
  "\"schema\":" +
  schema +
  ",\"rows\":" +
  rows +
  "},\"as\":\"out\"}]," +
  "\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\"," +
  "\"src\",\"dst\",\"node_name\",\"weight\"]}}},{\"id\":\"graph\"," +
  "\"inputs\":{\"rows\":{\"result\":{\"stage\":\"values\"," +
  "\"result\":\"r\"}}},\"steps\":[{\"graph\":{\"nodes\":{" +
  "\"from\":\"rows\",\"id\":\"id\",\"fields\":[\"node_name\"]}," +
  "\"edges\":{\"from\":\"rows\",\"source\":\"src\"," +
  "\"target\":\"dst\",\"fields\":[\"weight\"]}},\"as\":\"g\"},{" +
  "\"node_rows\":true,\"as\":\"out\"}],\"results\":{\"r\":{" +
  "\"from\":\"out\",\"fields\":[\"id\",\"node_name\"]}}},{" +
  "\"id\":\"consumer_a\",\"inputs\":{\"x\":{\"result\":{" +
  "\"stage\":\"graph\",\"result\":\"r\"}}},\"steps\":[{" +
  "\"select\":[\"id\",\"node_name\"],\"as\":\"out\"}],\"results\":{" +
  "\"r\":{\"from\":\"out\",\"fields\":[\"id\",\"node_name\"]}}},{" +
  "\"id\":\"consumer_b\",\"inputs\":{\"x\":{\"result\":{" +
  "\"stage\":\"graph\",\"result\":\"r\"}}},\"steps\":[{" +
  "\"select\":[\"node_name\"],\"as\":\"out\"}],\"results\":{\"r\":{" +
  "\"from\":\"out\",\"fields\":[\"node_name\"]}}}],\"results\":{" +
  "\"source\":{\"from\":{\"stage\":\"a\",\"result\":\"r\"}}}}"
}

///|
fn local_carrier_graph_environment(
  original : @environment.WireEnvironment,
) -> @environment.WireEnvironment raise {
  let writer = @encode.writer(1000000, 100000, 100)
  @environment.emit(original, writer)
  let body = @encode.finish(writer)
    .replace(
      old="\"evidence_bundle_cid\":\"" + @environment.cid(original) + "\",",
      new="",
    )
    .replace(
      old="\"max_graph_input_edges\":",
      new="\"max_graph_construction_edges\":10000," +
        "\"max_graph_construction_input_rows\":10000," +
        "\"max_graph_construction_nodes\":10000," +
        "\"max_graph_input_edges\":",
    )
  let cid = "sha256:" + @sha.hex(@utf8.encode(body))
  @environment.read(
    @utf8.encode(
      body.replace(
        old="\"host_policy_profile\":",
        new="\"evidence_bundle_cid\":\"" + cid + "\",\"host_policy_profile\":",
      ),
    ),
    cid,
    {
      max_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 100,
      max_members: 1000,
    },
  ).unwrap()
}

///|
fn carrier_graph_owner(
  source : @lower.BoundPrepared,
  projection? : String = "node_rows",
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"graph\":{\"nodes\":{\"from\":\"rows\",\"id\":\"id\"," +
      "\"fields\":[\"node_name\"]},\"edges\":{\"from\":\"rows\"," +
      "\"source\":\"src\",\"target\":\"dst\"," +
      "\"fields\":[\"weight\"]}},\"as\":\"graph\"}," +
      "{\"" +
      projection +
      "\":true}]",
    ),
    [
      (
        "rows",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(source)),
            @pipeline.Step(0),
          ).unwrap(),
        ),
      ),
    ],
    None,
    Some(input_cursor("\"rows\"")),
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn carrier_graph_storage_limits() -> @graph_storage.Limits {
  {
    max_input_rows: 20,
    max_nodes: 10,
    max_edges: 10,
    max_value_bytes: 1000,
    max_total_value_bytes: 10000,
    max_retained_value_bytes: 10000,
    max_value_nodes: 100,
    max_value_depth: 10,
    max_contract_work: 1000,
    max_work: 1000,
    max_workspace_slots: 1000,
  }
}

///|
fn finish_rows_to_graph(
  execution : @local_bridge.RowsToGraphExecution,
) -> @graphs.Completed {
  while true {
    match @local_bridge.advance_rows_to_graph(execution, 1).unwrap() {
      @local_bridge.Continue(..) => ()
      @local_bridge.Complete(output, ..) => return output
      @local_bridge.Failed(_, ..) => abort("rows-to-graph failed")
      @local_bridge.Stopped(_, ..) => abort("rows-to-graph stopped")
    }
  }
  abort("unreachable")
}

///|
fn finish_graph_to_rows(
  execution : @local_bridge.GraphRowsExecution,
) -> @execution.CompletedOutput {
  while true {
    match @local_bridge.advance_graph_to_rows(execution, 1).unwrap() {
      @local_bridge.Continue(..) => ()
      @local_bridge.Complete(output, ..) => return output
      @local_bridge.Failed(issue, ..) =>
        match issue {
          @local_bridge.InvalidGraphKernel => abort("invalid graph kernel")
          @local_bridge.GraphInputUnavailable => abort("graph unavailable")
          @local_bridge.InvalidGraphRecord(_) => abort("invalid graph record")
          @local_bridge.GraphWorkspaceLimit => abort("graph workspace")
          @local_bridge.GraphRelationOutput(_) => abort("graph relation output")
          @local_bridge.GraphCompletion(_) => abort("graph completion")
          @local_bridge.GraphExecution(_) => abort("graph execution")
        }
      @local_bridge.Stopped(_, ..) => abort("graph-to-rows stopped")
    }
  }
  abort("unreachable")
}

///|
fn carrier_graph_consumer_output(
  producer : @lower.BoundPrepared,
  output : @execution.CompletedOutput,
  projection : String,
) -> @execution.CompletedOutput raise {
  let consumer = typed_receiver(producer, projection, target=@pipeline.Step(1))
  let binding = @execution.bind_completed_input(consumer, 0, producer, output).unwrap()
  let result = @execution.execute_generated_sequence(
    compute_test_sequence(consumer),
    [],
    compute_test_limits(),
    produced=[binding],
  ).unwrap()
  @execution.completed_output(result, @pipeline.Step(0)).unwrap()
}

///|
test "bounded Graph bridge preserves repeated positions and two consumers" {
  let source_owner = carrier_graph_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_owner(source_owner)
  let sequence = prepared_sequence(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  assert_true(
    @local_bridge.start_rows_to_graph(
      @bounded.control(),
      sequence,
      0,
      [external, external],
      carrier_graph_storage_limits(),
      4096L,
      9,
      fn() { true },
    )
    is Err(@local_bridge.GraphWorkspaceLimit),
  )
  let construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    0,
    [external, external],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let graph = finish_rows_to_graph(construction)
  assert_eq(@local_bridge.cleanup_rows_to_graph(construction), Ok(true))
  let projection_input = @graphs.prepare_step_read(owner, 1, 0, graph).unwrap()
  let projection = @local_bridge.start_graph_to_rows(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    projection_input,
    10,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    100,
    1000,
    1000,
    [external],
  ).unwrap()
  let rows = finish_graph_to_rows(projection)
  assert_eq(@local_bridge.cleanup_graph_to_rows(projection), Ok(true))
  assert_true(@graphs.discard_completed(graph))
  assert_eq(@execution.completed_row_count(rows), 2)
  assert_true(@execution.completed_output_matches_inputs(rows, [external]))
  let first = carrier_graph_consumer_output(
    owner, rows, "[{\"select\":[\"id\",\"node_name\"]}]",
  )
  let second = carrier_graph_consumer_output(
    owner, rows, "[{\"select\":[\"node_name\"]}]",
  )
  assert_true(@execution.completed_cell(first, 0, 0) is Some(Number(1.0)))
  assert_true(@execution.completed_cell(first, 1, 1) is Some(Text("second")))
  assert_true(@execution.completed_cell(second, 0, 0) is Some(Text("first")))
  assert_true(@execution.completed_output_available(rows))
}

///|
test "bounded Graph edge projection survives Graph reclamation" {
  let source_owner = carrier_graph_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_owner(source_owner, projection="edge_rows")
  let sequence = prepared_sequence(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    0,
    [external, external],
    carrier_graph_storage_limits(),
    4096L,
    10,
    fn() { true },
  ).unwrap()
  let graph = finish_rows_to_graph(construction)
  assert_eq(@local_bridge.cleanup_rows_to_graph(construction), Ok(true))
  let projection_input = @graphs.prepare_step_read(owner, 1, 0, graph).unwrap()
  let projection = @local_bridge.start_graph_to_rows(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    projection_input,
    10,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    100,
    1000,
    1000,
    [external],
  ).unwrap()
  let rows = finish_graph_to_rows(projection)
  assert_eq(@local_bridge.cleanup_graph_to_rows(projection), Ok(true))
  assert_true(@graphs.discard_completed(graph))
  assert_eq(@execution.completed_row_count(rows), 2)
  let first = carrier_graph_consumer_output(
    owner, rows, "[{\"select\":[\"src\",\"dst\",\"weight\"]}]",
  )
  let second = carrier_graph_consumer_output(
    owner, rows, "[{\"select\":[\"weight\",\"src\"]}]",
  )
  assert_true(@execution.completed_cell(first, 0, 0) is Some(Number(1.0)))
  assert_true(@execution.completed_cell(first, 0, 1) is Some(Number(2.0)))
  assert_true(@execution.completed_cell(first, 1, 2) is Some(Number(20.0)))
  assert_true(@execution.completed_cell(second, 0, 0) is Some(Number(10.0)))
  assert_true(@execution.completed_output_available(rows))
}

///|
test "explicit Graph construction closes absent edge endpoints" {
  let source_owner = carrier_graph_open_endpoint_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_owner(source_owner, projection="edge_rows")
  let sequence = prepared_sequence(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    0,
    [external, external],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let graph = finish_rows_to_graph(construction)
  assert_eq(@local_bridge.cleanup_rows_to_graph(construction), Ok(true))
  let projection_input = @graphs.prepare_step_read(owner, 1, 0, graph).unwrap()
  let projection = @local_bridge.start_graph_to_rows(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    projection_input,
    10,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    100,
    1000,
    1000,
    [external],
  ).unwrap()
  let rows = finish_graph_to_rows(projection)
  assert_eq(@local_bridge.cleanup_graph_to_rows(projection), Ok(true))
  assert_true(@graphs.discard_completed(graph))
  assert_eq(@execution.completed_row_count(rows), 0)
}

///|
test "Graph bridge cancellation stops before cleanup and preserves inputs" {
  let source_owner = carrier_graph_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_owner(source_owner)
  let sequence = prepared_sequence(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let control = @bounded.control()
  let construction = @local_bridge.start_rows_to_graph(
    control,
    sequence,
    0,
    [external, external],
    carrier_graph_storage_limits(),
    4096L,
    10,
    fn() { true },
  ).unwrap()
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_bridge.advance_rows_to_graph(construction, 1).unwrap()
    is @local_bridge.Stopped(_, ..),
  )
  assert_true(@local_bridge.rows_to_graph_cleanup_pending(construction))
  assert_eq(@local_bridge.cleanup_rows_to_graph(construction), Ok(true))
  assert_false(@local_bridge.rows_to_graph_cleanup_pending(construction))
  assert_true(@execution.producer_read_available(external))
}

///|
test "registered Graph provider expands repeated semantic input positions" {
  let source_owner = carrier_graph_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_owner(source_owner)
  let generated = task_test_generated(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let provider = @local_sga_provider.provider(
    carrier_graph_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      generated,
      dispatch_test_limits().local_execution,
      dispatch_test_limits().guards,
    ).unwrap(),
  )
  assert_true(@local_connector.managed_provider_accepts(provider, generated))
  let execution = @local_connector.start_managed_provider(
    provider,
    generated,
    [external],
    10,
    1000,
  ).unwrap()
  let mut output = None
  while output is None {
    match @local_connector.advance_managed_provider(execution, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.Complete(value, ..) => output = Some(value)
      @local_connector.Failed(_, ..) => fail("Graph provider failed")
      @local_connector.Stopped(..) => fail("Graph provider stopped")
    }
  }
  let completed = output.unwrap()
  assert_eq(@execution.completed_row_count(completed), 2)
  assert_true(@execution.completed_output_matches_inputs(completed, [external]))
  assert_true(@local_connector.managed_provider_stopped(execution))
  assert_true(
    @local_connector.cleanup_managed_provider(execution).unwrap_or(false),
  )
  assert_true(@execution.completed_output_available(completed))
  assert_true(@execution.producer_read_available(external))
}

///|
test "standard Host runs bounded Graph bridge with two consumers" {
  let (run, issuer) = captured_graph_fixture(local_carrier_graph_chain=true)
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let sequences = dispatch_test_generated(run)
  let cleanup_attempts = Ref(0)
  let provider = delayed_cleanup_provider(
    @local_sga_provider.provider(
      carrier_graph_storage_limits(),
      4096L,
      @execution.generated_sequence_capacity(
        sequences[1],
        limits.local_execution,
        limits.guards,
      ).unwrap(),
    ),
    cleanup_attempts,
  )
  let modules = @builtin.configure_compute_modules(
    @host_driver.open_dispatch_driver(run),
    registry,
    1,
    _ => @strategy.RunIssue::ForeignCandidate,
    with_local=Some(
      (
        @connector.capability_registration_at(registry, 0).unwrap(),
        {
          sequences,
          managed_providers: [provider],
          managed_capacity: limits.capacity,
          execution: limits.local_execution,
          measurement: limits.guards,
          max_work: limits.candidate_work,
        },
        _ => @strategy.RunIssue::ForeignCandidate,
        _ => @strategy.RunIssue::ForeignCandidate,
      ),
    ),
  ).unwrap()
  let installed = @builtin.configured_local_module(modules).unwrap()
  @local_driver.configure_local_retained_inputs(
    installed,
    {
      max_rows: 100,
      values: limits.local_execution.rows.input_values,
      wire: {
        ..retained_attempt_wire_limits(),
        max_bytes: 3000,
        max_nodes: 300,
        max_depth: 10,
        max_columns: 10,
      },
      row: {
        max_bytes: 3000,
        max_nodes: 300,
        max_depth: 10,
        max_text_bytes: 3000,
      },
      max_batch_bytes: 3000,
    },
    None,
  ).unwrap()

  let values_live = Ref(true)
  let (values_ops, values) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    values_live,
  )
  let values_rows = local_managed_test_rows(values_ops)
  let graph_live = Ref(true)
  let (graph_ops, graph) = run_local_managed_test_task(
    installed,
    run,
    2,
    [values],
    [values_rows],
    2,
    graph_live,
  )
  let graph_rows = local_managed_test_rows(graph_ops)
  assert_eq(graph_rows.length(), 2)
  assert_true(graph_rows[0].contains("\"id\":1"))
  assert_true(graph_rows[1].contains("\"node_name\":\"second\""))

  let first_live = Ref(true)
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    3,
    [graph],
    [graph_rows],
    3,
    first_live,
  )
  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    4,
    [graph],
    [graph_rows],
    4,
    second_live,
  )
  assert_eq(local_managed_test_rows(first_ops).length(), 2)
  assert_eq(local_managed_test_rows(second_ops).length(), 2)

  first_live.val = false
  @strategy.close_captured_task_output(run, 3)
  (first_ops.close)()
  (first_ops.cleanup_refresh)() |> ignore
  assert_false(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(graph))

  second_live.val = false
  @strategy.close_captured_task_output(run, 4)
  (second_ops.close)()
  (second_ops.cleanup_refresh)() |> ignore
  graph_live.val = false
  @strategy.close_captured_task_output(run, 2)
  (graph_ops.close)()
  assert_false((graph_ops.cleanup_refresh)())
  assert_true((graph_ops.cleanup_refresh)())
  assert_eq(cleanup_attempts.val, 2)
  values_live.val = false
  @strategy.close_captured_task_output(run, 1)
  (values_ops.close)()
  (values_ops.cleanup_refresh)() |> ignore
  @strategy.stop_captured_dag(run)
  @strategy.close_captured_task_output(run, 0)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
  @mock.close_mock_query_issuer(issuer)
}
