///|
test "typed node and edge identity sorting yields during long comparisons and preserves input on stop" {
  let prefix = "x".repeat(160)
  let first = prefix + "a"
  let second = prefix + "b"
  let source = keyed_source_owner(
    "{\"id\":{\"type\":\"string\",\"nullable\":false}}",
    "[{\"id\":\"" + second + "\"},{\"id\":\"" + first + "\"}]",
  )
  let graph_body =
    #|[{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["id"]}],"edges":[{"name":"E","from":"edges","key":["id"],"source":{"definition":"N","key":["id"]},"target":{"definition":"N","key":["id"]}}]},"as":"g"}]
  let owner = keyed_bridge_owner(source, source, body=Some(graph_body))
  let construction = @local_bridge.start_rows_to_property_graph(
    @bounded.control(),
    prepared_sequence(owner),
    0,
    keyed_bridge_inputs(owner, source, source),
    { ..carrier_graph_storage_limits(), max_work: 10000, },
    10000L,
    1000,
    () => true,
  ).unwrap()
  let mut retained = None
  for _ in 0..<10000 {
    match @local_bridge.advance_rows_to_graph(construction, 1).unwrap() {
      @local_bridge.Continue(..) => ()
      @local_bridge.Complete(graph, ..) => {
        retained = Some(graph)
        break
      }
      _ => fail("long typed-key constructor failed")
    }
  }
  let graph = retained.unwrap()
  guard @pipeline.carrier_at(
      @lower.pipeline(@lower.bound_preparation(owner)),
      @pipeline.Step(0),
    )
    is Some(@carrier_contract.GraphValue(schema)) else {
    fail("current Graph schema")
  }
  let domain = @carrier_contract.property_graph_domain(
    @carrier_contract.graph_property_definition(schema),
  )
  for edges in [false, true] {
    let definition = if edges { "E" } else { "N" }
    let operation = if edges { "match_edges" } else { "match_nodes" }
    let receiver = keyed_graph_receiver(
      owner,
      body="[{\"from\":\"g\",\"" +
        operation +
        "\":{\"definition\":\"" +
        definition +
        "\",\"bindings\":{\"identity\":\"element\"},\"where\":\"true\",\"fields\":[\"element\"]}}]",
    )
    let input = @graphs.prepare_producer_read(receiver, 0, owner, graph).unwrap()
    let control = @bounded.control()
    let sequence = prepared_sequence(receiver)
    let preparation = task_test_completion(receiver)
    let limits : @execution.ValueLimits = {
      max_work: 100000,
      max_nodes: 10000,
      max_text_bytes: 10000,
      max_depth: 50,
    }
    if edges {
      let active = @local_sga.start_match_edges(
        control,
        preparation,
        sequence,
        0,
        input,
        2,
        limits,
        100,
        10000,
        10000,
        [],
      ).unwrap()
      for _ in 0..<60 {
        guard @local_sga.advance_match_edges(active, 1)
          is Ok(@local_sga.MatchEdgesContinue(work~, ..)) else {
          fail("long edge comparison must yield")
        }
        assert_true(work > 0L)
      }
      assert_true(@bounded.request_cancel(control))
      assert_true(
        @local_sga.advance_match_edges(active, 1)
        is Ok(@local_sga.MatchEdgesStopped(_, ..)),
      )
      assert_true(@local_sga.cleanup_match_edges(active).unwrap())
      assert_false(@local_sga.cleanup_match_edges(active).unwrap())
      assert_true(@graphs.producer_read_available(input))
      let complete = @local_sga.start_match_edges(
        @bounded.control(),
        preparation,
        sequence,
        0,
        input,
        2,
        limits,
        100,
        10000,
        10000,
        [],
      ).unwrap()
      let output = finish_match_edges(complete).unwrap()
      for index, key in [first, second] {
        assert_eq(
          @execution.completed_output_row_wire(output, index, 10000, 10000, 50).unwrap(),
          "{\"element\":{\"definition\":\"E\",\"domain\":\"" +
          domain +
          "\",\"key\":[\"" +
          key +
          "\"],\"key_types\":[{\"kind\":\"string\"}]}}",
        )
      }
      assert_true(@local_sga.cleanup_match_edges(complete).unwrap())
    } else {
      let active = @local_sga.start_match_nodes(
        control,
        preparation,
        sequence,
        0,
        input,
        2,
        limits,
        100,
        10000,
        10000,
        [],
      ).unwrap()
      for _ in 0..<60 {
        guard @local_sga.advance_match_nodes(active, 1)
          is Ok(@local_sga.MatchNodesContinue(work~, ..)) else {
          fail("long node comparison must yield")
        }
        assert_true(work > 0L)
      }
      assert_true(@bounded.request_cancel(control))
      assert_true(
        @local_sga.advance_match_nodes(active, 1)
        is Ok(@local_sga.MatchNodesStopped(_, ..)),
      )
      assert_true(@local_sga.cleanup_match_nodes(active).unwrap())
      assert_false(@local_sga.cleanup_match_nodes(active).unwrap())
      assert_true(@graphs.producer_read_available(input))
      let complete = @local_sga.start_match_nodes(
        @bounded.control(),
        preparation,
        sequence,
        0,
        input,
        2,
        limits,
        100,
        10000,
        10000,
        [],
      ).unwrap()
      let output = finish_match_nodes(complete).unwrap()
      for index, key in [first, second] {
        assert_eq(
          @execution.completed_output_row_wire(output, index, 10000, 10000, 50).unwrap(),
          "{\"element\":{\"definition\":\"N\",\"domain\":\"" +
          domain +
          "\",\"key\":[\"" +
          key +
          "\"],\"key_types\":[{\"kind\":\"string\"}]}}",
        )
      }
      assert_true(@local_sga.cleanup_match_nodes(complete).unwrap())
    }
  }
  let identity = fn(key : String) {
    "{\"definition\":\"N\",\"domain\":\"" +
    domain +
    "\",\"key\":[\"" +
    key +
    "\"],\"key_types\":[{\"kind\":\"string\"}]}"
  }
  let receiver = keyed_graph_receiver(
    owner,
    body="[{\"from\":\"g\",\"traverse\":{\"start\":{\"ids\":[" +
      identity(second) +
      "," +
      identity(first) +
      "]},\"path_mode\":\"trail\",\"min_hops\":0,\"max_hops\":1,\"direction\":\"out\",\"emit\":\"paths\"}}]",
  )
  let input = @graphs.prepare_producer_read(receiver, 0, owner, graph).unwrap()
  let preparation = task_test_completion(receiver)
  let start = fn(control) {
    @local_sga.start_traverse(
      control,
      preparation,
      prepared_sequence(receiver),
      0,
      input,
      4,
      {
        max_work: 100000,
        max_nodes: 10000,
        max_text_bytes: 10000,
        max_depth: 50,
      },
      100,
      10000,
      10000,
      [],
    ).unwrap()
  }
  let control = @bounded.control()
  let active = start(control)
  for _ in 0..<60 {
    guard @local_sga.advance_traverse(active, 1)
      is Ok(@local_sga.TraverseContinue(work~, ..)) else {
      fail("long start comparison must yield")
    }
    assert_true(work > 0L)
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_sga.advance_traverse(active, 1)
    is Ok(@local_sga.TraverseStopped(_, ..)),
  )
  assert_true(@local_sga.cleanup_traverse(active).unwrap())
  assert_false(@local_sga.cleanup_traverse(active).unwrap())
  assert_eq(@local_sga.traverse_private_entry_count(active), 0)
  assert_true(@graphs.producer_read_available(input))
  let complete = start(@bounded.control())
  let output = finish_traverse(complete).unwrap()
  assert_eq(@execution.completed_row_count(output), 4)
  for index, key in [first, second] {
    let node = identity(key)
    let edge = "{\"definition\":\"E\",\"domain\":\"" +
      domain +
      "\",\"key\":[\"" +
      key +
      "\"],\"key_types\":[{\"kind\":\"string\"}]}"
    for depth in [0, 1] {
      let edge_ids = if depth == 0 { "[]" } else { "[" + edge + "]" }
      let node_ids = if depth == 0 {
        "[" + node + "]"
      } else {
        "[" + node + "," + node + "]"
      }
      assert_eq(
        @execution.completed_output_row_wire(
          output,
          index * 2 + depth,
          10000,
          10000,
          50,
        ).unwrap(),
        "{\"edge_ids\":" +
        edge_ids +
        ",\"end_id\":" +
        node +
        ",\"hop_count\":" +
        depth.to_string() +
        ",\"node_ids\":" +
        node_ids +
        ",\"start_id\":" +
        node +
        "}",
      )
    }
  }
  assert_true(@local_sga.cleanup_traverse(complete).unwrap())
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
}
