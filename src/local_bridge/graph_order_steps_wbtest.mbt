// Real-owner regression fixtures for charged Graph ordering.
// Registered contract bodies are generated in graph_order_contracts_wbtest.mbt.

///|
fn graph_order_carrier_events_source_output(
  owner : @lower.BoundPrepared,
) -> @execution.CompletedOutput raise {
  let sequence = graph_order_prepared_sequence(owner)
  let node = @lower.node_at(@lower.bound_preparation(owner), 0).unwrap()
  let generated = @execution.prepare_generated_sequence(
    graph_order_registered_relation_contracts(),
    sequence,
    [],
    [@lower.node_id(node)],
    100000,
    10000,
  ).unwrap()
  let result = @execution.execute_generated_sequence(generated, [], {
    rows: graph_order_run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  @execution.completed_output(result, @pipeline.Step(0)).unwrap()
}

///|
priv struct GraphOrderFixture {
  active : EventsToRowsExecution
  source : GraphRowsSource
  input : @graph.ProducerRead
  graph : @graph.Completed
  construction : RowsToGraphExecution
  control : @bounded.Control
}

///|
fn graph_order_fixture(work? : Int = 10000) -> GraphOrderFixture raise {
  let nodes = graph_order_keyed_source_owner(
    "{\"person_key\":{\"type\":\"number\",\"nullable\":false}}", "[{\"person_key\":3},{\"person_key\":1},{\"person_key\":2}]",
  )
  let empty = graph_order_keyed_source_owner(
    "{\"person_key\":{\"type\":\"number\",\"nullable\":false}}", "[]",
  )
  let graph_owner = graph_order_keyed_bridge_owner(
    nodes,
    empty,
    body=Some(
      (
        #|[{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["person_key"],"labels":[]},{"name":"M","from":"edges","key":["person_key"],"labels":[]}],"edges":[]},"as":"g"}]
      ),
    ),
  )
  let construction = start_rows_to_property_graph(
    @bounded.control(),
    graph_order_prepared_sequence(graph_owner),
    0,
    graph_order_keyed_bridge_inputs(graph_owner, nodes, empty),
    { ..graph_order_carrier_graph_storage_limits(), max_work: 100000, },
    8192L,
    10000,
    () => true,
  ).unwrap()
  guard graph_order_keyed_bridge_terminal(construction, max_fixture_steps=10000)
    is Complete(graph, ..) else {
    fail("three-node Graph fixture construction")
  }
  let owner = graph_order_keyed_graph_receiver(
    graph_owner,
    body="[{\"node_rows\":true}]",
  )
  let input = @graph.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
  let storage = @graph.producer_read_storage(input).unwrap()
  guard @graph_storage.carrier(storage) is @carrier.GraphValue(carrier) else {
    fail("Graph storage carrier")
  }
  let limits : @execution.ValueLimits = {
    max_nodes: 1000,
    max_text_bytes: 10000,
    max_depth: 20,
    max_work: 10000,
  }
  let source : GraphRowsSource = {
    source: StoredGraph(storage),
    definition: @carrier.graph_property_definition(carrier),
    selected_definition: None,
    selected_label: None,
    selection_label_index: 0,
    selection_name_offset: 0,
    edge: false,
    limits,
    label_builder: None,
    label_recheck: None,
    label_workspace: 0,
    label_reserved: 0,
    label_index: 0,
    label_bytes: limits.max_text_bytes,
    order_keys: [],
    order: None,
    order_slots: 128,
  }
  let schema = @lower.preparation_schema_at(
    @lower.bound_preparation(owner),
    @pipeline.Step(0),
  ).unwrap()
  let control = @bounded.control()
  let active = start_storage_to_rows(
    control,
    graph_order_task_test_completion(owner),
    owner,
    @pipeline.Step(0),
    GraphRows(source),
    fn() { @graph.producer_read_available(input) },
    None,
    schema,
    3,
    limits,
    128,
    10000,
    None,
    Some(work),
    trusted_inputs=Some([
      @execution.trusted_output_carrier_input(
        @graph.producer_read_carrier_reference(input),
      ),
    ]),
  ).unwrap()
  { active, source, input, graph, construction, control, }
}

///|
fn graph_order_collect(fixture : GraphOrderFixture) -> Unit raise {
  for expected in 1..<=3 {
    guard advance_events_to_rows(fixture.active, 1).unwrap()
      is Continue(work~, ..) else {
      fail("Graph key collection stopped")
    }
    assert_eq(work, expected.to_int64())
    assert_eq(fixture.source.order_keys.length(), expected)
    assert_true(fixture.source.order is None)
  }
}

///|
fn graph_order_close(fixture : GraphOrderFixture) -> Unit raise {
  assert_true(cleanup_events_to_rows(fixture.active).unwrap())
  assert_false(cleanup_events_to_rows(fixture.active).unwrap())
  assert_false(events_to_rows_cleanup_pending(fixture.active))
  assert_true(fixture.source.order is None)
  assert_true(fixture.source.order_keys.is_empty())
  assert_true(@graph.producer_read_available(fixture.input))
  assert_true(@graph.completed_available(fixture.graph))
  let storage = @graph.producer_read_storage(fixture.input).unwrap()
  assert_eq(@graph_storage.node_count(storage), 3)
  assert_true(@graph_storage.node_identity(storage, 2) is Some(_))
  assert_true(cleanup_rows_to_graph(fixture.construction).unwrap())
  assert_true(@graph.discard_completed(fixture.graph))
}

///|
test "Graph row order validates later key shapes only in charged initialization" {
  let fixture = graph_order_fixture()
  graph_order_collect(fixture)
  // Fault injection into private sort input, not a reachable malformed public
  // Graph. Production acquisition always produces singleton keys. A sentinel
  // on the LAST key makes eager lookahead observable without timing guesses.
  fixture.source.order_keys[2].push("test-only second component")
  for expected in [4L, 5L] {
    guard advance_events_to_rows(fixture.active, 1).unwrap()
      is Continue(work~, ..) else {
      fail("Graph order inspected a later key before its charged visit")
    }
    assert_eq(work, expected)
    assert_true(fixture.source.order is Some(_))
    assert_eq(@sort.count(fixture.source.order.unwrap()), 0)
  }
  guard advance_events_to_rows(fixture.active, 1).unwrap()
    is Failed(GraphOrder(@sort.InvalidKey), work~, ..) else {
    fail("Graph order did not reject the malformed key at its own visit")
  }
  // The malformed visit reports no invented successful work or publication.
  assert_eq(work, 5L)
  assert_true(advance_events_to_rows(fixture.active, 1) is Err(_))
  graph_order_close(fixture)
}

///|
test "Graph row order cancels before inspecting an unvisited later key" {
  let fixture = graph_order_fixture()
  graph_order_collect(fixture)
  fixture.source.order_keys[2].push("test-only second component")
  guard advance_events_to_rows(fixture.active, 1).unwrap()
    is Continue(work=4L, ..) else {
    fail("Graph order inspected a later key before cancellation")
  }
  assert_true(@bounded.request_cancel(fixture.control))
  assert_true(
    cleanup_events_to_rows(fixture.active)
    is Err(Execution(@bounded.NotStopped)),
  )
  assert_true(fixture.source.order is Some(_))
  assert_eq(fixture.source.order_keys.length(), 3)
  assert_true(
    advance_events_to_rows(fixture.active, 1).unwrap()
    is Stopped(@bounded.Cancelled, work=4L, ..),
  )
  graph_order_close(fixture)
}

///|
test "Graph row order retains three exact rows and independent work across quanta" {
  // The existing one-node fixture's 105 units contain 2 ordering units, so
  // each identically shaped row costs 103. Three key collections cost 3.
  // Sort: 3 initialization + 3 run setup + 6 moves + 2 swaps + 3 extra
  // prefix fragments = 17. Total 3 + 17 + 3*103 = 329, not a sampled run.
  for quantum in [1, 7, 256] {
    let fixture = graph_order_fixture(work=329)
    let mut completed = None
    let mut previous = 0L
    for _ in 0..<1000 {
      match advance_events_to_rows(fixture.active, quantum).unwrap() {
        Continue(work~, ..) => {
          assert_true(work >= previous && work - previous <= quantum.to_int64())
          previous = work
        }
        Complete(output, work~, ..) => {
          assert_eq(work, 329L)
          completed = Some(output)
          break
        }
        _ => fail("three-node Graph order did not complete at exact work")
      }
    }
    let output = completed.unwrap()
    assert_eq(@execution.completed_row_count(output), 3)
    let mut column = -1
    for index in 0..<@execution.completed_column_count(output) {
      if @execution.completed_column_name(output, index) == Some("person_key") {
        column = index
      }
    }
    assert_true(column >= 0)
    for row in 0..<3 {
      guard @execution.completed_cell(output, row, column)
        is Some(@execution.Number(actual)) else {
        fail("Graph key is not a typed number")
      }
      assert_eq(actual, (row + 1).to_double())
    }
    graph_order_close(fixture)
    assert_true(@execution.completed_output_available(output))
    for row in 0..<3 {
      guard @execution.completed_cell(output, row, column)
        is Some(@execution.Number(actual)) else {
        fail("Graph key disappeared after cleanup")
      }
      assert_eq(actual, (row + 1).to_double())
    }
  }
  let short = graph_order_fixture(work=328)
  let mut refused = false
  for _ in 0..<1000 {
    match advance_events_to_rows(short.active, 1).unwrap() {
      Continue(..) => ()
      Failed(ControlWorkLimit, work~, ..) => {
        assert_eq(work, 328L)
        refused = true
        break
      }
      _ => fail("one-short Graph order exposed output")
    }
  }
  assert_true(refused)
  graph_order_close(short)
}

// Fixture adapted from src/query_integration/engine_fixtures_wbtest.mbt at bc4690dac556404e0d31cb410329fdb50553d6de.

///|
fn graph_order_input_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(
      text,
      { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      source_path="supplied.json",
    ).unwrap(),
    {
      max_nodes: 1000,
      max_depth: 100,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

// Fixture adapted from src/query_integration/engine_fixtures_wbtest.mbt at bc4690dac556404e0d31cb410329fdb50553d6de.

///|
fn graph_order_run_limits() -> @execution.SequenceRunLimits {
  {
    max_rows: 100,
    metadata_entries: 10000,
    retained_entries: 10000,
    operation_entries: 10000,
    input_values: {
      max_nodes: 10000,
      max_text_bytes: 10000,
      max_depth: 100,
      max_work: 100000,
    },
    output_values: {
      max_nodes: 10000,
      max_text_bytes: 10000,
      max_depth: 100,
      max_work: 100000,
    },
  }
}

// Fixture adapted from src/query_integration/engine_fixtures_wbtest.mbt at bc4690dac556404e0d31cb410329fdb50553d6de.

///|
fn graph_order_prepared_sequence(
  owner : @lower.BoundPrepared,
  prefix_end? : Int? = None,
) -> @lower.PreparedSequence {
  let limits : @lower.SequenceLimits = {
    max_steps: 100,
    max_rows: 100,
    max_cells: 10000,
    max_bindings: 100,
    max_name_bytes: 10000,
    expressions: {
      max_nodes: 10000,
      max_work: 100000,
      max_depth: 100,
      max_literal_nodes: 10000,
      max_literal_text_bytes: 10000,
    },
  }
  match prefix_end {
    Some(last) => @lower.prepare_sequence_prefix(owner, last, limits).unwrap()
    None => @lower.prepare_sequence(owner, limits).unwrap()
  }
}

// Fixture adapted from src/query_integration/engine_fixtures_wbtest.mbt at bc4690dac556404e0d31cb410329fdb50553d6de.

///|
fn graph_order_registered_relation_contracts() -> @execution.RegisteredRelationContracts raise {
  @execution.admit_relation_registry(
    graph_order_registered_body(),
    graph_order_registered_values(),
    graph_order_registry_limits(),
  ).unwrap()
}

// Fixture adapted from src/query_integration/engine_fixtures_wbtest.mbt at bc4690dac556404e0d31cb410329fdb50553d6de.

///|
fn graph_order_registry_limits() -> @execution.RegistryLimits {
  { max_body_bytes: 100000, max_body_nodes: 10000, max_body_depth: 100, }
}

// Fixture adapted from src/query_integration/property_graph_construction_wbtest.mbt at bc4690dac556404e0d31cb410329fdb50553d6de.

///|
fn graph_order_keyed_source_owner(
  schema : String,
  rows : String,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check(
    graph_order_input_cursor(
      "[{\"values\":{\"schema\":" +
      schema +
      ",\"rows\":" +
      rows +
      "},\"as\":\"source\"}]",
    ),
    [],
    None,
    None,
    {
      max_steps: 10,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 1000,
      max_references: 1000,
      max_work: 100000,
      max_identifier_bytes: 100000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

// Fixture adapted from src/query_integration/property_graph_construction_wbtest.mbt at bc4690dac556404e0d31cb410329fdb50553d6de.

///|
fn graph_order_keyed_bridge_owner(
  nodes : @lower.BoundPrepared,
  edges : @lower.BoundPrepared,
  body? : String? = None,
  edge_alt? : @lower.BoundPrepared? = None,
) -> @lower.BoundPrepared {
  let inputs = [
    (
      "nodes",
      @pipeline.ProducedInput(
        @pipeline.produced_input(
          @lower.pipeline(@lower.bound_preparation(nodes)),
          @pipeline.Step(0),
        ).unwrap(),
      ),
    ),
    (
      "edges",
      @pipeline.ProducedInput(
        @pipeline.produced_input(
          @lower.pipeline(@lower.bound_preparation(edges)),
          @pipeline.Step(0),
        ).unwrap(),
      ),
    ),
  ]
  if edge_alt is Some(source) {
    inputs.push(
      (
        "edges_alt",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(source)),
            @pipeline.Step(0),
          ).unwrap(),
        ),
      ),
    )
  }
  let checked = @pipeline.check_with_evidence(
    graph_order_input_cursor(
      body.unwrap_or(
        (
          #|[{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["tenant","id"],"labels":[{"name":"Node","properties":{"mode":"columns","columns":[{"from":"name","to":"display"}]}}]}],"edges":[{"name":"E","from":"edges","key":["key"],"source":{"definition":"N","key":["tenant","src"]},"target":{"definition":"N","key":["tenant","dst"]},"labels":[{"name":"R","properties":{"mode":"no_properties"}}]}]},"as":"g"}]
        ),
      ),
    ),
    inputs,
    None,
    None,
    {
      max_steps: 10,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 1000,
      max_references: 1000,
      max_work: 100000,
      max_identifier_bytes: 100000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

// Fixture adapted from src/query_integration/property_graph_construction_wbtest.mbt at bc4690dac556404e0d31cb410329fdb50553d6de.

///|
fn graph_order_keyed_bridge_inputs(
  owner : @lower.BoundPrepared,
  nodes : @lower.BoundPrepared,
  edges : @lower.BoundPrepared,
  edge_alt? : @lower.BoundPrepared? = None,
) -> Array[@execution.ProducerRead] raise {
  let inputs = []
  let sources = [nodes, edges]
  if edge_alt is Some(source) {
    sources.push(source)
  }
  for index, source in sources {
    let output = graph_order_carrier_events_source_output(source)
    inputs.push(
      @execution.prepare_producer_read(
        owner,
        @execution.bind_completed_input(owner, index, source, output).unwrap(),
        1000,
        10000,
      ).unwrap(),
    )
  }
  inputs
}

// Fixture adapted from src/query_integration/property_graph_construction_wbtest.mbt at bc4690dac556404e0d31cb410329fdb50553d6de.

///|
fn graph_order_keyed_bridge_terminal(
  active : RowsToGraphExecution,
  max_fixture_steps? : Int = 1000,
) -> RowsToGraphPoll {
  for _ in 0..<max_fixture_steps {
    match advance_rows_to_graph(active, 1).unwrap() {
      Continue(..) => ()
      terminal => return terminal
    }
  }
  abort("bounded property constructor did not finish")
}

// Fixture adapted from src/query_integration/property_graph_construction_wbtest.mbt at bc4690dac556404e0d31cb410329fdb50553d6de.

///|
fn graph_order_keyed_graph_receiver(
  owner : @lower.BoundPrepared,
  body? : String = "[]",
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    graph_order_input_cursor(body),
    [
      (
        "g",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(owner)),
            @pipeline.Step(0),
          ).unwrap(),
        ),
      ),
    ],
    None,
    Some(graph_order_input_cursor("\"g\"")),
    {
      max_steps: 10,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 1000,
      max_references: 1000,
      max_work: 100000,
      max_identifier_bytes: 100000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

// Fixture adapted from src/query_integration/property_graph_fixture_helpers_wbtest.mbt at bc4690dac556404e0d31cb410329fdb50553d6de.

///|
fn graph_order_carrier_graph_storage_limits() -> @graph_storage.Limits {
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

// Fixture adapted from src/query_integration/task_generated_fixture_wbtest.mbt at bc4690dac556404e0d31cb410329fdb50553d6de.

///|
fn graph_order_task_test_completion(
  owner : @lower.BoundPrepared,
) -> @execution.CompletionPreparation raise {
  let sequence = graph_order_prepared_sequence(owner)
  let last = @lower.node_at(
    @lower.bound_preparation(owner),
    @lower.sequence_count(sequence) - 1,
  ).unwrap()
  @execution.prepare_completion(
    graph_order_registered_relation_contracts(),
    sequence,
    [@lower.node_id(last)],
    100000,
    10000,
  ).unwrap()
}
