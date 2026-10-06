///|
enum KeyedPredicateBoundaryPoll {
  Pending(Int64)
  Complete(@execution.CompletedOutput, Int64)
  Rejected(String, Int64)
  Stopped(Int64)
}

///|
test "current TRAIL evaluates reached edge and nullable node predicates on demand" {
  let nodes = keyed_source_owner(
    "{\"id\":{\"type\":\"number\",\"nullable\":false},\"flag\":{\"type\":\"boolean\",\"nullable\":true}}",
    "[{\"id\":1,\"flag\":null},{\"id\":2,\"flag\":true}]",
  )
  let edges = keyed_source_owner(
    "{\"key\":{\"type\":\"number\",\"nullable\":false},\"src\":{\"type\":\"number\",\"nullable\":false},\"dst\":{\"type\":\"number\",\"nullable\":false},\"flag\":{\"type\":\"boolean\",\"nullable\":false}}",
    "[{\"key\":10,\"src\":1,\"dst\":2,\"flag\":true},{\"key\":11,\"src\":2,\"dst\":1,\"flag\":false}]",
  )
  let graph_owner = keyed_bridge_owner(
    nodes,
    edges,
    body=Some(
      (
        #|[{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["id"],"labels":[{"name":"Node","properties":{"mode":"columns","columns":[{"from":"flag","to":"f"}]}}]}],"edges":[{"name":"E","from":"edges","key":["key"],"source":{"definition":"N","key":["src"]},"target":{"definition":"N","key":["dst"]},"labels":[{"name":"R","properties":{"mode":"columns","columns":[{"from":"flag","to":"f"}]}}]}]},"as":"g"}]
      ),
    ),
  )
  let construction = @local_bridge.start_rows_to_property_graph(
    @bounded.control(),
    prepared_sequence(graph_owner),
    0,
    keyed_bridge_inputs(graph_owner, nodes, edges),
    carrier_graph_storage_limits(),
    8192L,
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
    is Some(@carrier_contract.GraphValue(contract)) else {
    fail("current Graph contract")
  }
  let domain = @carrier_contract.property_graph_domain(
    @carrier_contract.graph_property_definition(contract),
  )
  let node = fn(key : Int) {
    "{\"definition\":\"N\",\"domain\":\"" +
    domain +
    "\",\"key\":[" +
    key.to_string() +
    "],\"key_types\":[{\"kind\":\"number\"}]}"
  }
  let edge = fn(key : Int) {
    "{\"definition\":\"E\",\"domain\":\"" +
    domain +
    "\",\"key\":[" +
    key.to_string() +
    "],\"key_types\":[{\"kind\":\"number\"}]}"
  }
  for
    (start, edge_where, node_where, expected_edge, expected_end) in [
      (1, "f = TRUE", "f = TRUE", 10, 2),
      (2, "f = FALSE", "f IS NULL", 11, 1),
    ] {
    let owner = keyed_graph_receiver(
      graph_owner,
      body="[{\"from\":\"g\",\"traverse\":{\"start\":{\"ids\":[" +
        node(start) +
        "]},\"hops\":[{\"direction\":\"out\",\"edge_types\":[\"R\"],\"edge_where\":\"" +
        edge_where +
        "\",\"node_where\":\"" +
        node_where +
        "\"}],\"path_mode\":\"trail\",\"emit\":\"paths\"}}]",
    )
    let input = @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
    let preparation = task_test_completion(owner)
    for quantum in [1, 7] {
      let active = @local_sga.start_traverse(
        @bounded.control(),
        preparation,
        prepared_sequence(owner),
        0,
        input,
        2,
        {
          max_work: 10000,
          max_nodes: 10000,
          max_text_bytes: 10000,
          max_depth: 50,
        },
        10000,
        10000,
        10000,
        [],
      ).unwrap()
      let output = finish_traverse(active, quantum~).unwrap()
      assert_eq(@execution.completed_row_count(output), 1)
      assert_eq(
        @execution.completed_output_row_wire(output, 0, 10000, 10000, 50).unwrap(),
        "{\"edge_ids\":[" +
        property_graph_expected_json_wire(edge(expected_edge)) +
        "],\"end_id\":" +
        property_graph_expected_json_wire(node(expected_end)) +
        ",\"hop_count\":1,\"node_ids\":[" +
        property_graph_expected_json_wire(node(start)) +
        "," +
        property_graph_expected_json_wire(node(expected_end)) +
        "],\"start_id\":" +
        property_graph_expected_json_wire(node(start)) +
        "}",
      )
      assert_true(@local_sga.cleanup_traverse(active).unwrap())
      assert_false(@local_sga.cleanup_traverse(active).unwrap())
      assert_true(@graphs.producer_read_available(input))
    }
    let control = @bounded.control()
    let cancelled = @local_sga.start_traverse(
      control,
      preparation,
      prepared_sequence(owner),
      0,
      input,
      2,
      {
        max_work: 10000,
        max_nodes: 10000,
        max_text_bytes: 10000,
        max_depth: 50,
      },
      10000,
      10000,
      10000,
      [],
    ).unwrap()
    let mut reached_node_predicate = false
    for _ in 0..<1000 {
      guard @local_sga.advance_traverse(cancelled, 1)
        is Ok(@local_sga.TraverseContinue(..)) else {
        fail("predicate run completed before cancellation boundary")
      }
      if @local_sga.traverse_predicate_starts(cancelled) == 2 {
        reached_node_predicate = true
        break
      }
    }
    assert_true(reached_node_predicate)
    assert_true(@bounded.request_cancel(control))
    assert_true(
      @local_sga.advance_traverse(cancelled, 1)
      is Ok(@local_sga.TraverseStopped(_, ..)),
    )
    assert_true(@local_sga.traverse_cleanup_pending(cancelled))
    assert_true(@graphs.producer_read_available(input))
    assert_true(@local_sga.cleanup_traverse(cancelled).unwrap())
    assert_false(@local_sga.cleanup_traverse(cancelled).unwrap())
    assert_eq(@local_sga.traverse_private_entry_count(cancelled), 0)
    assert_true(@graphs.producer_read_available(input))
  }
  let patterned = keyed_graph_receiver(
    graph_owner,
    body="[{\"from\":\"g\",\"traverse\":{\"start\":{\"ids\":[" +
      node(1) +
      "]},\"hops\":[{\"direction\":\"out\",\"edge_where\":\"f = TRUE\",\"node_where\":\"f = TRUE\"},{\"direction\":\"out\",\"edge_where\":\"f = FALSE\",\"node_where\":\"f IS NULL\"}],\"path_mode\":\"trail\",\"emit\":\"paths\"}}]",
  )
  let patterned_input = @graphs.prepare_producer_read(
    patterned, 0, graph_owner, graph,
  ).unwrap()
  let patterned_execution = @local_sga.start_traverse(
    @bounded.control(),
    task_test_completion(patterned),
    prepared_sequence(patterned),
    0,
    patterned_input,
    2,
    { max_work: 10000, max_nodes: 10000, max_text_bytes: 10000, max_depth: 50, },
    10000,
    10000,
    10000,
    [],
  ).unwrap()
  let patterned_output = finish_traverse(patterned_execution, quantum=1).unwrap()
  assert_eq(@execution.completed_row_count(patterned_output), 1)
  assert_eq(
    @execution.completed_output_row_wire(patterned_output, 0, 10000, 10000, 50).unwrap(),
    "{\"edge_ids\":[" +
    property_graph_expected_json_wire(edge(10)) +
    "," +
    property_graph_expected_json_wire(edge(11)) +
    "],\"end_id\":" +
    property_graph_expected_json_wire(node(1)) +
    ",\"hop_count\":2,\"node_ids\":[" +
    property_graph_expected_json_wire(node(1)) +
    "," +
    property_graph_expected_json_wire(node(2)) +
    "," +
    property_graph_expected_json_wire(node(1)) +
    "],\"start_id\":" +
    property_graph_expected_json_wire(node(1)) +
    "}",
  )
  assert_true(@local_sga.cleanup_traverse(patterned_execution).unwrap())
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
}

///|
test "keyed node and edge predicates preserve exact work workspace and every private stop boundary" {
  let nodes = keyed_source_owner(
    "{\"id\":{\"type\":\"number\",\"nullable\":false},\"flag\":{\"type\":\"boolean\",\"nullable\":false}}",
    "[{\"id\":1,\"flag\":true}]",
  )
  let edges = keyed_source_owner(
    "{\"key\":{\"type\":\"number\",\"nullable\":false},\"src\":{\"type\":\"number\",\"nullable\":false},\"dst\":{\"type\":\"number\",\"nullable\":false},\"flag\":{\"type\":\"boolean\",\"nullable\":false}}",
    "[{\"key\":10,\"src\":1,\"dst\":1,\"flag\":true}]",
  )
  let graph_owner = keyed_bridge_owner(
    nodes,
    edges,
    body=Some(
      (
        #|[{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["id"],"labels":[{"name":"Node","properties":{"mode":"columns","columns":[{"from":"flag","to":"f"}]}}]}],"edges":[{"name":"E","from":"edges","key":["key"],"source":{"definition":"N","key":["src"]},"target":{"definition":"N","key":["dst"]},"labels":[{"name":"R","properties":{"mode":"columns","columns":[{"from":"flag","to":"f"}]}}]}]},"as":"g"}]
      ),
    ),
  )
  let construction = @local_bridge.start_rows_to_property_graph(
    @bounded.control(),
    prepared_sequence(graph_owner),
    0,
    keyed_bridge_inputs(graph_owner, nodes, edges),
    carrier_graph_storage_limits(),
    8192L,
    1000,
    () => true,
  ).unwrap()
  guard keyed_bridge_terminal(construction) is @local_bridge.Complete(graph, ..) else {
    fail("constructor failed")
  }
  // Independent phase calculation, not observed output: the Boolean equality
  // enters binary/field/literal and returns each (6 transitions); Boolean
  // comparison has no variable-size charge; the one-byte reference costs 1.
  // Binary children are borrowed; peak expression workspace is one frame.
  // MATCH retains two sort entries, one output column and one property binding.
  let expression_work = 6 + 1
  let workspace = 2 + 1 + 1 + 1
  for nodes_match in [true, false] {
    let op = if nodes_match { "match_nodes" } else { "match_edges" }
    let definition = if nodes_match { "N" } else { "E" }
    let owner = keyed_graph_receiver(
      graph_owner,
      body="[{\"from\":\"g\",\"" +
        op +
        "\":{\"definition\":\"" +
        definition +
        "\",\"where\":\"f = TRUE\",\"fields\":[\"f\"]}}]",
    )
    let input = @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
    let preparation = task_test_completion(owner)
    // Scratch, one property binding, six predicate transitions, read, commit,
    // finish; edge MATCH also charges its edge-selection transition.
    let work = 1 + 1 + 6 + 1 + 1 + 1 + (if nodes_match { 0 } else { 1 })
    for viewed in [false, true] {
      let start = fn(control, slots, allowed_work, expression_limit) {
        let limits : @execution.ValueLimits = {
          max_work: expression_limit,
          max_nodes: 1000,
          max_text_bytes: 1000,
          max_depth: 50,
        }
        if nodes_match {
          let active = if viewed {
            @local_sga.start_match_nodes_view(
              control,
              preparation,
              prepared_sequence(owner),
              0,
              @graphs.producer_read_view(input).unwrap(),
              1,
              limits,
              slots,
              10000,
              10000,
              [],
              control_work_limit=Some(allowed_work),
            ).unwrap()
          } else {
            @local_sga.start_match_nodes(
              control,
              preparation,
              prepared_sequence(owner),
              0,
              input,
              1,
              limits,
              slots,
              10000,
              10000,
              [],
              control_work_limit=Some(allowed_work),
            ).unwrap()
          }
          (
            quantum => {
              match @local_sga.advance_match_nodes(active, quantum).unwrap() {
                @local_sga.MatchNodesContinue(work~, ..) => Pending(work)
                @local_sga.MatchNodesComplete(output, work~, ..) =>
                  Complete(output, work)
                @local_sga.MatchNodesStopped(_, work~, ..) => Stopped(work)
                @local_sga.MatchNodesFailed(
                  @local_sga.MatchNodesPredicate(@execution.WorkspaceLimit),
                  work~,
                  ..
                ) => Rejected("workspace", work)
                @local_sga.MatchNodesFailed(
                  @local_sga.MatchNodesPredicate(@execution.ControlLimit),
                  work~,
                  ..
                ) => Rejected("expression-work", work)
                @local_sga.MatchNodesFailed(
                  @local_sga.MatchNodesWorkLimit,
                  work~,
                  ..
                ) => Rejected("control-work", work)
                _ => fail("unexpected node predicate failure")
              }
            },
            fn() { @local_sga.cleanup_match_nodes(active).unwrap() },
            fn() { @local_sga.match_nodes_cleanup_pending(active) },
            fn() { @local_sga.match_nodes_scratch_slots(active) },
          )
        } else {
          let active = if viewed {
            @local_sga.start_match_edges_view(
              control,
              preparation,
              prepared_sequence(owner),
              0,
              @graphs.producer_read_view(input).unwrap(),
              1,
              limits,
              slots,
              10000,
              10000,
              [],
              control_work_limit=Some(allowed_work),
            ).unwrap()
          } else {
            @local_sga.start_match_edges(
              control,
              preparation,
              prepared_sequence(owner),
              0,
              input,
              1,
              limits,
              slots,
              10000,
              10000,
              [],
              control_work_limit=Some(allowed_work),
            ).unwrap()
          }
          (
            quantum => {
              match @local_sga.advance_match_edges(active, quantum).unwrap() {
                @local_sga.MatchEdgesContinue(work~, ..) => Pending(work)
                @local_sga.MatchEdgesComplete(output, work~, ..) =>
                  Complete(output, work)
                @local_sga.MatchEdgesStopped(_, work~, ..) => Stopped(work)
                @local_sga.MatchEdgesFailed(
                  @local_sga.MatchEdgesPredicate(@execution.WorkspaceLimit),
                  work~,
                  ..
                ) => Rejected("workspace", work)
                @local_sga.MatchEdgesFailed(
                  @local_sga.MatchEdgesPredicate(@execution.ControlLimit),
                  work~,
                  ..
                ) => Rejected("expression-work", work)
                @local_sga.MatchEdgesFailed(
                  @local_sga.MatchEdgesWorkLimit,
                  work~,
                  ..
                ) => Rejected("control-work", work)
                _ => fail("unexpected edge predicate failure")
              }
            },
            fn() { @local_sga.cleanup_match_edges(active).unwrap() },
            fn() { @local_sga.match_edges_cleanup_pending(active) },
            fn() { @local_sga.match_edges_scratch_slots(active) },
          )
        }
      }
      for quantum in [1, 7, 1024] {
        for
          (slots, allowed_work, expression_limit, expected) in [
            (workspace, work, expression_work, "complete"),
            (workspace - 1, work, expression_work, "workspace"),
            (workspace, work, expression_work - 1, "expression-work"),
            (workspace, work - 1, expression_work, "control-work"),
          ] {
          let (advance, cleanup, pending, scratch) = start(
            @bounded.control(),
            slots,
            allowed_work,
            expression_limit,
          )
          let mut terminal = false
          for _ in 0..<30 {
            match advance(quantum) {
              Pending(_) => ()
              Complete(output, spent) => {
                assert_eq(expected, "complete")
                assert_eq(spent, work.to_int64())
                assert_eq(@execution.completed_row_count(output), 1)
                assert_eq(
                  @execution.completed_output_row_wire(
                    output, 0, 10000, 10000, 50,
                  ).unwrap(),
                  "{\"f\":true}",
                )
                terminal = true
                break
              }
              Rejected(reason, spent) => {
                assert_eq(reason, expected)
                assert_true(spent <= allowed_work.to_int64())
                terminal = true
                break
              }
              _ => fail("unexpected stop")
            }
          }
          assert_true(terminal)
          assert_true(pending())
          assert_true(cleanup())
          assert_false(cleanup())
          assert_false(pending())
          assert_eq(scratch(), 0)
          assert_true(@graphs.producer_read_available(input))
        }
      }
      for prefix in 0..<work {
        let control = @bounded.control()
        let (advance, cleanup, pending, scratch) = start(
          control, workspace, work, expression_work,
        )
        for index in 0..<prefix {
          assert_true(
            advance(1) is Pending(spent) && spent == (index + 1).to_int64(),
          )
        }
        assert_true(@bounded.request_cancel(control))
        assert_true(advance(1) is Stopped(spent) && spent == prefix.to_int64())
        assert_true(cleanup())
        assert_false(cleanup())
        assert_false(pending())
        assert_eq(scratch(), 0)
        assert_true(@graphs.producer_read_available(input))
      }
    }
  }
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
}
