///|
fn property_equality_receiver(
  graph_owner : @lower.BoundPrepared,
  other_owner : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  let left = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(graph_owner)),
    @pipeline.Step(0),
  ).unwrap()
  let right = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(other_owner)),
    @pipeline.Step(0),
  ).unwrap()
  let checked = @pipeline.check_with_evidence(
    input_cursor("[{\"graphs_equal\":{\"with\":\"other\"}}]"),
    [
      ("g", @pipeline.ProducedInput(left)),
      ("other", @pipeline.ProducedInput(right)),
    ],
    None,
    Some(input_cursor("\"g\"")),
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

///|
test "current Graph equality compares retained values with bounded steps" {
  let nodes = keyed_node_source(
    rows="[{\"id\":1,\"tenant\":\"a\",\"name\":\"one\"}]",
  )
  let edges = keyed_edge_source(rows="[]")
  let graph_owner = keyed_bridge_owner(nodes, edges)
  let construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    prepared_sequence(graph_owner),
    0,
    keyed_bridge_inputs(graph_owner, nodes, edges),
    carrier_graph_storage_limits(),
    4096L,
    1000,
    () => true,
  ).unwrap()
  guard keyed_bridge_terminal(construction) is @local_bridge.Complete(graph, ..) else {
    fail("property Graph construction failed")
  }
  let receiver = property_equality_receiver(graph_owner, graph_owner)
  let left = @graphs.prepare_producer_read(receiver, 0, graph_owner, graph).unwrap()
  let right = @graphs.prepare_producer_read(receiver, 1, graph_owner, graph).unwrap()
  let first = @graphs.producer_read_view(left).unwrap()
  let second = @graphs.producer_read_view(right).unwrap()
  let control = @bounded.control()
  let active = @local_sga.start_property_equality_views(
    control,
    task_test_completion(receiver),
    prepared_sequence(receiver),
    0,
    first,
    second,
    1,
    {
      max_work: 100000,
      max_nodes: 10000,
      max_text_bytes: 10000,
      max_depth: 50,
    },
    1000,
    10000,
    10000,
    100000,
  ).unwrap()
  let mut result = None
  for _ in 0..<10000 {
    match @local_sga.advance_property_equality(active, 1).unwrap() {
      @local_sga.PropertyEqualityContinue(..) => ()
      @local_sga.PropertyEqualityComplete(output, ..) => {
        result = Some(output)
        break
      }
      _ => fail("bounded property Graph equality failed")
    }
  }
  let output = result.unwrap()
  assert_eq(
    @execution.completed_output_row_wire(output, 0, 10000, 10000, 50).unwrap(),
    "{\"equal\":true}",
  )
  assert_true(@local_sga.cleanup_property_equality(active).unwrap())
  assert_true(@graphs.producer_read_available(left))
  assert_true(@graphs.producer_read_available(right))
  assert_true(@graphs.discard_completed(graph))
}

///|
fn property_equality_wire(
  first_rows : String,
  second_rows : String,
) -> String raise {
  let first_nodes = keyed_node_source(rows=first_rows)
  let second_nodes = keyed_node_source(rows=second_rows)
  let edges = keyed_edge_source(rows="[]")
  let first_owner = keyed_bridge_owner(first_nodes, edges)
  let second_owner = keyed_bridge_owner(second_nodes, edges)
  let first_build = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    prepared_sequence(first_owner),
    0,
    keyed_bridge_inputs(first_owner, first_nodes, edges),
    carrier_graph_storage_limits(),
    4096L,
    1000,
    () => true,
  ).unwrap()
  guard keyed_bridge_terminal(first_build)
    is @local_bridge.Complete(first_graph, ..) else {
    fail("first Graph construction failed")
  }
  let second_build = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    prepared_sequence(second_owner),
    0,
    keyed_bridge_inputs(second_owner, second_nodes, edges),
    carrier_graph_storage_limits(),
    4096L,
    1000,
    () => true,
  ).unwrap()
  guard keyed_bridge_terminal(second_build)
    is @local_bridge.Complete(second_graph, ..) else {
    fail("second Graph construction failed")
  }
  let receiver = property_equality_receiver(first_owner, second_owner)
  let left = @graphs.prepare_producer_read(
    receiver, 0, first_owner, first_graph,
  ).unwrap()
  let right = @graphs.prepare_producer_read(
    receiver, 1, second_owner, second_graph,
  ).unwrap()
  let active = @local_sga.start_property_equality_views(
    @bounded.control(),
    task_test_completion(receiver),
    prepared_sequence(receiver),
    0,
    @graphs.producer_read_view(left).unwrap(),
    @graphs.producer_read_view(right).unwrap(),
    1,
    {
      max_work: 100000,
      max_nodes: 10000,
      max_text_bytes: 10000,
      max_depth: 50,
    },
    1000,
    10000,
    10000,
    100000,
  ).unwrap()
  let mut result = None
  for _ in 0..<10000 {
    match @local_sga.advance_property_equality(active, 1).unwrap() {
      @local_sga.PropertyEqualityContinue(..) => ()
      @local_sga.PropertyEqualityComplete(output, ..) => {
        result = Some(output)
        break
      }
      _ => fail("changed property comparison failed")
    }
  }
  let wire = @execution.completed_output_row_wire(
    result.unwrap(),
    0,
    10000,
    10000,
    50,
  ).unwrap()
  assert_true(@local_sga.cleanup_property_equality(active).unwrap())
  assert_true(@graphs.discard_completed(first_graph))
  assert_true(@graphs.discard_completed(second_graph))
  wire
}

///|
test "Graph equality charges exact work and retains inputs after stop" {
  let present = keyed_node_source(
    rows="[{\"id\":1,\"tenant\":\"a\",\"name\":\"one\"}]",
  )
  let absent = keyed_node_source(rows="[]")
  let edges = keyed_edge_source(rows="[]")
  let first_owner = keyed_bridge_owner(present, edges)
  let second_owner = keyed_bridge_owner(absent, edges)
  let first_build = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    prepared_sequence(first_owner),
    0,
    keyed_bridge_inputs(first_owner, present, edges),
    carrier_graph_storage_limits(),
    4096L,
    1000,
    () => true,
  ).unwrap()
  guard keyed_bridge_terminal(first_build)
    is @local_bridge.Complete(first_graph, ..) else {
    fail("first Graph construction failed")
  }
  let second_build = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    prepared_sequence(second_owner),
    0,
    keyed_bridge_inputs(second_owner, absent, edges),
    carrier_graph_storage_limits(),
    4096L,
    1000,
    () => true,
  ).unwrap()
  guard keyed_bridge_terminal(second_build)
    is @local_bridge.Complete(second_graph, ..) else {
    fail("second Graph construction failed")
  }
  let receiver = property_equality_receiver(first_owner, second_owner)
  let first_read = @graphs.prepare_producer_read(
    receiver, 0, first_owner, first_graph,
  ).unwrap()
  let second_read = @graphs.prepare_producer_read(
    receiver, 1, second_owner, second_graph,
  ).unwrap()
  let first_view = @graphs.producer_read_view(first_read).unwrap()
  let second_view = @graphs.producer_read_view(second_read).unwrap()
  let limits : @execution.ValueLimits = {
    max_work: 100000,
    max_nodes: 10000,
    max_text_bytes: 10000,
    max_depth: 50,
  }
  // A different admitted node count needs CompareCounts, EmitResult, and
  // FinishResult; no identity or property scan is required.
  for (allowed, success) in [(3, true), (2, false)] {
    let active = @local_sga.start_property_equality_views(
      @bounded.control(),
      task_test_completion(receiver),
      prepared_sequence(receiver),
      0,
      first_view,
      second_view,
      1,
      limits,
      1,
      10000,
      10000,
      allowed,
    ).unwrap()
    let mut terminal = false
    let mut prior_work = 0L
    for _ in 0..<4 {
      match @local_sga.advance_property_equality(active, 1).unwrap() {
        @local_sga.PropertyEqualityContinue(work~, ..) => {
          assert_true(work > prior_work && work - prior_work <= 1L)
          prior_work = work
        }
        @local_sga.PropertyEqualityComplete(output, ..) => {
          assert_true(success)
          assert_eq(
            @execution.completed_output_row_wire(output, 0, 10000, 10000, 50).unwrap(),
            "{\"equal\":false}",
          )
          terminal = true
          break
        }
        @local_sga.PropertyEqualityFailed(
          @local_sga.PropertyEqualityWorkLimit,
          ..
        ) => {
          assert_false(success)
          terminal = true
          break
        }
        _ => fail("unexpected property Graph equality boundary")
      }
    }
    assert_true(terminal)
    assert_true(@local_sga.cleanup_property_equality(active).unwrap())
    assert_false(@local_sga.property_equality_cleanup_pending(active))
    assert_true(@graphs.producer_read_available(first_read))
    assert_true(@graphs.producer_read_available(second_read))
  }
  assert_true(
    @local_sga.start_property_equality_views(
      @bounded.control(),
      task_test_completion(receiver),
      prepared_sequence(receiver),
      0,
      first_view,
      second_view,
      1,
      limits,
      0,
      10000,
      10000,
      3,
    )
    is Err(@local_sga.PropertyEqualityWorkspaceLimit),
  )
  let control = @bounded.control()
  let cancelling = @local_sga.start_property_equality_views(
    control,
    task_test_completion(receiver),
    prepared_sequence(receiver),
    0,
    first_view,
    second_view,
    1,
    limits,
    1,
    10000,
    10000,
    3,
  ).unwrap()
  assert_true(
    @local_sga.advance_property_equality(cancelling, 1).unwrap()
    is @local_sga.PropertyEqualityContinue(work=1L, ..),
  )
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_sga.advance_property_equality(cancelling, 1).unwrap()
    is @local_sga.PropertyEqualityStopped(_, ..),
  )
  assert_true(@local_sga.cleanup_property_equality(cancelling).unwrap())
  assert_false(@local_sga.property_equality_cleanup_pending(cancelling))
  assert_true(@graphs.producer_read_available(first_read))
  assert_true(@graphs.producer_read_available(second_read))
  assert_true(@graphs.discard_completed(first_graph))
  assert_true(@graphs.discard_completed(second_graph))
}

///|
test "Graph equality bounds nested text comparison and stops mid-value" {
  let long_name = "x".repeat(512)
  let nodes = keyed_node_source(
    rows="[{\"id\":1,\"tenant\":\"a\",\"name\":\"" + long_name + "\"}]",
  )
  let edges = keyed_edge_source(rows="[]")
  let graph_owner = keyed_bridge_owner(nodes, edges)
  let construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    prepared_sequence(graph_owner),
    0,
    keyed_bridge_inputs(graph_owner, nodes, edges),
    carrier_graph_storage_limits(),
    4096L,
    1000,
    () => true,
  ).unwrap()
  guard keyed_bridge_terminal(construction) is @local_bridge.Complete(graph, ..) else {
    fail("long-value Graph construction failed")
  }
  let receiver = property_equality_receiver(graph_owner, graph_owner)
  let left = @graphs.prepare_producer_read(receiver, 0, graph_owner, graph).unwrap()
  let right = @graphs.prepare_producer_read(receiver, 1, graph_owner, graph).unwrap()
  let first = @graphs.producer_read_view(left).unwrap()
  let second = @graphs.producer_read_view(right).unwrap()
  let limits : @execution.ValueLimits = {
    max_work: 100000,
    max_nodes: 10000,
    max_text_bytes: 10000,
    max_depth: 50,
  }
  let limited = @local_sga.start_property_equality_views(
    @bounded.control(),
    task_test_completion(receiver),
    prepared_sequence(receiver),
    0,
    first,
    second,
    1,
    limits,
    1,
    10000,
    10000,
    20,
  ).unwrap()
  let mut hit_limit = false
  for _ in 0..<25 {
    match @local_sga.advance_property_equality(limited, 1).unwrap() {
      @local_sga.PropertyEqualityContinue(..) => ()
      @local_sga.PropertyEqualityFailed(
        @local_sga.PropertyEqualityWorkLimit,
        ..
      ) => {
        hit_limit = true
        break
      }
      _ => fail("long-value comparison must fail at its work ceiling")
    }
  }
  assert_true(hit_limit)
  assert_true(@local_sga.cleanup_property_equality(limited).unwrap())
  let control = @bounded.control()
  let active = @local_sga.start_property_equality_views(
    control,
    task_test_completion(receiver),
    prepared_sequence(receiver),
    0,
    first,
    second,
    1,
    limits,
    1,
    10000,
    10000,
    10000,
  ).unwrap()
  for _ in 0..<50 {
    guard @local_sga.advance_property_equality(active, 1).unwrap()
      is @local_sga.PropertyEqualityContinue(..) else {
      fail("long-value comparison must yield within the value")
    }
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_sga.advance_property_equality(active, 1).unwrap()
    is @local_sga.PropertyEqualityStopped(_, ..),
  )
  assert_true(@local_sga.cleanup_property_equality(active).unwrap())
  assert_true(@graphs.producer_read_available(left))
  assert_true(@graphs.producer_read_available(right))
  assert_true(@graphs.discard_completed(graph))
}

///|
test "current Graph equality distinguishes a changed producer domain" {
  assert_eq(
    property_equality_wire(
      "[{\"id\":1,\"tenant\":\"a\",\"name\":\"one\"}]", "[{\"id\":1,\"tenant\":\"a\",\"name\":\"two\"}]",
    ),
    "{\"equal\":false}",
  )
}

///|
test "separately retained Graphs with the same semantic identity compare equal" {
  let rows = "[{\"id\":1,\"tenant\":\"a\",\"name\":\"one\"}]"
  assert_eq(property_equality_wire(rows, rows), "{\"equal\":true}")
}

///|
test "compatible empty Graphs remain equal despite different producer domains" {
  assert_eq(
    property_equality_wire(
      "[{\"id\":null,\"tenant\":\"a\",\"name\":\"one\"}]", "[{\"id\":null,\"tenant\":\"a\",\"name\":\"two\"}]",
    ),
    "{\"equal\":true}",
  )
}
