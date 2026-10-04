///|
fn traversal_fixture_node(domain : String, key : Int) -> String {
  "{\"definition\":\"N\",\"domain\":\"" +
  domain +
  "\",\"key\":[\"a\"," +
  key.to_string() +
  "],\"key_types\":[{\"kind\":\"string\"},{\"kind\":\"number\"}]}"
}

///|
test "keyed node traversal keeps minimum eligible depth without pruning paths" {
  let nodes = keyed_node_source(
    rows=(
      #|[{"id":3,"tenant":"a","name":"three"},{"id":2,"tenant":"a","name":"two"},{"id":1,"tenant":"a","name":"one"}]
    ),
  )
  let edges = keyed_edge_source(
    rows=(
      #|[{"key":13,"tenant":"a","src":1,"dst":3},{"key":12,"tenant":"a","src":1,"dst":2},{"key":11,"tenant":"a","src":2,"dst":1},{"key":10,"tenant":"a","src":1,"dst":2},{"key":14,"tenant":"a","src":2,"dst":3}]
    ),
  )
  let graph_owner = keyed_bridge_owner(nodes, edges)
  let construction = @local_bridge.start_rows_to_property_graph(
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
    fail("constructor failed")
  }
  guard @pipeline.carrier_at(
      @lower.pipeline(@lower.bound_preparation(graph_owner)),
      @pipeline.Step(0),
    )
    is Some(@carrier_contract.GraphValue(carrier)) else {
    fail("Graph schema")
  }
  let domain = @carrier_contract.property_graph_domain(
    @carrier_contract.graph_property_definition(carrier),
  )
  // Independently authored expectations, never copied from traversal output.
  for
    (mode, minimum, maximum, starts, expected) in [
      ("walk", 2, 2, [1], [(1, 1, 2), (1, 3, 2)]),
      ("trail", 2, 2, [1], [(1, 1, 2), (1, 3, 2)]),
      ("acyclic", 2, 2, [1], [(1, 3, 2)]),
      ("trail", 1, 1, [1], [(1, 2, 1), (1, 3, 1)]),
      ("walk", 1, 3, [1], [(1, 1, 2), (1, 2, 1), (1, 3, 1)]),
      ("acyclic", 0, 1, [3, 1, 3], [(1, 1, 0), (1, 2, 1), (1, 3, 1), (3, 3, 0)]),
      ("walk", 3, 3, [1], [(1, 2, 3), (1, 3, 3)]),
      ("trail", 3, 3, [1], [(1, 2, 3), (1, 3, 3)]),
      ("acyclic", 3, 3, [1], []),
    ] {
    let ids = starts.map(key => traversal_fixture_node(domain, key)).join(",")
    let owner = keyed_graph_receiver(
      graph_owner,
      body="[{\"from\":\"g\",\"traverse\":{\"start\":{\"ids\":[" +
        ids +
        "]},\"direction\":\"out\",\"min_hops\":" +
        minimum.to_string() +
        ",\"max_hops\":" +
        maximum.to_string() +
        ",\"path_mode\":\"" +
        mode +
        "\",\"emit\":\"nodes\"}}]",
    )
    let input = @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
    for viewed in [false, true] {
      let limits : @execution.ValueLimits = {
        max_work: 100000,
        max_nodes: 10000,
        max_text_bytes: 10000,
        max_depth: 50,
      }
      let active = if viewed {
        @local_sga.start_traverse_view(
          @bounded.control(),
          task_test_completion(owner),
          prepared_sequence(owner),
          0,
          @graphs.producer_read_view(input).unwrap(),
          expected.length(),
          limits,
          20000,
          10000,
          10000,
          [],
        ).unwrap()
      } else {
        @local_sga.start_traverse(
          @bounded.control(),
          task_test_completion(owner),
          prepared_sequence(owner),
          0,
          input,
          expected.length(),
          limits,
          20000,
          10000,
          10000,
          [],
        ).unwrap()
      }
      let output = finish_traverse(active).unwrap()
      assert_eq(@execution.completed_row_count(output), expected.length())
      for row, (start, node, depth) in expected {
        assert_eq(
          @execution.completed_output_row_wire(output, row, 10000, 10000, 50).unwrap(),
          "{\"depth\":" +
          depth.to_string() +
          ",\"node_id\":" +
          traversal_fixture_node(domain, node) +
          ",\"start_id\":" +
          traversal_fixture_node(domain, start) +
          "}",
        )
      }
      assert_true(@local_sga.cleanup_traverse(active).unwrap())
      assert_false(@local_sga.cleanup_traverse(active).unwrap())
      assert_false(@local_sga.traverse_cleanup_pending(active))
      assert_eq(@local_sga.traverse_private_entry_count(active), 0)
      assert_true(@execution.completed_output_available(output))
      assert_true(@graphs.producer_read_available(input))
    }
  }
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
}

///|
test "keyed node traversal has independent exact budgets and every zero-hop stop boundary" {
  let nodes = keyed_node_source()
  let edge_count = 100
  let edge_rows = []
  for key in 0..<edge_count {
    edge_rows.push(
      "{\"key\":" + key.to_string() + ",\"tenant\":\"a\",\"src\":1,\"dst\":1}",
    )
  }
  let edges = keyed_edge_source(rows="[" + edge_rows.join(",") + "]")
  let definitions = []
  for index in 0..<5 {
    definitions.push(
      "{\"name\":\"E" +
      index.to_string() +
      "\",\"from\":\"edges\",\"key\":[\"key\"],\"source\":{\"definition\":\"N\",\"key\":[\"tenant\",\"src\"]},\"target\":{\"definition\":\"N\",\"key\":[\"tenant\",\"dst\"]},\"labels\":[{\"name\":\"R\",\"properties\":{\"mode\":\"no_properties\"}}]}",
    )
  }
  let graph_owner = keyed_bridge_owner(
    nodes,
    edges,
    body=Some(
      "[{\"property_graph\":{\"version\":\"actql-property-graph-constructor/0.1\",\"nodes\":[{\"name\":\"N\",\"from\":\"nodes\",\"key\":[\"tenant\",\"id\"],\"labels\":[{\"name\":\"Node\",\"properties\":{\"mode\":\"columns\",\"columns\":[{\"from\":\"name\",\"to\":\"display\"}]}}]}],\"edges\":[" +
      definitions.join(",") +
      "]},\"as\":\"g\"}]",
    ),
  )
  let inputs = keyed_bridge_inputs(graph_owner, nodes, edges)
  for _ in 0..<4 {
    inputs.push(inputs[1])
  }
  let construction = @local_bridge.start_rows_to_property_graph(
    @bounded.control(),
    prepared_sequence(graph_owner),
    0,
    inputs,
    {
      ..carrier_graph_storage_limits(),
      max_input_rows: 600,
      max_edges: 500,
      max_work: 1000000,
      max_workspace_slots: 100000,
      max_total_value_bytes: 1000000,
      max_retained_value_bytes: 1000000,
    },
    8388608L,
    10000,
    () => true,
  ).unwrap()
  guard keyed_bridge_terminal(construction, max_fixture_steps=100000)
    is @local_bridge.Complete(graph, ..) else {
    fail("constructor failed")
  }
  guard @pipeline.carrier_at(
      @lower.pipeline(@lower.bound_preparation(graph_owner)),
      @pipeline.Step(0),
    )
    is Some(@carrier_contract.GraphValue(contract)) else {
    fail("Graph schema")
  }
  let id = traversal_fixture_node(
    @carrier_contract.property_graph_domain(
      @carrier_contract.graph_property_definition(contract),
    ),
    1,
  )
  let owner = keyed_graph_receiver(
    graph_owner,
    body="[{\"from\":\"g\",\"traverse\":{\"start\":{\"ids\":[" +
      id +
      "]},\"direction\":\"out\",\"min_hops\":0,\"max_hops\":1,\"edge_types\":[],\"path_mode\":\"walk\",\"emit\":\"nodes\"}}]",
  )
  let input = @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
  let preparation = task_test_completion(owner)
  // Start selection/resolve/collect (3), depth index (1), eligible endpoint
  // collection (1), scalar columns (3), row commit (1), completion (1),
  // and scan plus WALK mode check for each excluded edge (2 * 5 * edge_count).
  // The scan ceiling also permits ordinary typed value admission; no
  // separate work budget or fabricated cleanup cost is introduced.
  // Peak private entries: start index (1), depth index (1), seed path (2)
  // and endpoint order index (1). Neither number comes from measured output.
  let work = 3 + 1 + 1 + 3 + 1 + 1 + 2 * 5 * edge_count
  let workspace = 1 + 1 + 2 + 1
  for viewed in [false, true] {
    let start = fn(control, slots, allowed, rows, paths) {
      let limits : @execution.ValueLimits = {
        max_work: allowed,
        max_nodes: 1000,
        max_text_bytes: 10000,
        max_depth: 50,
      }
      if viewed {
        @local_sga.start_traverse_view(
          control,
          preparation,
          prepared_sequence(owner),
          0,
          @graphs.producer_read_view(input).unwrap(),
          rows,
          limits,
          slots,
          10000,
          10000,
          [],
          max_paths=paths,
        ).unwrap()
      } else {
        @local_sga.start_traverse(
          control,
          preparation,
          prepared_sequence(owner),
          0,
          input,
          rows,
          limits,
          slots,
          10000,
          10000,
          [],
          max_paths=paths,
        ).unwrap()
      }
    }
    for quantum in [1, 7, 1024] {
      let active = start(@bounded.control(), workspace, work, 1, 1)
      let spent = Ref(0L)
      let finished = finish_traverse(active, quantum~, spent_work=Some(spent))
      assert_eq(finished.map(_ => true), Ok(true))
      let output = finished.unwrap()
      assert_eq(spent.val, work.to_int64())
      assert_eq(@execution.completed_row_count(output), 1)
      assert_eq(
        @execution.completed_output_row_wire(output, 0, 10000, 10000, 50).unwrap(),
        "{\"depth\":0,\"node_id\":" + id + ",\"start_id\":" + id + "}",
      )
      assert_true(@local_sga.cleanup_traverse(active).unwrap())
      for
        (slots, allowed, rows, paths, expected) in [
          (workspace - 1, work, 1, 1, @local_sga.TraversePathsWorkspaceLimit),
          (workspace, work - 1, 1, 1, @local_sga.TraversePathsWorkLimit),
          (workspace, work, 0, 1, @local_sga.TraversePathsOutputLimit),
          (workspace, work, 1, 0, @local_sga.TraversePathsSearchLimit),
        ] {
        let rejected = start(@bounded.control(), slots, allowed, rows, paths)
        assert_eq(
          finish_traverse(rejected, quantum~).unwrap_err(),
          @local_sga.TraversePathIssue(expected),
        )
        assert_true(@local_sga.cleanup_traverse(rejected).unwrap())
        assert_false(@local_sga.cleanup_traverse(rejected).unwrap())
        assert_false(@local_sga.traverse_cleanup_pending(rejected))
        assert_eq(@local_sga.traverse_private_entry_count(rejected), 0)
        assert_true(@graphs.producer_read_available(input))
      }
    }
    for prefix in 0..<work {
      let control = @bounded.control()
      let active = start(control, workspace, work, 1, 1)
      for index in 0..<prefix {
        assert_true(
          @local_sga.advance_traverse(active, 1)
          is Ok(@local_sga.TraverseContinue(work=spent, ..)) &&
          spent == (index + 1).to_int64(),
        )
      }
      assert_true(@bounded.request_cancel(control))
      assert_true(
        @local_sga.advance_traverse(active, 1)
        is Ok(@local_sga.TraverseStopped(_, work=spent, ..)) &&
        spent == prefix.to_int64(),
      )
      assert_true(@local_sga.cleanup_traverse(active).unwrap())
      assert_false(@local_sga.cleanup_traverse(active).unwrap())
      assert_false(@local_sga.traverse_cleanup_pending(active))
      assert_eq(@local_sga.traverse_private_entry_count(active), 0)
      assert_true(@graphs.producer_read_available(input))
    }
  }
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
}
