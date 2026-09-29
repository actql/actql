///|
fn reach_selector_output(
  rows : String,
  start : String,
  max_rows? : Int = 12,
) -> Result[@execution.CompletedOutput, @local_sga.ReachIssue] raise {
  let source_owner = carrier_graph_source_owner_with_rows(rows)
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_reach_owner_with_depth(
    source_owner,
    1,
    "out",
    "2",
    start_json=start,
  )
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
  let input = @graphs.prepare_step_read(owner, 1, 0, graph).unwrap()
  let execution = @local_sga.start_reach(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    input,
    max_rows,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    100,
    1000,
    1000,
    [external],
  ).unwrap()
  let output = finish_reach(execution)
  assert_eq(@local_sga.cleanup_reach(execution), Ok(true))
  assert_true(@graphs.discard_completed(graph))
  output
}

///|
test "Reach explicit selector deduplicates starts and preserves minimum depths" {
  let rows = "[{\"id\":1,\"src\":1,\"dst\":2," +
    "\"node_name\":\"one\",\"weight\":10},{\"id\":2," +
    "\"src\":2,\"dst\":3,\"node_name\":\"two\"," +
    "\"weight\":20},{\"id\":3,\"src\":3,\"dst\":3," +
    "\"node_name\":\"three\",\"weight\":30}]"
  let output = reach_selector_output(rows, "{\"ids\":[2,1,2]}").unwrap()
  assert_eq(@execution.completed_row_count(output), 5)
  for
    (row, start, node, depth) in [
      (0, 1.0, 1.0, 0.0),
      (1, 1.0, 2.0, 1.0),
      (2, 1.0, 3.0, 2.0),
      (3, 2.0, 2.0, 0.0),
      (4, 2.0, 3.0, 1.0),
    ] {
    assert_true(
      @execution.completed_cell(output, row, 3) is Some(Number(s)) && s == start,
    )
    assert_true(
      @execution.completed_cell(output, row, 2) is Some(Number(n)) && n == node,
    )
    assert_true(
      @execution.completed_cell(output, row, 0) is Some(Number(d)) && d == depth,
    )
  }
  assert_true(
    reach_selector_output(rows, "{\"ids\":[1,999]}")
    is Err(@local_sga.ReachStartMissing),
  )
  assert_true(
    reach_selector_output(rows, "{\"ids\":[1,2]}", max_rows=4)
    is Err(@local_sga.ReachOutput(@execution.CaptureLimit)),
  )
}

///|
test "Reach node predicate selects starts without changing reached rows" {
  let rows = "[{\"id\":1,\"src\":1,\"dst\":2," +
    "\"node_name\":\"one\",\"weight\":10},{\"id\":2," +
    "\"src\":2,\"dst\":3,\"node_name\":\"two\"," +
    "\"weight\":20},{\"id\":3,\"src\":3,\"dst\":3," +
    "\"node_name\":\"three\",\"weight\":30}]"
  let output = reach_selector_output(
    rows,
    "{\"where\":{\"eq\":[{\"field\":\"node_name\"}," +
    "{\"literal\":\"one\"}]}}",
  ).unwrap()
  assert_eq(@execution.completed_row_count(output), 3)
  for (row, node, depth) in [(0, 1.0, 0.0), (1, 2.0, 1.0), (2, 3.0, 2.0)] {
    assert_true(
      @execution.completed_cell(output, row, 3) is Some(Number(s)) && s == 1.0,
    )
    assert_true(
      @execution.completed_cell(output, row, 2) is Some(Number(n)) && n == node,
    )
    assert_true(
      @execution.completed_cell(output, row, 0) is Some(Number(d)) && d == depth,
    )
  }
  let empty = reach_selector_output(rows, "{\"where\":{\"literal\":false}}").unwrap()
  assert_eq(@execution.completed_row_count(empty), 0)
}

///|
fn reach_relation_owner(
  source : @lower.BoundPrepared,
  selector : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"graph\":{\"nodes\":{\"from\":\"rows\",\"id\":\"id\"," +
      "\"fields\":[\"node_name\"]},\"edges\":{\"from\":\"rows\"," +
      "\"source\":\"src\",\"target\":\"dst\"," +
      "\"fields\":[\"weight\"]}},\"as\":\"graph\"},{" +
      "\"from\":\"graph\",\"reach\":{\"start\":{" +
      "\"from\":\"selected\",\"id\":\"key\"}," +
      "\"direction\":\"out\",\"max_depth\":2}}]",
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
      (
        "selected",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(selector)),
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
fn reach_relation_output(
  rows : String,
  nullable? : Bool = false,
) -> Result[@execution.CompletedOutput, @local_sga.ReachIssue] raise {
  let source_owner = carrier_graph_components_source_owner()
  let source = carrier_events_source_output(source_owner)
  let selector_owner = carrier_graph_selector_source_owner(rows, nullable~)
  let selector = carrier_events_source_output(selector_owner)
  let owner = reach_relation_owner(source_owner, selector_owner)
  let generated = task_test_generated(owner)
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
  let sequence = prepared_sequence(owner)
  let source_read = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let selector_read = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 1, selector_owner, selector).unwrap(),
    100,
    1000,
  ).unwrap()
  let construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    0,
    [source_read, source_read],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let graph = finish_rows_to_graph(construction)
  assert_eq(@local_bridge.cleanup_rows_to_graph(construction), Ok(true))
  let execution = @local_sga.start_reach(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    1,
    @graphs.prepare_step_read(owner, 1, 0, graph).unwrap(),
    12,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    100,
    1000,
    1000,
    [source_read, selector_read],
  ).unwrap()
  let result = finish_reach(execution)
  assert_eq(@local_sga.cleanup_reach(execution), Ok(true))
  assert_true(@graphs.discard_completed(graph))
  result
}

///|
test "Reach Relation selector uses retained values and rejects invalid identities" {
  let output = reach_relation_output("[{\"key\":2},{\"key\":1},{\"key\":2}]").unwrap()
  assert_eq(@execution.completed_row_count(output), 6)
  for
    (row, start, node) in [
      (0, 1.0, 1.0),
      (1, 1.0, 2.0),
      (2, 1.0, 3.0),
      (3, 2.0, 1.0),
      (4, 2.0, 2.0),
      (5, 2.0, 3.0),
    ] {
    assert_true(
      @execution.completed_cell(output, row, 3) is Some(Number(s)) && s == start,
    )
    assert_true(
      @execution.completed_cell(output, row, 2) is Some(Number(n)) && n == node,
    )
  }
  assert_eq(
    @execution.completed_row_count(reach_relation_output("[]").unwrap()),
    0,
  )
  assert_true(
    reach_relation_output("[{\"key\":null}]", nullable=true)
    is Err(@local_sga.ReachKeyOrder(@admitted.InvalidKey)),
  )
  assert_true(
    reach_relation_output("[{\"key\":999}]")
    is Err(@local_sga.ReachStartMissing),
  )
}

///|
test "Reach selector cancellation retains the Graph and releases private work" {
  let source_owner = carrier_graph_components_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_reach_owner_with_depth(
    source_owner,
    1,
    "out",
    "2",
    start_json="{\"ids\":[2,1]}",
  )
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
  let control = @bounded.control()
  let execution = @local_sga.start_reach(
    control,
    task_test_completion(owner),
    sequence,
    1,
    @graphs.prepare_step_read(owner, 1, 0, graph).unwrap(),
    12,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    100,
    1000,
    1000,
    [external],
  ).unwrap()
  assert_true(
    @local_sga.advance_reach(execution, 1).unwrap()
    is @local_sga.ReachContinue(..),
  )
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_sga.advance_reach(execution, 1).unwrap()
    is @local_sga.ReachStopped(_, ..),
  )
  assert_true(@local_sga.reach_cleanup_pending(execution))
  assert_eq(@local_sga.cleanup_reach(execution), Ok(true))
  assert_false(@local_sga.reach_cleanup_pending(execution))
  assert_true(@graphs.discard_completed(graph))
  assert_true(@execution.producer_read_available(external))
}
